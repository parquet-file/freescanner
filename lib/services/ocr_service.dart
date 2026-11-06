import 'package:flutter/foundation.dart';

import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// services/ocr_service.dart — on-device OCR with two engines:
///
///   * English  → ML Kit text recognition (Latin). Superb accuracy, fully
///                offline, the same engine Google Lens uses.
///   * Bengali  → Tesseract with the bundled ben+eng traineddata.
///                BETA — the UI shows a disclaimer before every Bengali run.
class OcrService {
  OcrService._();

  static final OcrService instance = OcrService._();

  TextRecognizer? _latinRecognizer;

  /// Extracts English text from a page image (fully offline).
  Future<String> recognizeEnglish(String imagePath) async {
    _latinRecognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final recognized = await _latinRecognizer!.processImage(inputImage);
      return _cleanText(recognized.text);
    } finally {
      // Keep the recognizer warm across pages; released in [dispose].
    }
  }

  /// Extracts Bengali text (with English fallback mixed in — Tesseract
  /// handles 'ben+eng' models together). Runs fully on-device against the
  /// bundled tessdata assets.
  Future<String> recognizeBengali(String imagePath) async {
    final text = await FlutterTesseractOcr.extractText(
      imagePath,
      language: 'ben+eng',
      args: <String, String>{'preserve_interword_spaces': '1'},
    );
    return _cleanText(text);
  }

  /// Normalizes engine output: trims, collapses >2 blank lines, strips the
  /// NUL characters Tesseract sometimes emits.
  String _cleanText(String raw) {
    final cleaned = raw.replaceAll('\u0000', '');
    final lines = cleaned.split('\n').map((l) => l.trimRight()).toList();
    final out = <String>[];
    var blank = 0;
    for (final line in lines) {
      if (line.trim().isEmpty) {
        blank += 1;
        if (blank <= 1) out.add('');
      } else {
        blank = 0;
        out.add(line);
      }
    }
    return out.join('\n').trim();
  }

  @mustCallSuper
  void dispose() {
    _latinRecognizer?.close();
    _latinRecognizer = null;
  }
}
