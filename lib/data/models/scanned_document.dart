import 'scanned_page.dart';

/// data/models/scanned_document.dart — a multi-page scanned document,
/// persisted as `<documents>/<id>/meta.json` on the device.
class ScannedDocument {
  ScannedDocument({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    List<ScannedPage>? pages,
    Map<String, String>? ocrRuns,
  })  : pages = pages ?? <ScannedPage>[],
        ocrRuns = ocrRuns ?? <String, String>{};

  final String id;
  String title;
  DateTime createdAt;
  DateTime updatedAt;

  final List<ScannedPage> pages;

  /// OCR language key → ISO timestamp of the last run (text lives in
  /// `ocr/<language>.txt` next to meta.json).
  final Map<String, String> ocrRuns;

  bool get isEmpty => pages.isEmpty;

  int get pageCount => pages.length;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'pages': pages.map((p) => p.toJson()).toList(),
        'ocr': ocrRuns,
      };

  factory ScannedDocument.fromJson(Map<String, dynamic> json) =>
      ScannedDocument(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? 'Document',
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
        updatedAt:
            DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
        pages: (json['pages'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(ScannedPage.fromJson)
            .toList(),
        ocrRuns: (json['ocr'] as Map<String, dynamic>? ?? const <String, dynamic>{})
            .map((k, dynamic v) => MapEntry(k, v.toString())),
      );
}
