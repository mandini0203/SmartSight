import 'package:permission_handler/permission_handler.dart';

enum PermissionResult { granted, denied, permanentlyDenied }

abstract class PermissionService {
  Future<PermissionResult> requestCamera();
  Future<PermissionResult> requestMicrophone();
  Future<void> openSettings();
}

class DevicePermissionService implements PermissionService {
  Future<PermissionResult> _request(Permission p) async {
    final status = await p.request();
    if (status.isGranted || status.isLimited) return PermissionResult.granted;
    if (status.isPermanentlyDenied || status.isRestricted) return PermissionResult.permanentlyDenied;
    return PermissionResult.denied;
  }

  @override
  Future<PermissionResult> requestCamera() => _request(Permission.camera);

  @override
  Future<PermissionResult> requestMicrophone() => _request(Permission.microphone);

  @override
  Future<void> openSettings() => openAppSettings();
}
