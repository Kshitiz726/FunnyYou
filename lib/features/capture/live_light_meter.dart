import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

/// How the light is right now, while the camera is still open.
enum LightReading {
  /// Good enough to shoot.
  fine,

  /// Under-exposed. The most common cause of a poor swap.
  tooDark,

  /// Blown out. Highlights clip and the features flatten.
  tooBright,
}

/// Reads the camera's own frames so the app can say "it is dark in here"
/// *before* the photo is taken rather than after.
///
/// Only light. Where the face is and which way it points needs landmarks,
/// which on the phone means ML Kit -- a large native dependency and an iOS pod
/// that raises the minimum iOS version -- so that half is answered by the
/// render box once there is a photo to send it. Light does not need any of
/// that: it is the average of a plane the camera is already handing over.
///
/// Deliberately cheap and deliberately slow to change its mind:
///
/// * one frame every [_minGap], not all thirty a second;
/// * every [_stride]th pixel of the luma plane, not all two million;
/// * a verdict only after [_agreeCount] readings in a row agree, so a hand
///   passing the lens does not make the advice flicker.
class LiveLightMeter {
  LiveLightMeter({this.onChanged});

  /// Called when the verdict changes, never on every frame.
  final ValueChanged<LightReading>? onChanged;

  /// Matches the thresholds the still check uses, so the live advice and the
  /// warning after the shot cannot contradict each other over one photo.
  /// See `PhotoQuality` and `backend/app/photo_check.py`.
  static const _darkBelow = 62.0;
  static const _brightAbove = 218.0;

  static const _minGap = Duration(milliseconds: 400);
  static const _stride = 37;
  static const _agreeCount = 3;

  LightReading _reading = LightReading.fine;
  LightReading get reading => _reading;

  LightReading _candidate = LightReading.fine;
  int _agreed = 0;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);
  bool _running = false;

  bool get running => _running;

  Future<void> attach(CameraController controller) async {
    if (_running) return;
    try {
      await controller.startImageStream(_onFrame);
      _running = true;
    } catch (error) {
      // Not every device and format supports streaming. The static tips on
      // screen still stand, and the check after the shot still runs.
      debugPrint('LiveLightMeter: no frame stream ($error)');
    }
  }

  Future<void> detach(CameraController? controller) async {
    if (!_running) return;
    _running = false;
    try {
      // Must stop before takePicture: the plugin cannot do both at once, and
      // leaving it running is what turns the shutter into a silent failure.
      await controller?.stopImageStream();
    } catch (error) {
      debugPrint('LiveLightMeter: could not stop the stream ($error)');
    }
  }

  void _onFrame(CameraImage image) {
    final now = DateTime.now();
    if (now.difference(_last) < _minGap) return;
    _last = now;

    final mean = _meanLuma(image);
    if (mean == null) return;

    final seen = mean < _darkBelow
        ? LightReading.tooDark
        : mean > _brightAbove
            ? LightReading.tooBright
            : LightReading.fine;

    if (seen != _candidate) {
      _candidate = seen;
      _agreed = 1;
      return;
    }

    if (++_agreed < _agreeCount || seen == _reading) return;
    _reading = seen;
    onChanged?.call(seen);
  }

  /// Average brightness from the first plane.
  ///
  /// On Android that plane is YUV's Y, which *is* luma. On iOS with BGRA
  /// there is one interleaved plane instead, and sampling every 37th byte
  /// walks the channels evenly enough that the average still tracks
  /// brightness. Neither needs the image decoded.
  static double? _meanLuma(CameraImage image) {
    if (image.planes.isEmpty) return null;
    final bytes = image.planes.first.bytes;
    if (bytes.isEmpty) return null;

    var total = 0;
    var count = 0;
    for (var i = 0; i < bytes.length; i += _stride) {
      total += bytes[i];
      count++;
    }
    return count == 0 ? null : total / count;
  }
}
