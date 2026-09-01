import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:funny_you/services/generation_service.dart';
import 'package:funny_you/services/http_generation_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// A real loopback HTTP server, so the client is tested against actual sockets
/// rather than a mocked `http.Client` that can drift from reality.
class FakeBackend {
  FakeBackend(this._server);

  final HttpServer _server;
  final List<String> requestLog = [];

  /// Job payloads returned by successive GET /v1/renders/{id} calls.
  late List<Map<String, dynamic>> pollResponses;
  int _pollIndex = 0;
  int startStatus = 202;
  Map<String, dynamic> startBody = const {'id': 'job-1'};

  String get baseUrl => 'http://127.0.0.1:${_server.port}';

  static Future<FakeBackend> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final backend = FakeBackend(server);
    backend._listen();
    return backend;
  }

  void _listen() {
    _server.listen((request) async {
      final path = request.uri.path;
      requestLog.add('${request.method} $path');

      if (request.method == 'POST' && path == '/v1/renders') {
        await request.drain<void>();
        request.response.statusCode = startStatus;
        request.response.write(jsonEncode(startBody));
      } else if (request.method == 'GET' && path.startsWith('/v1/renders/')) {
        final body = pollResponses[_pollIndex.clamp(0, pollResponses.length - 1)];
        _pollIndex++;
        request.response.write(jsonEncode(body));
      } else if (path.startsWith('/v1/videos/')) {
        request.response.add(utf8.encode('MP4DATA'));
      } else if (request.method == 'DELETE') {
        request.response.write(jsonEncode({'cancelled': true}));
      } else {
        request.response.statusCode = 404;
      }
      await request.response.close();
    });
  }

  Future<void> stop() => _server.close(force: true);
}

class _FakePathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProvider(this.path);

  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  late FakeBackend backend;
  late Directory tempDir;
  late File facePhoto;

  setUp(() async {
    backend = await FakeBackend.start();
    tempDir = await Directory.systemTemp.createTemp('funnyyou_test');
    facePhoto = File('${tempDir.path}/face.jpg')..writeAsBytesSync([1, 2, 3]);
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  tearDown(() async {
    await backend.stop();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  HttpGenerationService service() => HttpGenerationService(
        baseUrl: backend.baseUrl,
        pollInterval: const Duration(milliseconds: 10),
      );

  GenerationRequest request() => GenerationRequest(
        facePhotoPath: facePhoto.path,
        prompt: 'the person as a chef',
        templateId: 'chef',
      );

  test('maps backend stages onto the app stages and downloads the video',
      () async {
    backend.pollResponses = [
      {'status': 'running', 'stage': 'matchingFace', 'progress': 0.15},
      {'status': 'running', 'stage': 'rendering', 'progress': 0.6, 'etaSeconds': 42},
      {
        'status': 'completed',
        'stage': 'done',
        'progress': 1.0,
        'videoUrl': '${backend.baseUrl}/v1/videos/job-1.mp4',
      },
    ];

    final events = await service().generate(request()).toList();

    expect(events.first.stage, GenerationStage.uploading);
    expect(
      events.map((e) => e.stage),
      containsAll([GenerationStage.matchingFace, GenerationStage.rendering]),
    );

    final eta = events.firstWhere((e) => e.stage == GenerationStage.rendering);
    expect(eta.estimatedRemaining, const Duration(seconds: 42));

    final done = events.last;
    expect(done.stage, GenerationStage.done);
    expect(done.value, 1);
    expect(done.videoPath, isNotNull);
    expect(File(done.videoPath!).readAsStringSync(), 'MP4DATA');
  });

  test('done is emitted once, only after the file is on disk', () async {
    // The server flips to stage `done` while the client is still downloading.
    // If that tick is forwarded as done, the UI builds a Creation with a null
    // videoPath and the result screen has nothing to play or save.
    backend.pollResponses = [
      {'status': 'running', 'stage': 'rendering', 'progress': 0.6},
      {
        'status': 'completed',
        'stage': 'done',
        'progress': 1.0,
        'videoUrl': '${backend.baseUrl}/v1/videos/job-1.mp4',
      },
    ];

    final events = await service().generate(request()).toList();
    final done = events.where((e) => e.stage == GenerationStage.done);

    expect(done, hasLength(1));
    expect(events.last.stage, GenerationStage.done);
    expect(done.single.videoPath, isNotNull);
    for (final event in events.where((e) => e.stage != GenerationStage.done)) {
      expect(event.videoPath, isNull);
    }
  });

  test('downloads from the configured host, not the URL the server reports',
      () async {
    // PUBLIC_BASE_URL is the backend guessing how clients reach it, and it is
    // routinely wrong — behind a proxy, or on an emulator where the only route
    // to the host is 10.0.2.2. Only the path is trustworthy.
    backend.pollResponses = [
      {
        'status': 'completed',
        'stage': 'done',
        'progress': 1.0,
        'videoUrl': 'http://10.255.255.1:9/v1/videos/job-1.mp4',
      },
    ];

    final events = await service().generate(request()).toList();

    expect(events.last.videoPath, isNotNull);
    expect(File(events.last.videoPath!).readAsStringSync(), 'MP4DATA');
    expect(backend.requestLog, contains('GET /v1/videos/job-1.mp4'));
  });

  test('progress reported by the server is passed through untouched', () async {
    backend.pollResponses = [
      {'status': 'running', 'stage': 'rendering', 'progress': 0.33},
      {
        'status': 'completed',
        'stage': 'done',
        'progress': 1.0,
        'videoUrl': '${backend.baseUrl}/v1/videos/job-1.mp4',
      },
    ];

    final events = await service().generate(request()).toList();
    expect(events.any((e) => e.value == 0.33), isTrue);
  });

  test('a failed job surfaces the server message', () async {
    backend.pollResponses = [
      {'status': 'failed', 'error': 'CUDA out of memory'},
    ];

    expect(
      () => service().generate(request()).toList(),
      throwsA(
        isA<GenerationException>().having(
          (e) => e.message,
          'message',
          contains('CUDA out of memory'),
        ),
      ),
    );
  });

  test('a rejected start reports the server detail, not a status code', () async {
    backend
      ..startStatus = 401
      ..startBody = const {'detail': 'Invalid or missing API key'};
    backend.pollResponses = const [];

    expect(
      () => service().generate(request()).toList(),
      throwsA(
        isA<GenerationException>().having(
          (e) => e.message,
          'message',
          contains('Invalid or missing API key'),
        ),
      ),
    );
  });

  test('a missing photo fails before any network call', () async {
    final svc = HttpGenerationService(
      baseUrl: backend.baseUrl,
      pollInterval: const Duration(milliseconds: 10),
    );

    await expectLater(
      svc
          .generate(const GenerationRequest(
            facePhotoPath: '/does/not/exist.jpg',
            prompt: 'x',
          ))
          .toList(),
      throwsA(isA<GenerationException>()),
    );
    expect(backend.requestLog, isEmpty);
  });

  test('a completed job with no video url is an error, not a silent success',
      () async {
    backend.pollResponses = [
      {'status': 'completed', 'stage': 'done', 'progress': 1.0},
    ];

    expect(
      () => service().generate(request()).toList(),
      throwsA(isA<GenerationException>()),
    );
  });
}
