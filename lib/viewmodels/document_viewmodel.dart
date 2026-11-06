import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/utils.dart' as utils;

// clampInt is re-exported via utils for index-safe clamping.
import '../data/models/magic_filter.dart';
import '../data/models/scanned_document.dart';
import '../data/repositories/document_repository.dart';
import '../services/ad_service.dart';
import '../services/ad_policy.dart';
import '../services/image_filter_service.dart';
import '../services/pdf_service.dart';

/// viewmodels/document_viewmodel.dart — editing one document: per-page magic
/// filters, rotation, reordering, deletion, PDF export (with the
/// backend-gated interstitial) and page sharing.
class DocumentViewModel extends ChangeNotifier {
  DocumentViewModel({
    required DocumentRepository repository,
    required AdService adService,
    required String documentId,
    ImageFilterService? filterService,
    PdfService? pdfService,
  })  : _repository = repository,
        _adService = adService,
        _documentId = documentId,
        _filterService = filterService ?? const ImageFilterService(),
        _pdfService = pdfService ?? const PdfService();

  final DocumentRepository _repository;
  final AdService _adService;
  final String _documentId;
  final ImageFilterService _filterService;
  final PdfService _pdfService;

  ScannedDocument? _document;
  int _currentPage = 0;
  bool _busy = false;
  bool _exporting = false;
  String? _error;
  String? _lastExportPath;

  ScannedDocument? get document => _document;
  int get currentPage => _currentPage;
  bool get busy => _busy;
  bool get exporting => _exporting;
  String? get error => _error;
  String? get lastExportPath => _lastExportPath;

  bool get hasPages => (_document?.pages.isNotEmpty ?? false);

  String get displayPathCurrent {
    final doc = _document;
    if (doc == null || doc.pages.isEmpty) return '';
    final index = utils.clampInt(_currentPage, 0, doc.pages.length - 1);
    return _repository.displayPath(doc, index);
  }

  String displayPathFor(int pageIndex) =>
      _repository.displayPath(_document!, pageIndex);

  Future<void> load() async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      _document = await _repository.getDocument(_documentId);
      _currentPage = 0;
      if (_document == null) {
        _error = 'This document no longer exists.';
      }
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void setPage(int index) {
    final doc = _document;
    if (doc == null) return;
    if (index >= 0 && index < doc.pages.length && index != _currentPage) {
      _currentPage = index;
      notifyListeners();
    }
  }

  /// Applies a magic filter to the current page (Original clears the render).
  Future<void> applyFilter(MagicFilter filter) async {
    await _editCurrent(
      filter: filter,
      rotationDelta: 0,
    );
  }

  /// Rotates the current page by 90° clockwise.
  Future<void> rotateCurrentPage() async {
    await _editCurrent(
      filter: null,
      rotationDelta: 90,
    );
  }

  Future<void> _editCurrent({MagicFilter? filter, required int rotationDelta}) async {
    final doc = _document;
    if (doc == null || doc.pages.isEmpty || _busy) return;
    final index = utils.clampInt(_currentPage, 0, doc.pages.length - 1);
    final page = doc.pages[index];

    final nextFilter = filter ?? page.filter;
    final nextRotation = ScannedRotation.normalize(page.rotation + rotationDelta);

    // Back to pristine state → drop the rendered copy.
    if (nextFilter == MagicFilter.original && nextRotation == 0) {
      _busy = true;
      notifyListeners();
      try {
        await _repository.clearProcessed(doc, index);
        _document = await _repository.getDocument(_documentId);
      } finally {
        _busy = false;
        notifyListeners();
      }
      return;
    }

    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final source = _repository.originalPath(doc, index);
      final bytes = await _filterService.process(
        sourcePath: source,
        filter: nextFilter,
        rotation: nextRotation,
      );
      page.filter = nextFilter;
      page.rotation = nextRotation;
      await _repository.storeProcessed(doc, index, bytes: bytes);
      _document = await _repository.getDocument(_documentId);
    } catch (e) {
      _error = 'Could not apply the filter to this page.';
      debugPrint('filter failed: $e');
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> movePage(int from, int to) async {
    final doc = _document;
    if (doc == null || _busy) return;
    if (from < 0 || from >= doc.pages.length || to < 0 || to >= doc.pages.length) {
      return;
    }
    final page = doc.pages.removeAt(from);
    doc.pages.insert(to, page);
    _currentPage = to;
    await _repository.save(doc);
    notifyListeners();
  }

  Future<void> deleteCurrentPage() async {
    final doc = _document;
    if (doc == null || _busy) return;
    if (doc.pages.length <= 1) {
      _error = 'A document needs at least one page.';
      notifyListeners();
      return;
    }
    _busy = true;
    notifyListeners();
    try {
      doc.pages.removeAt(_currentPage);
      _currentPage = utils.clampInt(_currentPage, 0, doc.pages.length - 1);
      await _repository.save(doc);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// "Save as PDF": builds the multi-page PDF, then honours the backend
  /// interstitial switch (ad shows BEFORE the share sheet so the exported
  /// file is ready the moment the ad closes).
  Future<String?> exportPdf() async {
    final doc = _document;
    if (doc == null || doc.pages.isEmpty || _exporting) return null;
    _exporting = true;
    _error = null;
    notifyListeners();
    try {
      // Interstitial (only when the backend says ads are ON for this trigger).
      await _adService.maybeShowInterstitial(InterstitialTrigger.exportPdf);

      final paths = [
        for (var i = 0; i < doc.pages.length; i++) _repository.displayPath(doc, i),
      ];
      final out = await _pdfService.export(
        pageImagePaths: paths,
        documentTitle: doc.title,
        exportsDir: _repository.exportsRoot,
      );
      _lastExportPath = out;
      return out;
    } catch (e) {
      _error = 'PDF export failed.';
      debugPrint('pdf export failed: $e');
      return null;
    } finally {
      _exporting = false;
      notifyListeners();
    }
  }

  /// Shares the current page image (optionally gated by the export-image
  /// interstitial switch).
  Future<String?> shareCurrentPage({bool withAd = true}) async {
    final doc = _document;
    if (doc == null || doc.pages.isEmpty) return null;
    if (withAd) {
      await _adService.maybeShowInterstitial(InterstitialTrigger.exportImage);
    }
    final index = utils.clampInt(_currentPage, 0, doc.pages.length - 1);
    return _repository.displayPath(doc, index);
  }

  /// Relative PDF name for the share sheet / snackbar.
  String exportName() =>
      'FreeScanner-${_document?.title ?? 'document'}-${utils.fileTimestamp()}'
          .replaceAll(' ', '-');

  bool fileExists(String path) => File(path).existsSync();
}
