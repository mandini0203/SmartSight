import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// One captured still frame.
class CapturedFrame {
  CapturedFrame({required this.jpeg, required this.capturedAt, required this.id});

  final Uint8List jpeg;
  final DateTime capturedAt;
  final String id;
}

enum CameraState { uninitialised, initialising, ready, permissionDenied, unavailable }

/// Source of camera frames and the live preview.
abstract class FrameSource extends ChangeNotifier {
  CameraState get state;
  String? get errorMessage;
  Future<void> initialise();
  Future<CapturedFrame> capture();

  /// Live preview widget; only valid when [state] is [CameraState.ready].
  Widget buildPreview();

  /// Preview aspect ratio as width / height in portrait.
  double get previewAspectRatio;
  Future<void> release();

  int _leases = 0;

  /// Screens showing the camera take a lease; the camera is released when the
  /// last lease ends, so stacked camera screens do not fight over it.
  Future<void> acquire() async {
    _leases++;
    await initialise();
  }

  Future<void> releaseLease() async {
    if (_leases > 0) _leases--;
    if (_leases == 0) await release();
  }

  /// App went to background: free the camera but remember the leases.
  Future<void> suspend() => release();

  Future<void> resumeIfLeased() async {
    if (_leases > 0) await initialise();
  }
}

class DeviceFrameSource extends FrameSource {
  CameraController? _controller;
  CameraState _state = CameraState.uninitialised;
  String? _error;
  int _counter = 0;
  bool _capturing = false;

  @override
  CameraState get state => _state;
  @override
  String? get errorMessage => _error;

  @override
  Future<void> initialise() async {
    if (_state == CameraState.ready || _state == CameraState.initialising) return;
    _state = CameraState.initialising;
    notifyListeners();
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _fail(CameraState.unavailable, 'No camera found on this device.');
        return;
      }
      final back = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cameras.first);
      final controller = CameraController(back, ResolutionPreset.high,
          enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
      await controller.initialize();
      await controller.setFlashMode(FlashMode.off);
      _controller = controller;
      _state = CameraState.ready;
      _error = null;
      notifyListeners();
    } on CameraException catch (e) {
      final denied = e.code.contains('AccessDenied') || e.code.contains('Permission');
      _fail(denied ? CameraState.permissionDenied : CameraState.unavailable,
          denied ? 'Camera permission was denied.' : 'The camera could not be started.');
    } catch (_) {
      _fail(CameraState.unavailable, 'The camera could not be started.');
    }
  }

  void _fail(CameraState s, String message) {
    _state = s;
    _error = message;
    notifyListeners();
  }

  @override
  Future<CapturedFrame> capture() async {
    final c = _controller;
    if (c == null || _state != CameraState.ready) {
      throw StateError('Camera is not ready');
    }
    if (_capturing) throw StateError('A capture is already in progress');
    _capturing = true;
    try {
      final file = await c.takePicture();
      final bytes = await file.readAsBytes();
      return CapturedFrame(jpeg: bytes, capturedAt: DateTime.now(), id: 'f${++_counter}');
    } finally {
      _capturing = false;
    }
  }

  @override
  double get previewAspectRatio {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return 3 / 4;
    return 1 / c.value.aspectRatio; // controller reports landscape ratio
  }

  @override
  Widget buildPreview() {
    final c = _controller;
    if (c == null) return const SizedBox.shrink();
    return CameraPreview(c);
  }

  @override
  Future<void> release() async {
    final c = _controller;
    _controller = null;
    _state = CameraState.uninitialised;
    await c?.dispose();
    notifyListeners();
  }
}
