import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:image/image.dart' as img;

import 'package:freescanner/services/filter_math.dart';

img.Image _solidImage(int w, int h, int rgb) {
  final image = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      image.setPixelRgba(
          x, y, (rgb >> 16) & 0xff, (rgb >> 8) & 0xff, rgb & 0xff, 255);
    }
  }
  return image;
}

void main() {
  group('FilterMath LUTs', () {
    test('identity LUT maps v to v', () {
      final lut = FilterMath.identityLut();
      expect(lut.length, 256);
      for (var v = 0; v < 256; v++) {
        expect(lut[v], v);
      }
    });

    test('contrast LUT is monotonic and clamped', () {
      final lut = FilterMath.contrastLut(1.5, 4);
      var last = -1;
      for (var v = 0; v < 256; v++) {
        expect(lut[v], inInclusiveRange(0, 255));
        expect(lut[v], greaterThanOrEqualTo(last));
        last = lut[v];
      }
      expect(lut[0], 0); // dark end clamps to 0
      expect(lut[255], 255); // bright end clamps to 255
    });

    test('gamma LUT brightens midtones for gamma > 1', () {
      final lut = FilterMath.gammaLut(1.4);
      expect(lut[128], greaterThan(128));
      expect(lut[0], 0);
      expect(lut[255], 255);
    });

    test('percentile stretch pushes a low-contrast image to full range', () {
      // Image where every channel sits in [90, 160].
      final image = _solidImage(8, 8, 0x5A5A5A); // 90,90,90
      final luts = FilterMath.percentileStretchLuts(image);
      // 90 is the 2nd percentile AND the 98th (uniform) — degenerate, but a
      // small delta still stretches. Use a two-tone image for a real case:
      final mixed = img.Image(width: 8, height: 8);
      for (var y = 0; y < 8; y++) {
        for (var x = 0; x < 8; x++) {
          final v = (x + y) % 2 == 0 ? 100 : 150;
          mixed.setPixelRgba(x, y, v, v, v, 255);
        }
      }
      final stretched = FilterMath.percentileStretchLuts(mixed);
      // 100 → 0, 150 → 255 (2%/98% of 64 px are beyond these values).
      expect(stretched[0][100], 0);
      expect(stretched[0][150], 255);
      expect(luts.length, 3);
    });

    test('applyLuts maps channels through their tables', () {
      final image = _solidImage(2, 2, 0x804020); // r=128 g=64 b=32
      final lut = FilterMath.identityLut();
      final rLut = Uint8List.fromList([for (var v = 0; v < 256; v++) 255]);
      FilterMath.applyLuts(image, rLut, lut, lut);
      final p = image.getPixel(0, 0);
      expect(p.r.toInt(), 255);
      expect(p.g.toInt(), 64);
      expect(p.b.toInt(), 32);
    });

    test('saturation 0 yields grayscale', () {
      final image = _solidImage(2, 2, 0xFF0000); // pure red
      FilterMath.applySaturation(image, 0.0);
      final p = image.getPixel(0, 0);
      expect(p.r.toInt(), p.g.toInt());
      expect(p.g.toInt(), p.b.toInt());
      expect(p.r.toInt(), greaterThan(0)); // luma of red ≈ 76
    });
  });

  group('FilterMath.toAdaptiveBlackWhite', () {
    test('binarizes a bright-sheet-on-dark-background pattern', () {
      // Dark background (30) with a bright square (220) in the middle.
      const w = 40, h = 40;
      final image = img.Image(width: w, height: h);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final inside = x > 10 && x < 30 && y > 10 && y < 30;
          final v = inside ? 220 : 30;
          image.setPixelRgba(x, y, v, v, v, 255);
        }
      }
      FilterMath.toAdaptiveBlackWhite(image, windowFraction: 1 / 8, bias: 8);

      // Centre of the bright square must be white (255)…
      var whites = 0;
      for (var y = 16; y < 24; y++) {
        for (var x = 16; x < 24; x++) {
          final p = image.getPixel(x, y);
          if (p.r.toInt() == 255) whites += 1;
        }
      }
      expect(whites, greaterThan(48));

      // …and the dark side of each sheet edge (just outside the bright
      // square, where the local window still sees the bright pixels) must
      // be black. (A far-uniform dark region is *white* by design — its
      // local mean equals the pixel value; that's how local-mean
      // thresholding behaves and why it suppresses uneven lighting.)
      var edgeBlacks = 0;
      for (var y = 16; y < 24; y++) {
        for (var x = 4; x < 10; x++) {
          final p = image.getPixel(x, y);
          if (p.r.toInt() == 0) edgeBlacks += 1;
        }
      }
      expect(edgeBlacks, greaterThan(40));
    });

    test('every output pixel is pure black or pure white', () {
      final image = img.Image(width: 24, height: 24);
      for (var y = 0; y < 24; y++) {
        for (var x = 0; x < 24; x++) {
          final v = (x * 11 + y * 7) % 256;
          image.setPixelRgba(x, y, v, 255 - v, (v * 3) % 256, 255);
        }
      }
      FilterMath.toAdaptiveBlackWhite(image);
      for (final p in image) {
        expect(p.r.toInt(), anyOf(0, 255));
        expect(p.r.toInt(), p.g.toInt());
        expect(p.g.toInt(), p.b.toInt());
      }
    });
  });
}
