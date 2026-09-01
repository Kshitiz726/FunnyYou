import 'api_config.dart';
import 'backend_status.dart';
import 'generation_service.dart';
import 'http_generation_service.dart';
import 'permission_service.dart';
import 'preview_service.dart';
import 'purchase_service.dart';

/// Single place where implementations are chosen.
///
/// With `API_BASE_URL` defined at build time the app talks to the real render
/// backend; without it everything runs on mocks so the flow stays demoable.
class ServiceLocator {
  ServiceLocator._();

  static final ServiceLocator instance = ServiceLocator._();

  final PreviewStore previewStore = PreviewStore();
  final BackendStatus backend = BackendStatus.fromConfig();

  late GenerationService generation = ApiConfig.isConfigured
      ? HttpGenerationService(
          baseUrl: ApiConfig.baseUrl,
          headers: ApiConfig.authHeaders,
        )
      : MockGenerationService();

  late PreviewService previews = ApiConfig.isConfigured
      ? HttpPreviewService(
          baseUrl: ApiConfig.baseUrl,
          headers: ApiConfig.authHeaders,
          store: previewStore,
        )
      : const DisabledPreviewService();

  // Payments stay mocked until StoreKit products exist in App Store Connect.
  PurchaseService purchases = MockPurchaseService();
  PermissionService permissions = PermissionService();
}
