import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

enum CameraAccess { granted, denied, permanentlyDenied, unsupported }

/// Thin wrapper so screens never touch `permission_handler` directly and so
/// desktop builds (used for design review on Windows) degrade gracefully.
class PermissionService {
  static bool get _isMobile => Platform.isIOS || Platform.isAndroid;

  Future<CameraAccess> cameraStatus() async {
    if (!_isMobile) return CameraAccess.unsupported;
    return _map(await Permission.camera.status);
  }

  /// Triggers the native iOS "Would Like to Access the Camera" alert.
  Future<CameraAccess> requestCamera() async {
    if (!_isMobile) return CameraAccess.unsupported;
    return _map(await Permission.camera.request());
  }

  Future<CameraAccess> requestMicrophone() async {
    if (!_isMobile) return CameraAccess.unsupported;
    return _map(await Permission.microphone.request());
  }

  Future<CameraAccess> requestPhotos() async {
    if (!_isMobile) return CameraAccess.unsupported;
    final permission = Platform.isIOS ? Permission.photos : Permission.storage;
    return _map(await permission.request());
  }

  Future<bool> openSettings() => openAppSettings();

  CameraAccess _map(PermissionStatus status) => switch (status) {
        PermissionStatus.granted ||
        PermissionStatus.limited ||
        PermissionStatus.provisional =>
          CameraAccess.granted,
        PermissionStatus.permanentlyDenied ||
        PermissionStatus.restricted =>
          CameraAccess.permanentlyDenied,
        _ => CameraAccess.denied,
      };
}
