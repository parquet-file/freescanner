import 'package:flutter/foundation.dart';

import '../data/models/scanned_document.dart';
import '../data/repositories/document_repository.dart';
import '../services/document_scanner_service.dart';

/// viewmodels/library_viewmodel.dart — the home screen: the document list
/// plus the scan flow.
class LibraryViewModel extends ChangeNotifier {
  LibraryViewModel({
    required DocumentRepository repository,
    DocumentScannerService? scannerService,
  })  : _repository = repository,
        _scannerService = scannerService ?? DocumentScannerService();

  final DocumentRepository _repository;
  final DocumentScannerService _scannerService;

  List<ScannedDocument> _documents = const <ScannedDocument>[];
  bool _loading = false;
  bool _scanning = false;
  String? _error;

  List<ScannedDocument> get documents => _documents;
  bool get loading => _loading;
  bool get scanning => _scanning;
  String? get error => _error;

  String displayPath(ScannedDocument doc, int pageIndex) =>
      _repository.displayPath(doc, pageIndex);

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _documents = await _repository.listDocuments();
    } catch (e) {
      _error = 'Could not read saved documents.';
      debugPrint('library load failed: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Opens the ML Kit scanner and saves the result as a new document.
  /// Returns the new document, or null when the user cancelled / nothing was
  /// scanned.
  Future<ScannedDocument?> scanNewDocument() async {
    if (_scanning) return null;
    _scanning = true;
    _error = null;
    notifyListeners();
    try {
      final images = await _scannerService.scan();
      if (images.isEmpty) return null;
      final doc = await _repository.createDocument(imagePaths: images);
      _documents = await _repository.listDocuments();
      return doc;
    } catch (e) {
      _error = 'Scanning failed. Please try again.';
      debugPrint('scan failed: $e');
      return null;
    } finally {
      _scanning = false;
      notifyListeners();
    }
  }

  Future<void> renameDocument(String id, String title) async {
    final doc = _documents.where((d) => d.id == id).firstOrNull;
    if (doc == null || title.trim().isEmpty) return;
    doc.title = title.trim();
    await _repository.save(doc);
    await load();
  }

  Future<void> deleteDocument(String id) async {
    await _repository.deleteDocument(id);
    _documents = _documents.where((d) => d.id != id).toList();
    notifyListeners();
  }
}
