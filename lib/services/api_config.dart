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
/// With nothing defined the app runs on mocks, which is what makes the whole
/// flow demoable on a fresh clone with no backend, no GPU and no keys — just
/// `flutter run`. The mock plays every stage and lands on the result screen
/// without a video file, so nothing pretends a render happened.
///
/// Pointing a **debug** build at a backend on the dev machine is a deliberate
/// act, not the default:
///
/// ```
/// flutter run --dart-define=USE_LOCAL_BACKEND=true
/// ```
///
/// It is opt-in because mocks fabricate a convincing finished flow, and while
/// developing the pipeline that is a trap — it reads as "the pipeline works"
/// when nothing was rendered. Asking for the local backend explicitly means a
/// missing one surfaces as a connection error, which is the truth. Asking for
/// nothing means the app just runs.
abstract final class ApiConfig {
  static const _definedBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const apiKey = String.fromEnvironment('API_KEY');

  /// Android emulators reach the host machine on 10.0.2.2, never 127.0.0.1.
  static const localEmulatorUrl = 'http://10.0.2.2:8000';

  /// Desktop and iOS simulator share the host's loopback.
  static const localHostUrl = 'http://127.0.0.1:8000';

  static const _useLocalBackend =
      bool.fromEnvironment('USE_LOCAL_BACKEND');

  static String get baseUrl {
    if (_definedBaseUrl.isNotEmpty) return _definedBaseUrl;
    if (!kDebugMode || !_useLocalBackend) return '';
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
