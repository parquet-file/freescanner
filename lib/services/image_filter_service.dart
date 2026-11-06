import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:image/image.dart' as img;

import '../core/app_config.dart' as app_config;
import '../data/models/magic_filter.dart';
import 'filter_math.dart';

/// services/image_filter_service.dart — renders the "magic filter" copies of
/// scanned pages (filter + rotation), off the UI thread.
class ImageFilterService {
  const ImageFilterService();

  /// Renders [filter] + [rotation] for the page at [sourcePath] and returns
  /// the encoded JPEG bytes. `original` + 0° simply re-encodes the source
  /// (used to normalize rotation metadata away).
  Future<Uint8List> process({
    required String sourcePath,
    required MagicFilter filter,
    required int rotation,
  }) async {
    final params = _ProcessParams(
      sourcePath: sourcePath,
      filterKey: filter.key,
      rotation: ScannedRotation.normalize(rotation),
      maxDimension: app_config.AppConfig.maxPageDimension,
      jpegQuality: app_config.AppConfig.jpegQuality,
    );
    return compute(_processIsolate, params);
  }

  /// Decodes only the dimensions of an image (cheap header parse).
  Future<({int width, int height})> dimensionsOf(String path) async {
    final bytes = await File(path).readAsBytes();
    final decoded = await compute(_decodeInfo, bytes);
    return (width: decoded.$1, height: decoded.$2);
  }
}

class ScannedRotation {
  static int normalize(int degrees) => ((degrees % 360) + 360) % 360;
}

class _ProcessParams {
  const _ProcessParams({
    required this.sourcePath,
    required this.filterKey,
    required this.rotation,
    required this.maxDimension,
    required this.jpegQuality,
  });

  final String sourcePath;
  final String filterKey;
  final int rotation;
  final int maxDimension;
  final int jpegQuality;
}

/// Runs in a background isolate — no platform channels needed.
Uint8List _processIsolate(_ProcessParams params) {
  final bytes = File(params.sourcePath).readAsBytesSync();
  var image = img.decodeJpg(bytes);
  if (image == null) {
    throw const _ProcessingException('Could not decode the scanned page');
  }

  // 1) Filter.
  switch (MagicFilter.fromKey(params.filterKey)) {
    case MagicFilter.original:
      break;
    case MagicFilter.enhance:
      // "Magic Color": per-channel auto levels + gentle saturation boost.
      final luts = FilterMath.percentileStretchLuts(image);
      FilterMath.applyLuts(image, luts[0], luts[1], luts[2]);
      FilterMath.applySaturation(image, 1.18);
    case MagicFilter.blackWhite:
      FilterMath.toAdaptiveBlackWhite(image);
    case MagicFilter.lighten:
      FilterMath.applyLuts(
        image,
        FilterMath.gammaLut(1.35),
        FilterMath.gammaLut(1.35),
        FilterMath.gammaLut(1.35),
      );
    case MagicFilter.sharp:
      FilterMath.applyLuts(
        image,
        FilterMath.contrastLut(1.16),
        FilterMath.contrastLut(1.16),
        FilterMath.contrastLut(1.16),
      );
      FilterMath.applySaturation(image, 1.35);
  }

  // 2) Rotation (clockwise).
  if (params.rotation != 0) {
    image = img.copyRotate(image, angle: params.rotation);
  }

  // 3) Bound the longest side.
  final longest = image.width > image.height ? image.width : image.height;
  if (longest > params.maxDimension) {
    final scale = params.maxDimension / longest;
    image = img.copyResize(
      image,
      width: (image.width * scale).round(),
      height: (image.height * scale).round(),
    );
  }

  return img.encodeJpg(image, quality: params.jpegQuality);
}

(int, int) _decodeInfo(Uint8List bytes) {
  final image = img.decodeJpg(bytes);
  if (image == null) {
    throw const _ProcessingException('Could not decode the scanned page');
  }
  return (image.width, image.height);
}

class _ProcessingException implements Exception {
  const _ProcessingException(this.message);
  final String message;

  @override
  String toString() => message;
}
