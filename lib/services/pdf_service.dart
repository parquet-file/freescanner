import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/utils.dart' as utils;

/// services/pdf_service.dart — multi-page PDF export.
///
/// Each page is sized to the image's aspect ratio, capped at A4, so scans
/// are never cropped, stretched or letterboxed.
class PdfService {
  const PdfService();

  static const double _a4Short = 595.28; // pt
  static const double _a4Long = 841.89; // pt
  static const double _margin = 16;

  /// Builds a PDF from the given JPEG page paths and writes it to
  /// `exports/FreeScanner-<name>-<timestamp>.pdf`. Returns the file path.
  Future<String> export({
    required List<String> pageImagePaths,
    required String documentTitle,
    required Directory exportsDir,
  }) async {
    final doc = pw.Document(
      title: documentTitle,
      author: 'FreeScanner',
      creator: 'FreeScanner',
    );

    for (final path in pageImagePaths) {
      final bytes = await File(path).readAsBytes();
      final image = pw.MemoryImage(bytes);
      final format = _pageFormatFor(image.width ?? 0, image.height ?? 0);
      doc.addPage(
        pw.Page(
          pageFormat: format,
          margin: const pw.EdgeInsets.all(_margin),
          build: (context) => pw.Center(
            child: pw.Image(image, fit: pw.BoxFit.contain),
          ),
        ),
      );
    }

    if (!exportsDir.existsSync()) exportsDir.createSync(recursive: true);
    final safeTitle = _fileSafe(documentTitle);
    final out = File(
      '${exportsDir.path}/FreeScanner-$safeTitle-${utils.fileTimestamp()}.pdf',
    );
    await out.writeAsBytes(await doc.save(), flush: true);
    debugPrint('pdf exported: ${out.path}');
    return out.path;
  }

  /// Chooses a page size that preserves the image aspect, capped at A4.
  PdfPageFormat _pageFormatFor(int width, int height) {
    if (width <= 0 || height <= 0) return PdfPageFormat.a4;
    final aspect = width / height;
    double pageW;
    double pageH;
    if (aspect >= 1) {
      // Landscape source.
      pageW = _a4Long;
      pageH = pageW / aspect;
      if (pageH > _a4Short) {
        pageH = _a4Short;
        pageW = pageH * aspect;
      }
    } else {
      // Portrait source.
      pageW = _a4Short;
      pageH = pageW / aspect;
      if (pageH > _a4Long) {
        pageH = _a4Long;
        pageW = pageH * aspect;
      }
    }
    return PdfPageFormat(pageW, pageH,
        marginTop: _margin, marginLeft: _margin, marginRight: _margin, marginBottom: _margin);
  }

  String _fileSafe(String title) {
    final cleaned = title.replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '').trim();
    return cleaned.isEmpty ? 'document' : cleaned.replaceAll(' ', '-');
  }
}
