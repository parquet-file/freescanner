import 'package:flutter_test/flutter_test.dart';

import 'package:freescanner/data/models/magic_filter.dart';
import 'package:freescanner/data/models/scanned_document.dart';
import 'package:freescanner/data/models/scanned_page.dart';

void main() {
  group('MagicFilter', () {
    test('key round-trip', () {
      for (final filter in MagicFilter.values) {
        expect(MagicFilter.fromKey(filter.key), filter);
      }
    });

    test('unknown keys fall back to original', () {
      expect(MagicFilter.fromKey('nope'), MagicFilter.original);
      expect(MagicFilter.fromKey(null), MagicFilter.original);
    });
  });

  group('ScannedPage', () {
    test('rotation is normalized on load', () {
      final page = ScannedPage.fromJson(<String, dynamic>{
        'file': 'p001.jpg',
        'filter': 'bw',
        'rotation': 450,
      });
      expect(page.rotation, 90);
      expect(page.filter, MagicFilter.blackWhite);
    });

    test('negative rotation wraps', () {
      expect(ScannedPage.normalizeRotation(-90), 270);
      expect(ScannedPage.normalizeRotation(720), 0);
    });

    test('displayFile prefers the processed copy', () {
      final page = ScannedPage(file: 'p001.jpg')
        ..processedFile = 'p001_f2_r90.jpg';
      expect(page.displayFile, 'p001_f2_r90.jpg');
      expect(ScannedPage(file: 'p001.jpg').displayFile, 'p001.jpg');
    });
  });

  group('ScannedDocument JSON round-trip', () {
    final doc = ScannedDocument(
      id: 'doc-x',
      title: 'Driving licence',
      createdAt: DateTime.utc(2026, 11, 1, 9),
      updatedAt: DateTime.utc(2026, 11, 2, 10, 30),
      pages: [
        ScannedPage(file: 'p001.jpg')
          ..filter = MagicFilter.enhance
          ..rotation = 90
          ..processedFile = 'p001_enhance_r90.jpg',
        ScannedPage(file: 'p002.jpg'),
      ],
      ocrRuns: {'eng': '2026-11-02T10:30:00Z'},
    );

    test('toJson → fromJson preserves everything', () {
      final copy = ScannedDocument.fromJson(doc.toJson());
      expect(copy.id, 'doc-x');
      expect(copy.title, 'Driving licence');
      expect(copy.pageCount, 2);
      expect(copy.pages[0].filter, MagicFilter.enhance);
      expect(copy.pages[0].rotation, 90);
      expect(copy.pages[0].processedFile, 'p001_enhance_r90.jpg');
      expect(copy.pages[1].filter, MagicFilter.original);
      expect(copy.ocrRuns['eng'], '2026-11-02T10:30:00Z');
    });

    test('corrupt JSON degrades instead of throwing', () {
      final copy = ScannedDocument.fromJson(<String, dynamic>{
        'pages': <dynamic>['not-a-page', 42],
      });
      expect(copy.pageCount, 0);
      expect(copy.title, 'Document');
    });
  });
}
