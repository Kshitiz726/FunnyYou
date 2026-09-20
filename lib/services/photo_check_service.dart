import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../features/capture/photo_quality.dart';
import 'api_config.dart';

/// Asks the render box what is wrong with a selfie.
///
/// The phone reads exposure and focus itself, instantly and offline. What it
/// cannot do is find the face and say which way it is pointing: that needs
/// landmarks, and on the phone that means ML Kit — a large native dependency
/// and an iOS pod that raises the minimum iOS version. The box is already
/// running InsightFace for the face swap, so the head angle is answered there
/// and costs the app nothing but a request.
///
/// **Fails open, always.** No backend, no signal, slow reply, unreadable
/// answer: all of them come back as "nothing wrong". Blocking somebody's
/// perfectly good photo because our server is having a bad day would be worse
/// than missing a crooked one.
class PhotoCheckService {
  PhotoCheckService({
    String? baseUrl,
    Map<String, String>? headers,
    this.client,
    this.timeout = const Duration(seconds: 20),
  })  : baseUrl = baseUrl ?? ApiConfig.baseUrl,
        headers = headers ?? ApiConfig.authHeaders;

  final String baseUrl;
  final Map<String, String> headers;
  final Duration timeout;

  /// Injected by the tests; production builds use the package default.
  final http.Client? client;

  bool get enabled => baseUrl.isNotEmpty;

  /// Everything the box found, or null when it could not be asked.
  Future<PhotoReport?> inspect(String path) async {
    if (!enabled) return null;
    try {
      final bytes = await File(path).readAsBytes();
      return await inspectBytes(bytes);
    } catch (error) {
      debugPrint('PhotoCheckService: skipped ($error)');
      return null;
    }
  }

  @visibleForTesting
  Future<PhotoReport?> inspectBytes(Uint8List bytes) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${baseUrl.replaceAll(RegExp(r'/$'), '')}/v1/photo-check'),
    )
      ..headers.addAll(headers)
      ..files.add(
        http.MultipartFile.fromBytes('image', bytes, filename: 'face.jpg'),
      );

    try {
      final sender = client;
      final streamed = await (sender == null
              ? request.send()
              : sender.send(request))
          .timeout(timeout);
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) return null;

      double? number(String key) => (body[key] as num?)?.toDouble();

      // Worst first, as the box orders them. Anything this build has never
      // heard of is dropped rather than guessed at: a newer server must not
      // be able to make an older app show a warning it has no words for.
      final issues = <PhotoIssue>[
        for (final code in (body['issues'] as List? ?? const []))
          ?issueFromCode('$code'),
      ];

      return PhotoReport(
        issues: issues,
        faceCount: (body['faceCount'] as num?)?.toInt(),
        yaw: number('yaw'),
        pitch: number('pitch'),
        roll: number('roll'),
        brightness: number('brightness'),
        sharpness: number('sharpness'),
        faceShare: number('faceShare'),
        fromBackend: true,
      );
    } catch (error) {
      debugPrint('PhotoCheckService: no answer from the box ($error)');
      return null;
    }
  }

  /// Maps the backend's issue codes onto what the app knows how to say.
  @visibleForTesting
  static PhotoIssue? issueFromCode(String code) => switch (code) {
        'no_face' => PhotoIssue.noFace,
        'many_faces' => PhotoIssue.manyFaces,
        'turned' => PhotoIssue.turned,
        'chin' => PhotoIssue.chin,
        'tilted' => PhotoIssue.tilted,
        'too_far' => PhotoIssue.tooFar,
        'too_dark' => PhotoIssue.tooDark,
        'too_bright' => PhotoIssue.tooBright,
        'blurry' => PhotoIssue.blurry,
        _ => null,
      };
}
