import 'package:flutter/foundation.dart';

import '../core/utils.dart' as utils;
import '../data/models/scanned_document.dart';
import '../data/repositories/document_repository.dart';
import '../services/ocr_service.dart';

/// OCR languages supported by the app.
enum OcrLanguage {
  english('eng', 'English'),
  bengali('ben', 'বাংলা (Beta)');

  const OcrLanguage(this.key, this.label);
  final String key;
  final String label;

  bool get requiresDisclaimer => this == OcrLanguage.bengali;
}

/// viewmodels/ocr_viewmodel.dart — text extraction for one document:
/// current page, or all pages concatenated.
class OcrViewModel extends ChangeNotifier {
  OcrViewModel({
    required DocumentRepository repository,
    required this.document,
    OcrService? ocrService,
  })  : _repository = repository,
        _ocrService = ocrService ?? OcrService.instance;

  final DocumentRepository _repository;
  final OcrService _ocrService;
  final ScannedDocument document;

  OcrLanguage _language = OcrLanguage.english;
  bool _running = false;
  String _text = '';
  String? _error;
  DateTime? _lastRunAt;
  bool _loadedSaved = false;

  OcrLanguage get language => _language;
  bool get running => _running;
  String get text => _text;
  String? get error => _error;
  DateTime? get lastRunAt => _lastRunAt;

  void setLanguage(OcrLanguage language) {
    if (_language != language) {
      _language = language;
      _loadedSaved = false;
      _text = '';
      _error = null;
      notifyListeners();
    }
  }

  /// Loads the saved result for the current language (if any) without
  /// re-running OCR.
  Future<void> loadSaved() async {
    if (_loadedSaved) return;
    _loadedSaved = true;
    final saved = await _repository.loadOcr(document.id, _language.key);
    if (saved != null && saved.isNotEmpty) {
      _text = saved;
      notifyListeners();
    }
  }

  /// Runs OCR over one page or every page of the document.
  Future<String> run({required bool allPages}) async {
    if (_running || document.pages.isEmpty) return _text;
    _running = true;
    _error = null;
    notifyListeners();
    try {
      final buffer = StringBuffer();
      final indices = allPages
          ? List<int>.generate(document.pages.length, (i) => i)
          : <int>[
              document.pages.length == 1
                  ? 0
                  : _pageForOcr(),
            ];
      for (var i = 0; i < indices.length; i++) {
        final pageIndex = indices[i];
        final path = _repository.displayPath(document, pageIndex);
        final pageText = _language == OcrLanguage.bengali
            ? await _ocrService.recognizeBengali(path)
            : await _ocrService.recognizeEnglish(path);
        if (allPages && document.pages.length > 1) {
          if (i > 0) buffer.writeln();
          buffer.writeln('— Page ${pageIndex + 1} —');
        }
        buffer.writeln(pageText);
      }
      _text = buffer.toString().trim();
      _lastRunAt = DateTime.now();
      await _repository.saveOcr(document.id, _language.key, _text);
      document.ocrRuns[_language.key] = _lastRunAt!.toIso8601String();
      return _text;
    } catch (e) {
      _error = _language == OcrLanguage.bengali
          ? 'Bengali OCR failed on this page. Try a sharper photo or more light.'
          : 'Text recognition failed. Please try again.';
      debugPrint('ocr failed: $e');
      return '';
    } finally {
      _running = false;
      notifyListeners();
    }
  }

  /// The page OCR should target — the current page in the viewer, tracked by
  /// the screen. Defaults to the first page.
  int _targetPage = 0;

  set targetPage(int page) => _targetPage = page;

  int _pageForOcr() =>
      utils.clampInt(_targetPage, 0, document.pages.length - 1);
}
