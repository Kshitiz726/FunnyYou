import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../data/templates.dart';

/// Generates a still of the user inside each scenario, so the picker shows
/// *them* rather than a stock image.
///
/// These come from Gemini's free image tier, not the paid video renderer —
/// that's the whole point: previews are free, the render is what costs money.
abstract interface class PreviewService {
  /// Whether previews can be produced at all right now.
  bool get enabled;

  /// Generate and cache previews for [templates]. Emits after each batch so
  /// the UI can fill in progressively.
  Stream<PreviewBatch> generate({
    required String facePhotoPath,
    required List<VideoTemplate> templates,
  });
}

@immutable
class PreviewBatch {
  const PreviewBatch({
    required this.completed,
    required this.total,
    required this.paths,
    this.errors = const {},
  });

  final int completed;
  final int total;

  /// templateId -> local file path.
  final Map<String, String> paths;
  final Map<String, String> errors;

  double get progress => total == 0 ? 1 : completed / total;
}

/// Local cache of generated previews, keyed by template id.
///
/// Kept separate from the service so the UI can read cached previews instantly
/// on launch without touching the network.
class PreviewStore extends ChangeNotifier {
  final Map<String, String> _paths = {};

  String? pathFor(String templateId) => _paths[templateId];

  bool get isEmpty => _paths.isEmpty;

  int get count => _paths.length;

  Future<void> load() async {
    final dir = await _directory();
    if (!dir.existsSync()) return;

    for (final entity in dir.listSync()) {
      if (entity is File && entity.path.endsWith('.jpg')) {
        final id = entity.uri.pathSegments.last.replaceAll('.jpg', '');
        _paths[id] = entity.path;
      }
    }
    notifyListeners();
  }

  Future<void> put(String templateId, Uint8List bytes) async {
    final dir = await _directory();
    await dir.create(recursive: true);
    final file = File('${dir.path}/$templateId.jpg');
    await file.writeAsBytes(bytes);

    // Flutter keys its image cache on the file *path*, and every preview for a
    // given scenario writes to the same path. Without this, replacing your
    // photo repaints the tiles with the previous face still cached — the fix
    // looks like it silently did nothing.
    await FileImage(file).evict();

    _paths[templateId] = file.path;
    notifyListeners();
  }

  /// Wipe everything — call when the user replaces their photo, otherwise the
  /// picker keeps showing the old face.
  Future<void> clear() async {
    final dir = await _directory();
    if (dir.existsSync()) {
      for (final entity in dir.listSync()) {
        if (entity is File) await FileImage(entity).evict();
      }
      await dir.delete(recursive: true);
    }
    _paths.clear();
    notifyListeners();
  }

  Future<Directory> _directory() async {
    final base = await getApplicationDocumentsDirectory();
    return Directory('${base.path}/previews');
  }
}

/// Calls `POST /v1/previews` on the Funny You backend.
class HttpPreviewService implements PreviewService {
  HttpPreviewService({
    required this.baseUrl,
    required this.store,
    this.headers = const {},
    this.batchSize = 6,
  });

  final String baseUrl;
  final PreviewStore store;
  final Map<String, String> headers;

  /// Templates per request. Small batches so the grid fills in visibly and one
  /// rate-limit rejection does not cost the whole set.
  final int batchSize;

  @override
  bool get enabled => baseUrl.isNotEmpty;

  @override
  Stream<PreviewBatch> generate({
    required String facePhotoPath,
    required List<VideoTemplate> templates,
  }) async* {
    final face = File(facePhotoPath);
    if (!face.existsSync()) return;

    final bytes = await face.readAsBytes();
    final paths = <String, String>{};
    final errors = <String, String>{};
    var completed = 0;

    for (var i = 0; i < templates.length; i += batchSize) {
      final batch = templates.skip(i).take(batchSize).toList();

      try {
        final result = await _requestBatch(bytes, batch);
        for (final entry in result.entries) {
          await store.put(entry.key, entry.value);
          paths[entry.key] = store.pathFor(entry.key)!;
        }
      } catch (error) {
        for (final template in batch) {
          errors[template.id] = error.toString();
        }
        debugPrint('Preview batch failed: $error');
      }

      completed += batch.length;
      yield PreviewBatch(
        completed: completed,
        total: templates.length,
        paths: Map.unmodifiable(paths),
        errors: Map.unmodifiable(errors),
      );
    }
  }

  Future<Map<String, Uint8List>> _requestBatch(
    Uint8List face,
    List<VideoTemplate> templates,
  ) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${baseUrl.replaceAll(RegExp(r'/$'), '')}/v1/previews'),
    )
      ..headers.addAll(headers)
      ..fields['scenarios'] = jsonEncode({
        for (final t in templates) t.id: t.prompt,
      })
      ..files.add(http.MultipartFile.fromBytes('image', face, filename: 'face.jpg'));

    final response = await http.Response.fromStream(await request.send());
    if (response.statusCode != 200) {
      throw PreviewException(
        'Preview request failed (${response.statusCode})',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return {
      for (final item in (body['previews'] as List? ?? []))
        (item as Map<String, dynamic>)['templateId'] as String:
            base64Decode(item['imageBase64'] as String),
    };
  }
}

class PreviewException implements Exception {
  const PreviewException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Used when no backend is configured. Reports disabled and emits nothing, so
/// the UI silently falls back to the designed gradient artwork.
class DisabledPreviewService implements PreviewService {
  const DisabledPreviewService();

  @override
  bool get enabled => false;

  @override
  Stream<PreviewBatch> generate({
    required String facePhotoPath,
    required List<VideoTemplate> templates,
  }) =>
      const Stream.empty();
}
