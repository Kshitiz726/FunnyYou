import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../core/i18n/strings.dart';

/// What a quick look at the selfie found wrong with it, if anything.
enum PhotoIssue {
  /// Under-exposed. The single most common cause of a bad swap: the renderer
  /// cannot match a face it cannot see.
  tooDark,

  /// Blown out. Highlights clip and the features flatten.
  tooBright,

  /// Soft. Either camera shake or the subject moving.
  blurry,

  // The rest need to know where the face is, so they are decided on the
  // render box rather than here. See `PhotoCheckService`.

  /// Nothing face-shaped in the frame. The only finding that means the
  /// render genuinely cannot work, rather than will not look its best.
  noFace,

  /// More than one face. The swap picks the biggest, which may not be the
  /// person holding the phone.
  manyFaces,

  /// Head turned away from the camera. Past about twenty degrees of yaw the
  /// swap starts losing the likeness it is supposed to preserve.
  turned,

  /// Chin up or down. Pitch, the same problem on the other axis.
  chin,

  /// Head tilted sideways. Roll.
  tilted,

  /// Face too small in the frame to swap cleanly.
  tooFar,
}

/// A cheap sanity check on a captured selfie.
///
/// Deliberately **not** a face detector. Detecting where a face is, and which
/// way it is pointing, needs ML Kit (`google_mlkit_face_detection`), which is
/// a large native dependency and an iOS pod that raises the minimum iOS
/// version. What this does instead is read the pixels for the two things that
/// go wrong most often and that a person can actually fix by taking the photo
/// again: exposure and focus.
///
/// The face itself — found, how many, and which way it points — is answered by
/// `PhotoCheckService` against the render box, which is already running
/// InsightFace for the swap. That keeps the angle check accurate and the app
/// free of native dependencies, at the cost of needing a connection; when
/// there is none the app still gets this much.
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

/// A finding, plus how far off the photo is where that could be measured.
///
/// "Your head is turned away" leaves someone guessing whether to move an inch
/// or turn right round. The box measures the actual angle, so the message can
/// say it.
class PhotoFinding {
  const PhotoFinding(this.issue, {this.amount});

  final PhotoIssue issue;

  /// Degrees off square for [PhotoIssue.turned], [PhotoIssue.chin] and
  /// [PhotoIssue.tilted]; roughly how much closer to move, as a percentage,
  /// for [PhotoIssue.tooFar].
  ///
  /// Null when the finding came from the phone, which reads exposure and
  /// focus and has no idea where the face is.
  final int? amount;
}

/// What to say to the person about [finding].
///
/// Kept out of the widget so the wording of every finding can be tested
/// without a camera. A warning with no words is worse than no warning, and
/// an unhandled case would give exactly that.
String photoIssueMessage(S s, PhotoFinding finding) => switch (finding.issue) {
      PhotoIssue.tooDark => s.photoTooDark,
      PhotoIssue.tooBright => s.photoTooBright,
      PhotoIssue.blurry => s.photoTooBlurry,
      PhotoIssue.noFace => s.photoNoFace,
      PhotoIssue.manyFaces => s.photoManyFaces,
      PhotoIssue.turned => s.photoTurned(finding.amount),
      PhotoIssue.chin => s.photoChin(finding.amount),
      PhotoIssue.tilted => s.photoTilted(finding.amount),
      PhotoIssue.tooFar => s.photoTooFar(finding.amount),
    };

/// Whether one line of the photo check passed.
enum CheckState { good, warning, unknown }

/// One line of the photo check, as the review screen shows it.
class PhotoCheckLine {
  const PhotoCheckLine(this.label, this.value, this.state);

  /// What is being checked, e.g. "Lighting".
  final String label;

  /// What was found, e.g. "Good" or "Turned 43°".
  final String value;

  final CheckState state;
}

/// Everything the checks found about one photo.
///
/// The client asked for "a small program that controls the lighting quality,
/// angle, etc", and a check nobody can see is indistinguishable from one that
/// was never built -- so this carries the whole reading, not just the first
/// complaint, and the review screen lists every line with its result.
class PhotoReport {
  const PhotoReport({
    this.issues = const [],
    this.faceCount,
    this.yaw,
    this.pitch,
    this.roll,
    this.brightness,
    this.sharpness,
    this.faceShare,
    this.fromBackend = false,
  });

  /// Worst first, as the box orders them.
  final List<PhotoIssue> issues;

