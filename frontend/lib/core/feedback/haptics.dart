import 'package:flutter/services.dart';

/// Distinct vibration patterns so results can be told apart without sound.
enum HapticCue { tap, success, found, warning, error }

abstract class Haptics {
  Future<void> play(HapticCue cue);
}

class DeviceHaptics implements Haptics {
  DeviceHaptics({required this.enabled});

  final bool Function() enabled;

  @override
  Future<void> play(HapticCue cue) async {
    if (!enabled()) return;
    switch (cue) {
      case HapticCue.tap:
        await HapticFeedback.selectionClick();
      case HapticCue.success:
        await HapticFeedback.lightImpact();
      case HapticCue.found:
        await HapticFeedback.heavyImpact();
        await Future<void>.delayed(const Duration(milliseconds: 120));
        await HapticFeedback.heavyImpact();
      case HapticCue.warning:
        await HapticFeedback.mediumImpact();
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await HapticFeedback.mediumImpact();
      case HapticCue.error:
        await HapticFeedback.vibrate();
    }
  }
}
