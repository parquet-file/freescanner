import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';

/// services/document_scanner_service.dart — thin wrapper around Google's ML
/// Kit Document Scanner (fully on-device):
///   * automatic edge detection + cropping
///   * perspective correction
///   * cleanup filters (the `filter` mode exposes ML Kit's own enhancement)
///   * multi-page capture with a page limit, plus gallery import
///
/// Returns the scanned page image paths (JPEG), or an empty list when the
/// user cancels.
class DocumentScannerService {
  DocumentScannerService({this.pageLimit = 10});

  /// Maximum pages per scan session.
  final int pageLimit;

  DocumentScanner? _scanner;

  /// Runs the full-screen scanner. Empty list ⇒ user cancelled.
  Future<List<String>> scan() async {
    final options = DocumentScannerOptions(
      documentFormats: const <DocumentFormat>{DocumentFormat.jpeg},
      mode: ScannerMode.filter,
      pageLimit: pageLimit,
      isGalleryImport: true,
    );
    _scanner = DocumentScanner(options: options);
    try {
      final result = await _scanner!.scanDocument();
      final images =
          (result.images ?? const <String>[]).where((e) => e.isNotEmpty).toList()
            ..sort();
      return images;
    } on PlatformException catch (e) {
      // User backing out of the scanner surfaces as a cancelled ActivityResult.
      final code = e.code.toLowerCase();
      if (code.contains('cancel')) return const <String>[];
      debugPrint('document scanner error: ${e.code} ${e.message}');
      rethrow;
    } finally {
      _close();
    }
  }

  void _close() {
    try {
      _scanner?.close();
    } catch (_) {
      // The scanner activity already released its resources.
    }
    _scanner = null;
  }

  void dispose() => _close();
}
