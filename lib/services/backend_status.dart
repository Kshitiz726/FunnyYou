import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';

/// What the render backend can actually do right now.
///
/// A character swap needs a template clip on the server, and the clips arrive
/// one scenario at a time. Without asking, the app shows forty tiles and lets
/// someone spend a credit to discover that thirty-nine of them have nothing to
/// swap into — the failure lands after the paywall, which is the worst possible
/// place for it.
class BackendStatus extends ChangeNotifier {
  BackendStatus({this.baseUrl = '', this.headers = const {}});

  final String baseUrl;
  final Map<String, String> headers;

  Set<String>? _renderable;
  bool _requiresTemplate = false;
  bool _checked = false;

  /// Null until the first successful check.
  Set<String>? get renderableTemplates => _renderable;

  bool get checked => _checked;

  /// Whether this scenario can be rendered today.
  ///
  /// Optimistic by default: an unreachable backend, a provider that builds
  /// scenes from the prompt, or a check that has not returned yet all mean
  /// "do not block the user". Only a definite answer hides anything.
  bool canRender(String templateId) {
    if (!_requiresTemplate) return true;
    final ready = _renderable;
    if (ready == null) return true;
    return ready.contains(templateId);
  }

  /// Retries, because the one call that matters happens at launch — and on a
  /// cold start the network stack is often not up yet ("Network is
  /// unreachable"). A single silent failure would leave the app permanently
  /// unable to tell ready scenarios from unbuilt ones.
  Future<void> refresh({int attempts = 3}) async {
    if (baseUrl.isEmpty) {
      _checked = true;
      return;
    }

    for (var attempt = 0; attempt < attempts; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(Duration(seconds: 2 * attempt));
      }
      if (await _tryOnce()) return;
    }
    _checked = true;
    notifyListeners();
  }

  Future<bool> _tryOnce() async {
    try {
      final uri = Uri.parse(
        '${baseUrl.replaceAll(RegExp(r'/$'), '')}/v1/health',
      );
      final response =
          await http.get(uri, headers: headers).timeout(const Duration(seconds: 8));

      // 503 still carries a usable body — the backend says it is not ready and
      // why, which is exactly what we want to read.
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      _requiresTemplate = body['requiresTemplate'] as bool? ?? false;
      final list = body['renderableTemplates'] as List?;
      _renderable = list?.map((e) => e.toString()).toSet();
      _checked = true;
      notifyListeners();
      return true;
    } catch (error) {
      debugPrint('Backend status check failed: $error');
      return false;
    }
  }

  /// Ask again if the last answer never arrived. Cheap, and it means opening
  /// the catalogue is a second chance to learn what can be rendered.
  Future<void> refreshIfUnknown() async {
    if (_renderable == null) await refresh(attempts: 1);
  }

  static BackendStatus fromConfig() => BackendStatus(
        baseUrl: ApiConfig.baseUrl,
        headers: ApiConfig.authHeaders,
      );
}
