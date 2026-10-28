import 'package:flutter/widgets.dart';

import '../core/api/api_exception.dart';
import '../core/app_dependencies.dart';
import '../core/camera/frame_source.dart';
import '../core/guidance/guidance_controller.dart';

/// Shared behaviour for screens that analyse camera frames:
/// registers the screen's task with the [GuidanceController] (so voice
/// commands like "capture" or "start" act on it), optionally captures once as
/// soon as the camera is ready, and records the last error for display.
mixin AnalysisScreenMixin<T extends StatefulWidget> on State<T> {
  late AppDependencies deps;
  String? lastError;
  bool _autostartArmed = false;
  bool _initialised = false;

  String get analysisOwner;
  bool get autostart;
  Future<GuidanceOutcome> analyseFrame(CapturedFrame frame);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    deps = AppScope.of(context);
    if (_initialised) return;
    _initialised = true;
    deps.guidance.attach(analysisOwner, _guarded);
    if (autostart) {
      _autostartArmed = true;
      deps.frames.addListener(_maybeAutostart);
    }
  }

  void _maybeAutostart() {
    if (_autostartArmed && deps.frames.state == CameraState.ready) {
      _autostartArmed = false;
      deps.frames.removeListener(_maybeAutostart);
      deps.guidance.captureOnce();
    }
  }

  Future<GuidanceOutcome> _guarded(CapturedFrame frame) async {
    try {
      final outcome = await analyseFrame(frame);
      if (mounted && lastError != null) setState(() => lastError = null);
      return outcome;
    } on ApiException catch (e) {
      if (mounted) setState(() => lastError = e.userMessage);
      rethrow;
    }
  }

  @override
  void dispose() {
    deps.frames.removeListener(_maybeAutostart);
    deps.guidance.detach(analysisOwner);
    super.dispose();
  }
}
