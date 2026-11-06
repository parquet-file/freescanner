import 'magic_filter.dart';

/// data/models/scanned_page.dart — one page of a scanned document.
///
/// The scanner saves the original JPEG as `pNNN.jpg`. When the user applies a
/// filter or rotation we render a *processed* copy next to it
/// (`pNNN_f2_r90.jpg`) and keep the original untouched, so filters can always
/// be undone losslessly.
class ScannedPage {
  ScannedPage({
    required this.file,
    this.filter = MagicFilter.original,
    this.rotation = 0,
    this.processedFile,
  });

  /// File name of the untouched original, relative to the document folder.
  final String file;

  /// Applied magic filter.
  MagicFilter filter;

  /// Rotation in degrees (0 / 90 / 180 / 270), clockwise.
  int rotation;

  /// File name of the rendered (filter + rotation) copy, or null when the
  /// page is still in its original state.
  String? processedFile;

  /// The file the UI and PDF exporter should display: the processed copy
  /// when present, otherwise the original.
  String get displayFile => processedFile ?? file;

  /// Normalized rotation (0..359, multiple of 90).
  static int normalizeRotation(int degrees) => ((degrees % 360) + 360) % 360;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'file': file,
        'filter': filter.key,
        'rotation': rotation,
        'processed': processedFile,
      };

  factory ScannedPage.fromJson(Map<String, dynamic> json) => ScannedPage(
        file: json['file'] as String? ?? '',
        filter: MagicFilter.fromKey(json['filter'] as String?),
        rotation:
            normalizeRotation(json['rotation'] as int? ?? 0),
        processedFile: json['processed'] as String?,
      );
}
