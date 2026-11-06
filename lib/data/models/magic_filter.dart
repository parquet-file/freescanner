/// data/models/magic_filter.dart — the CamScanner-style enhancement filters.
library;

/// Magic filters applicable to a scanned page.
enum MagicFilter {
  original,
  enhance,
  blackWhite,
  lighten,
  sharp;

  /// Stable serialization key (persisted in meta.json).
  String get key {
    switch (this) {
      case MagicFilter.original:
        return 'original';
      case MagicFilter.enhance:
        return 'enhance';
      case MagicFilter.blackWhite:
        return 'bw';
      case MagicFilter.lighten:
        return 'lighten';
      case MagicFilter.sharp:
        return 'sharp';
    }
  }

  String get label {
    switch (this) {
      case MagicFilter.original:
        return 'Original';
      case MagicFilter.enhance:
        return 'Magic Color';
      case MagicFilter.blackWhite:
        return 'B&W';
      case MagicFilter.lighten:
        return 'Lighten';
      case MagicFilter.sharp:
        return 'Sharp Color';
    }
  }

  static MagicFilter fromKey(String? key) {
    switch (key) {
      case 'enhance':
        return MagicFilter.enhance;
      case 'bw':
        return MagicFilter.blackWhite;
      case 'lighten':
        return MagicFilter.lighten;
      case 'sharp':
        return MagicFilter.sharp;
      case 'original':
      default:
        return MagicFilter.original;
    }
  }
}
