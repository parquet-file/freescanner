import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/utils.dart' as utils;
import '../models/magic_filter.dart';
import '../models/scanned_document.dart';
import '../models/scanned_page.dart';

/// data/repositories/document_repository.dart — filesystem-first local
/// storage. Everything the app creates lives under
/// `<app-documents>/freescanner-documents/`:
///
///     <id>/meta.json          document metadata
///     <id>/p001.jpg …         untouched scanner originals
///     <id>/p001_f2_r90.jpg    rendered copies (filter + rotation)
///     <id>/ocr/eng.txt        last OCR result per language
///     <id>/exports/…          generated PDFs
///
/// No permissions needed (app-private storage), survives app updates.
class DocumentRepository {
  DocumentRepository({required Directory baseDir})
      : root = Directory(p.join(baseDir.path, 'freescanner-documents'));

  final Directory root;

  Directory documentDir(String id) => Directory(p.join(root.path, id));

  Directory get exportsRoot {
    final d = Directory(p.join(root.path, 'exports'));
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  /// All documents, newest first. Missing/corrupt folders are skipped.
  Future<List<ScannedDocument>> listDocuments() async {
    if (!root.existsSync()) return const <ScannedDocument>[];
    final docs = <ScannedDocument>[];
    for (final entity in root.listSync(followLinks: false)) {
      if (entity is! Directory) continue;
      final meta = File(p.join(entity.path, 'meta.json'));
      if (!meta.existsSync()) continue;
      try {
        final json =
            jsonDecode(meta.readAsStringSync()) as Map<String, dynamic>;
        final doc = ScannedDocument.fromJson(json);
        if (doc.id.isNotEmpty && doc.pages.isNotEmpty) docs.add(doc);
      } catch (_) {
        // Corrupt meta — skip this document rather than crash the library.
      }
    }
    docs.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return docs;
  }

  Future<ScannedDocument?> getDocument(String id) async {
    final meta = File(p.join(documentDir(id).path, 'meta.json'));
    if (!meta.existsSync()) return null;
    try {
      final json = jsonDecode(meta.readAsStringSync()) as Map<String, dynamic>;
      return ScannedDocument.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  /// Copies scanned JPEGs into a fresh document folder and writes meta.json.
  Future<ScannedDocument> createDocument({
    required List<String> imagePaths,
    String? title,
  }) async {
    final now = DateTime.now();
    final id = 'doc-${utils.fileTimestamp(now)}-${utils.randomIdSuffix(6)}';
    final dir = documentDir(id);
    dir.createSync(recursive: true);

    final pages = <ScannedPage>[];
    var index = 0;
    for (final src in imagePaths) {
      index += 1;
      final name = 'p${index.toString().padLeft(3, '0')}.jpg';
      final dst = File(p.join(dir.path, name));
      await File(src).copy(dst.path);
      pages.add(ScannedPage(file: name));
    }

    final doc = ScannedDocument(
      id: id,
      title: title?.trim().isNotEmpty == true
          ? title!.trim()
          : 'Scan ${now.day} ${_monthName(now.month)} ${now.year}',
      createdAt: now,
      updatedAt: now,
      pages: pages,
    );
    await save(doc);
    return doc;
  }

  /// Persists meta.json.
  Future<void> save(ScannedDocument doc) async {
    doc.updatedAt = DateTime.now();
    final dir = documentDir(doc.id);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final meta = File(p.join(dir.path, 'meta.json'));
    await meta.writeAsString(const JsonEncoder.withIndent('  ').convert(doc));
  }

  /// Deletes the whole document folder (originals, renders, OCR, exports).
  Future<void> deleteDocument(String id) async {
    final dir = documentDir(id);
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
  }

  /// File name for a rendered copy of [page].
  String processedFileName(ScannedPage page, int pageIndex) =>
      'p${(pageIndex + 1).toString().padLeft(3, '0')}'
      '_f${page.filter.key}_r${page.rotation}.jpg';

  /// Writes the rendered copy for a page and updates its metadata, removing
  /// any previous render so disk usage stays bounded.
  Future<void> storeProcessed(
    ScannedDocument doc,
    int pageIndex, {
    required List<int> bytes,
  }) async {
    final dir = documentDir(doc.id);
    final page = doc.pages[pageIndex];
    final previous = page.processedFile;
    final name = processedFileName(page, pageIndex);
    await File(p.join(dir.path, name)).writeAsBytes(bytes, flush: true);
    if (previous != null && previous != name) {
      final old = File(p.join(dir.path, previous));
      if (old.existsSync()) await old.delete();
    }
    page.processedFile = name;
    await save(doc);
  }

  /// Removes the rendered copy (filter reset to Original).
  Future<void> clearProcessed(ScannedDocument doc, int pageIndex) async {
    final dir = documentDir(doc.id);
    final page = doc.pages[pageIndex];
    if (page.processedFile != null) {
      final f = File(p.join(dir.path, page.processedFile!));
      if (f.existsSync()) await f.delete();
      page.processedFile = null;
    }
    page.filter = MagicFilter.original;
    page.rotation = 0;
    await save(doc);
  }

  /// Absolute path of the file the UI should display for a page.
  String displayPath(ScannedDocument doc, int pageIndex) =>
      p.join(documentDir(doc.id).path, doc.pages[pageIndex].displayFile);

  /// Absolute path of the untouched original for a page.
  String originalPath(ScannedDocument doc, int pageIndex) =>
      p.join(documentDir(doc.id).path, doc.pages[pageIndex].file);

  // ---- OCR results ---------------------------------------------------------

  Future<void> saveOcr(String docId, String language, String text) async {
    final dir = Directory(p.join(documentDir(docId).path, 'ocr'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    await File(p.join(dir.path, '$language.txt')).writeAsString(text);
  }

  Future<String?> loadOcr(String docId, String language) async {
    final f = File(p.join(documentDir(docId).path, 'ocr', '$language.txt'));
    if (!f.existsSync()) return null;
    return f.readAsString();
  }

  String _monthName(int month) => const [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ][month - 1];
}