  final int? faceCount;
  final double? yaw;
  final double? pitch;
  final double? roll;
  final double? brightness;
  final double? sharpness;
  final double? faceShare;

  /// False when only the phone's own exposure and focus check ran, so the
  /// face lines have to say "needs a connection" rather than pretending.
  final bool fromBackend;

  bool has(PhotoIssue issue) => issues.contains(issue);

  /// The one finding worth putting in front of the user, or null.
  PhotoFinding? get headline {
    if (issues.isEmpty) return null;
    final first = issues.first;
    return PhotoFinding(first, amount: amountFor(first));
  }

  /// How far off the photo is for [issue], in that finding's own unit.
  int? amountFor(PhotoIssue issue) => switch (issue) {
        PhotoIssue.turned => _degrees(yaw),
        PhotoIssue.chin => _degrees(pitch),
        PhotoIssue.tilted => _degrees(roll),
        PhotoIssue.tooFar => _closerPercent,
        _ => null,
      };

  /// The share of the frame a face fills in a selfie that swaps cleanly.
  static const goodFaceShare = 0.32;

  int? get _closerPercent {
    final share = faceShare;
    if (share == null || share <= 0) return null;
    final closer = ((goodFaceShare / share) - 1) * 100;
    if (closer <= 0) return null;
    return (closer / 5).round() * 5;
  }

  /// The largest of the three head angles, which is the one worth quoting
  /// when the head is otherwise fine.
  int? get worstAngle {
    final angles = [yaw, pitch, roll].whereType<double>();
    if (angles.isEmpty) return null;
    return angles.map((a) => a.abs()).reduce((a, b) => a > b ? a : b).round();
  }

  static int? _degrees(double? value) {
    if (value == null) return null;
    final rounded = value.abs().round();
    return rounded > 0 ? rounded : null;
  }
}

/// The photo check as a list of lines the review screen can draw.
///
/// Every line is always present, including the ones that passed. That is the
/// point: the person can see the lighting and the head angle were measured,
/// and what they came out as.
List<PhotoCheckLine> photoCheckLines(S s, PhotoReport report) {
  CheckState stateFor(bool bad) => bad ? CheckState.warning : CheckState.good;

  final lines = <PhotoCheckLine>[
    PhotoCheckLine(
      s.checkLighting,
      report.has(PhotoIssue.tooDark)
          ? s.checkDark
          : report.has(PhotoIssue.tooBright)
              ? s.checkBright
              : s.checkGood,
      stateFor(
        report.has(PhotoIssue.tooDark) || report.has(PhotoIssue.tooBright),
      ),
    ),
    PhotoCheckLine(
      s.checkSharpness,
      report.has(PhotoIssue.blurry) ? s.checkSoft : s.checkSharp,
      stateFor(report.has(PhotoIssue.blurry)),
    ),
  ];

  // Without a backend the phone has read exposure and focus and nothing
  // else, so the face lines say so rather than claiming a pass they did not
  // earn.
  if (!report.fromBackend) {
    lines.add(
      PhotoCheckLine(s.checkFace, s.checkNeedsConnection, CheckState.unknown),
    );
    return lines;
  }

  final faces = report.faceCount ?? 0;
  lines.add(
    PhotoCheckLine(
      s.checkFace,
      report.has(PhotoIssue.noFace)
          ? s.checkFaceMissing
          : faces > 1
              ? s.checkFaceMany(faces)
              : s.checkFaceFound,
      stateFor(
        report.has(PhotoIssue.noFace) || report.has(PhotoIssue.manyFaces),
      ),
    ),
  );

  // Both of these need a face to mean anything.
  if (report.has(PhotoIssue.noFace)) return lines;

  final crooked = report.has(PhotoIssue.turned) ||
      report.has(PhotoIssue.chin) ||
      report.has(PhotoIssue.tilted);
  lines.add(
    PhotoCheckLine(
      s.checkAngle,
      crooked
          ? s.checkAngleOff(report.worstAngle)
          : s.checkAngleStraight(report.worstAngle),
      stateFor(crooked),
    ),
  );

  lines.add(
    PhotoCheckLine(
      s.checkFraming,
      report.has(PhotoIssue.tooFar) ? s.checkFramingFar : s.checkFramingGood,
      stateFor(report.has(PhotoIssue.tooFar)),
    ),
  );

  return lines;
}
