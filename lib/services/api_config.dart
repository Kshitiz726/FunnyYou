import 'package:flutter/foundation.dart';

/// Where the render backend lives.
///
/// Supplied at build time so no URL or key is compiled into the source:
///
/// ```
/// flutter run \
///   --dart-define=API_BASE_URL=https://your-pod-8000.proxy.runpod.net \
///   --dart-define=API_KEY=...
/// ```
///
/// In a **release** build with nothing defined the app runs on mocks, which is
/// what makes the whole flow demoable with no backend at all.
///
/// A **debug** build instead points at a backend on the dev machine. Mocks
/// fabricate a finished render — poster art, "Your video is ready!", a Share
/// button — which is indistinguishable from a real result at a glance. During
/// development that is a trap: it reads as "the pipeline works" when nothing
/// was rendered at all. Defaulting debug builds to localhost means a missing
/// backend surfaces as a connection error, which is the truth.
abstract final class ApiConfig {
  static const _definedBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const apiKey = String.fromEnvironment('API_KEY');

  /// Android emulators reach the host machine on 10.0.2.2, never 127.0.0.1.
  static const localEmulatorUrl = 'http://10.0.2.2:8000';

  /// Desktop and iOS simulator share the host's loopback.
  static const localHostUrl = 'http://127.0.0.1:8000';

  static String get baseUrl {
    if (_definedBaseUrl.isNotEmpty) return _definedBaseUrl;
    if (!kDebugMode) return '';
    return defaultTargetPlatform == TargetPlatform.android
        ? localEmulatorUrl
        : localHostUrl;
  }

  static bool get isConfigured => baseUrl.isNotEmpty;

  static Map<String, String> get authHeaders =>
      apiKey.isEmpty ? const {} : {'Authorization': 'Bearer $apiKey'};

  static void debugLogConfig() {
    if (!kDebugMode) return;
    debugPrint(
      isConfigured
          ? 'Funny You: using backend at $baseUrl'
          : 'Funny You: no API_BASE_URL set — running on mock services',
    );
  }
}
