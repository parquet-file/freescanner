/// services/filter_math.dart — the pure-Dart math behind the magic filters.
///
/// Everything here is a static function over plain data (LUTs, pixel arrays)
/// so it is unit-testable without any plugin. The heavy pixel loops run in a
/// background isolate via ImageFilterService.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../core/utils.dart' as utils;

class FilterMath {
  FilterMath._();

  /// Identity LUT.
  static Uint8List identityLut() => _lut((v) => v);

  /// Contrast: v' = clamp((v − 128)·c + 128 + b)
  static Uint8List contrastLut(double contrast, [double brightness = 0]) =>
      _lut((v) => (v - 128) * contrast + 128 + brightness);

  /// Gamma: v' = 255 · (v/255)^(1/g). gamma > 1 brightens.
  static Uint8List gammaLut(double gamma) =>
      _lut((v) => 255 * math.pow(v / 255, 1 / gamma));

  /// Applies three per-channel LUTs to every pixel (in place).
  static void applyLuts(img.Image image, Uint8List r, Uint8List g, Uint8List b) {
    for (final frame in image.frames) {
      for (final pixel in frame) {
        pixel.r = r[utils.clampInt(pixel.r.toInt(), 0, 255)];
        pixel.g = g[utils.clampInt(pixel.g.toInt(), 0, 255)];
        pixel.b = b[utils.clampInt(pixel.b.toInt(), 0, 255)];
      }
    }
  }

  /// Scales chroma around luma: v' = luma + (v − luma)·s (in place).
  static void applySaturation(img.Image image, double saturation) {
    for (final frame in image.frames) {
      for (final pixel in frame) {
        final luma = 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
        pixel.r = _clamp255(luma + (pixel.r - luma) * saturation);
        pixel.g = _clamp255(luma + (pixel.g - luma) * saturation);
        pixel.b = _clamp255(luma + (pixel.b - luma) * saturation);
      }
    }
  }

  /// Percentile stretch per channel: maps the [lowPct, highPct] range of the
  /// histogram onto [0, 255]. The classic "auto levels" document cleanup.
  static List<Uint8List> percentileStretchLuts(
    img.Image image, {
    double lowPct = 0.02,
    double highPct = 0.98,
  }) {
    final total = image.width * image.height;
    if (total == 0) {
      return [identityLut(), identityLut(), identityLut()];
    }
    final histograms = List.generate(3, (_) => Uint32List(256));
    for (final pixel in image.frames.first) {
      histograms[0][utils.clampInt(pixel.r.toInt(), 0, 255)] += 1;
      histograms[1][utils.clampInt(pixel.g.toInt(), 0, 255)] += 1;
      histograms[2][utils.clampInt(pixel.b.toInt(), 0, 255)] += 1;
    }
    return [
      for (final hist in histograms) _stretchOne(hist, total, lowPct, highPct)
    ];
  }

  /// Grayscale + adaptive threshold using an integral image (fast local-mean
  /// thresholding — the "B&W" scanner look, robust to uneven lighting).
  static void toAdaptiveBlackWhite(
    img.Image image, {
    double windowFraction = 1 / 16,
    int bias = 10,
  }) {
    for (final frame in image.frames) {
      final w = frame.width;
      final h = frame.height;
      if (w == 0 || h == 0) continue;
      var window = (w * windowFraction).round();
      if (window < 16) window = 16;
      final radius = window ~/ 2;

      // Luma plane.
      final luma = Uint8List(w * h);
      var i = 0;
      for (final pixel in frame) {
        luma[i++] = utils.clampInt(
            (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b).round(),
            0,
            255);
      }

      // Integral image with zero padding (row-major, (w+1) x (h+1)).
      final integralW = w + 1;
      final integral = Uint32List(integralW * (h + 1));
      for (var y = 0; y < h; y++) {
        var rowSum = 0;
        for (var x = 0; x < w; x++) {
          rowSum += luma[y * w + x];
          integral[(y + 1) * integralW + (x + 1)] =
              integral[y * integralW + (x + 1)] + rowSum;
        }
      }

      // Local-mean threshold.
      i = 0;
      for (var y = 0; y < h; y++) {
        final y0 = utils.clampInt(y - radius, 0, h - 1);
        final y1 = utils.clampInt(y + radius, 0, h - 1);
        for (var x = 0; x < w; x++, i++) {
          final x0 = utils.clampInt(x - radius, 0, w - 1);
          final x1 = utils.clampInt(x + radius, 0, w - 1);
          final area = (x1 - x0 + 1) * (y1 - y0 + 1);
          final sum = integral[(y1 + 1) * integralW + (x1 + 1)] -
              integral[y0 * integralW + (x1 + 1)] -
              integral[(y1 + 1) * integralW + x0] +
              integral[y0 * integralW + x0];
          final mean = sum ~/ area;
          final v = luma[i] < mean - bias ? 0 : 255;
          frame.setPixelRgba(x, y, v, v, v, frame.getPixel(x, y).a.toInt());
        }
      }
    }
  }

  // ------------------------------------------------------------------ helpers

  static Uint8List _stretchOne(
    Uint32List histogram,
    int total,
    double lowPct,
    double highPct,
  ) {
    final lowTarget = total * lowPct;
    final highTarget = total * highPct;
    var acc = 0;
    var low = 0;
    var high = 255;
    for (var v = 0; v < 256; v++) {
      acc += histogram[v];
      if (acc >= lowTarget) {
        low = v;
        break;
      }
    }
    acc = 0;
    for (var v = 0; v < 256; v++) {
      acc += histogram[v];
      if (acc >= highTarget) {
        high = v;
        break;
      }
    }
    if (high <= low) return identityLut();
    final scale = 255 / (high - low);
    return _lut((v) => (v - low) * scale);
  }

  static Uint8List _lut(num Function(int v) f) {
    final out = Uint8List(256);
    for (var v = 0; v < 256; v++) {
      out[v] = _clamp255(f(v));
    }
    return out;
  }

  static int _clamp255(num v) => v < 0 ? 0 : (v > 255 ? 255 : v.round());
}
