import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// What a quick look at the selfie found wrong with it, if anything.
enum PhotoIssue {
  /// Under-exposed. The single most common cause of a bad swap: the renderer
  /// cannot match a face it cannot see.
  tooDark,

  /// Blown out. Highlights clip and the features flatten.
  tooBright,

  /// Soft. Either camera shake or the subject moving.
  blurry,
}

/// A cheap sanity check on a captured selfie.
///
/// Deliberately **not** a face detector. Detecting where a face is, and which
/// way it is pointing, needs ML Kit (`google_mlkit_face_detection`), which is
/// a large native dependency and an iOS pod. What this does instead is read
/// the pixels for the two things that go wrong most often and that a person
/// can actually fix by taking the photo again: exposure and focus.
///
/// It runs on a 96px thumbnail decoded by Flutter's own image codec, so there
/// is no package to add and it costs a few milliseconds.
///
/// Every result is **advisory**. The user is shown a suggestion and can always
/// keep the photo, because this check has no idea whether the dark pixels it
/// found are a badly lit face or a deliberately moody one.
abstract final class PhotoQuality {
  /// Mean luma below this reads as under-exposed. 0..255.
  static const _darkBelow = 62.0;

  /// Mean luma above this reads as blown out.
  static const _brightAbove = 218.0;

  /// Mean absolute Laplacian below this reads as soft. Tuned on phone selfies
  /// downscaled to 96px, where a sharp face lands around 9 to 20.
  static const _blurBelow = 3.6;

  /// The long edge the image is scaled to before it is read.
  static const _sampleSize = 96;

  /// Returns what is wrong with the photo at [path], or null if it looks fine.
  ///
  /// Never throws. A file that cannot be decoded returns null rather than an
  /// issue: refusing a photo because *we* could not read it would block the
  /// user over our own failure.
  static Future<PhotoIssue?> inspect(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      return await inspectBytes(bytes);
    } catch (error) {
      debugPrint('PhotoQuality: could not read $path ($error)');
      return null;
    }
  }

  @visibleForTesting
  static Future<PhotoIssue?> inspectBytes(Uint8List bytes) async {
    final luma = await _lumaThumbnail(bytes);
    if (luma == null) return null;

    final mean = _mean(luma.values);
    if (mean < _darkBelow) return PhotoIssue.tooDark;
    if (mean > _brightAbove) return PhotoIssue.tooBright;

    if (_sharpness(luma) < _blurBelow) return PhotoIssue.blurry;
    return null;
  }

  /// Decode to a small greyscale buffer. Null when the bytes are not an image.
  static Future<_Luma?> _lumaThumbnail(Uint8List bytes) async {
    ui.Codec? codec;
    try {
      codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: _sampleSize,
        targetHeight: _sampleSize,
      );
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      final width = frame.image.width;
      final height = frame.image.height;
      frame.image.dispose();
      if (data == null || width == 0 || height == 0) return null;

      final rgba = data.buffer.asUint8List();
      final values = Float32List(width * height);
      for (var i = 0; i < values.length; i++) {
        final o = i * 4;
        // Rec. 601 luma. Good enough, and it is what every other
        // "is this photo dark" heuristic uses.
        values[i] = 0.299 * rgba[o] + 0.587 * rgba[o + 1] + 0.114 * rgba[o + 2];
      }
      return _Luma(values, width, height);
    } catch (error) {
      debugPrint('PhotoQuality: could not decode image ($error)');
      return null;
    } finally {
      codec?.dispose();
    }
  }

  static double _mean(Float32List values) {
    if (values.isEmpty) return 0;
    var total = 0.0;
    for (final v in values) {
      total += v;
    }
    return total / values.length;
  }

  /// Mean absolute response of a 4-neighbour Laplacian.
  ///
  /// The usual measure is the *variance* of the Laplacian, but variance is
  /// dominated by a handful of hard edges, so a blurry face in front of a
  /// sharp window frame still scores well. The mean is duller and, for this
  /// one question, more honest.
  static double _sharpness(_Luma luma) {
    final w = luma.width;
    final h = luma.height;
    if (w < 3 || h < 3) return double.infinity;

    var total = 0.0;
    var count = 0;
    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        final i = y * w + x;
        final response = luma.values[i - 1] +
            luma.values[i + 1] +
            luma.values[i - w] +
            luma.values[i + w] -
            4 * luma.values[i];
        total += response.abs();
        count++;
      }
    }
    return count == 0 ? double.infinity : total / count;
  }
}

class _Luma {
  const _Luma(this.values, this.width, this.height);

  final Float32List values;
  final int width;
  final int height;
}
