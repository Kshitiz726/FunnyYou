import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'generation_service.dart';

/// Talks to the Funny You render API (`backend/`).
///
/// Contract:
///   POST   /v1/renders        multipart(image, prompt, template_id) -> job
///   GET    /v1/renders/{id}                                          -> job
///   DELETE /v1/renders/{id}
///
/// Polling rather than websockets on purpose: renders take minutes, phones
/// suspend sockets aggressively in the background, and a 2-second poll is
/// dramatically less code to keep correct.
class HttpGenerationService implements GenerationService {
  HttpGenerationService({
    required this.baseUrl,
    this.headers = const {},
    this.pollInterval = const Duration(seconds: 2),
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final Map<String, String> headers;
  final Duration pollInterval;
  final http.Client _client;

  String? _jobId;
  bool _cancelled = false;

  Uri _uri(String path) => Uri.parse('${baseUrl.replaceAll(RegExp(r'/$'), '')}$path');

  @override
  Stream<GenerationProgress> generate(GenerationRequest request) async* {
    _cancelled = false;

    final jobId = await _start(request);
    _jobId = jobId;

    yield const GenerationProgress(
      stage: GenerationStage.uploading,
      value: 0.05,
    );

    while (!_cancelled) {
      await Future<void>.delayed(pollInterval);
      if (_cancelled) break;

      final job = await _poll(jobId);
      final status = job['status'] as String? ?? 'running';

      if (status == 'failed') {
        throw GenerationException(
          job['error'] as String? ?? 'The render failed. Please try again.',
        );
      }
      if (status == 'cancelled') {
        throw const GenerationException('Cancelled');
      }

      var stage = _stageFrom(job['stage'] as String?);
      // The server reports `done` the moment the render lands on *its* disk,
      // but we still have to download it. Emitting done here would hand the UI
      // a result with no file — so the last pre-download tick is `finishing`.
      // GenerationStage.done is yielded exactly once, below, with the path.
      if (stage == GenerationStage.done) stage = GenerationStage.finishing;

      final progress = GenerationProgress(
        stage: stage,
        value: (job['progress'] as num?)?.toDouble() ?? 0,
        detail: switch (job['detail']) {
          final String d when d.isNotEmpty => d,
          _ => null,
        },
        estimatedRemaining: job['etaSeconds'] == null
            ? null
            : Duration(seconds: (job['etaSeconds'] as num).round()),
      );

      if (status == 'completed') {
        final url = job['videoUrl'] as String?;
        if (url == null || url.isEmpty) {
          throw const GenerationException('Render finished but returned no video');
        }
        yield progress;
        yield GenerationProgress(
          stage: GenerationStage.done,
          value: 1,
          estimatedRemaining: Duration.zero,
          videoPath: await _download(url, jobId),
        );
        return;
      }

      yield progress;
    }

    throw const GenerationException('Cancelled');
  }

  Future<String> _start(GenerationRequest request) async {
    final file = File(request.facePhotoPath);
    if (!file.existsSync()) {
      throw const GenerationException('We could not find your photo. Take it again.');
    }

    final multipart = http.MultipartRequest('POST', _uri('/v1/renders'))
      ..headers.addAll(headers)
      ..fields['prompt'] = request.prompt
      ..files.add(await http.MultipartFile.fromPath('image', file.path));

    if (request.templateId != null) {
      multipart.fields['template_id'] = request.templateId!;
    }

    late final http.Response response;
    try {
      response = await http.Response.fromStream(await multipart.send());
    } on SocketException {
      throw const GenerationException(
        'We could not reach the server. Check your connection and try again.',
      );
    }

    if (response.statusCode != 202 && response.statusCode != 200) {
      throw GenerationException(_readableError(response));
    }

    final id = (jsonDecode(response.body) as Map<String, dynamic>)['id'] as String?;
    if (id == null) {
      throw const GenerationException('The server did not start the render');
    }
    return id;
  }

  Future<Map<String, dynamic>> _poll(String jobId) async {
    final http.Response response;
    try {
      response = await _client.get(_uri('/v1/renders/$jobId'), headers: headers);
    } on SocketException {
      // A dropped poll is usually a blip on mobile data — keep waiting rather
      // than throwing away a render that is still running on the server.
      return const {'status': 'running'};
    }

    if (response.statusCode != 200) {
      throw GenerationException(_readableError(response));
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Re-point a server-supplied URL at the host we already talk to.
  ///
  /// `videoUrl` is built from the backend's own `PUBLIC_BASE_URL`, which is a
  /// guess about how clients reach it — and it is wrong more often than not:
  /// behind a reverse proxy, on RunPod's generated domain, or on an emulator
  /// where the host is `10.0.2.2` and nothing else. The path is the only part
  /// worth trusting.
  Uri _resolve(String url) {
    final path = Uri.tryParse(url)?.path;
    return path == null || path.isEmpty ? Uri.parse(url) : _uri(path);
  }

  Future<String> _download(String url, String jobId) async {
    final response = await _client.get(_resolve(url), headers: headers);
    if (response.statusCode != 200) {
      throw const GenerationException('Could not download your video');
    }

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/funnyyou_$jobId.mp4');
    await file.writeAsBytes(response.bodyBytes);
    return file.path;
  }

  GenerationStage _stageFrom(String? name) => switch (name) {
        'uploading' => GenerationStage.uploading,
        'matchingFace' => GenerationStage.matchingFace,
        'buildingScene' => GenerationStage.buildingScene,
        'rendering' => GenerationStage.rendering,
        'finishing' => GenerationStage.finishing,
        'done' => GenerationStage.done,
        _ => GenerationStage.rendering,
      };

  String _readableError(http.Response response) {
    try {
      final detail = (jsonDecode(response.body) as Map<String, dynamic>)['detail'];
      if (detail is String && detail.isNotEmpty) return detail;
    } catch (_) {
      // fall through to the generic message
    }
    return switch (response.statusCode) {
      401 => 'This app is not authorised to use the render server.',
      413 => 'That photo is too large. Please take another.',
      503 => 'The render server is starting up. Try again in a minute.',
      _ => 'Something went wrong on the server (${response.statusCode}).',
    };
  }

  @override
  Future<void> cancel() async {
    _cancelled = true;
    final jobId = _jobId;
    if (jobId == null) return;
    try {
      await _client.delete(_uri('/v1/renders/$jobId'), headers: headers);
    } on SocketException {
      // Best effort — the server evicts stale jobs on its own.
    }
  }
}
