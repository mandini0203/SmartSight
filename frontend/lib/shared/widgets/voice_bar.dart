import 'package:flutter/material.dart';

import '../../app/theme.dart';

import '../../core/app_dependencies.dart';
import '../../core/feedback/haptics.dart';
import '../../core/permissions/permission_service.dart';

/// Bottom bar on every screen: speak a command, or repeat the last guidance.
class VoiceBar extends StatefulWidget {
  const VoiceBar({super.key});

  @override
  State<VoiceBar> createState() => _VoiceBarState();
}

class _VoiceBarState extends State<VoiceBar> {
  Future<void> _listen() async {
    final deps = AppScope.of(context);
    if (deps.listening.value) {
      await deps.speechInput.cancel();
      deps.listening.value = false;
      return;
    }
    final mic = await deps.permissions.requestMicrophone();
    if (mic != PermissionResult.granted) {
      await deps.guidance.announce(
        'Microphone permission is needed for voice commands. You can still use the buttons.',
        remember: false,
      );
      return;
    }
    await deps.speechOutput.stop(); // keep the app's own voice out of the microphone
    await deps.haptics.play(HapticCue.tap);
    deps.lastHeard.value = null;
    deps.listening.value = true;
    final text = await deps.speechInput.listenOnce();
    deps.listening.value = false;
    deps.lastHeard.value = text;
    if (text == null) {
      await deps.guidance.announce("I didn't hear a command.", remember: false);
      return;
    }
    await deps.dispatcher.handle(text);
  }

  @override
  Widget build(BuildContext context) {
    final deps = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: Listenable.merge([deps.listening, deps.lastHeard, deps.settings]),
      builder: (context, _) => _bar(context, deps, scheme, deps.listening.value, deps.lastHeard.value),
    );
  }

  Widget _bar(BuildContext context, AppDependencies deps, ColorScheme scheme, bool listening, String? heard) {
    return Material(
      color: scheme.surfaceContainerHigh,
      elevation: 8,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!deps.voiceEnabled)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(children: [
                    Icon(Icons.volume_off, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Voice is off. Say "voice on" to turn it on.',
                          style: TextStyle(fontSize: 16, color: scheme.onSurfaceVariant)),
                    ),
                  ]),
                ),
              if (heard != null || listening)
                Semantics(
                  liveRegion: true,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      listening ? 'Listening…' : 'Heard: "$heard"',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: FilledButton.icon(
                      key: const Key('voice-command-button'),
                      onPressed: _listen,
                      icon: Icon(listening ? Icons.stop_circle_outlined : Icons.mic, size: DisplaySize.of(context).iconSize + 2),
                      label: Text(listening ? 'Stop listening' : 'Speak command'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: OutlinedButton.icon(
                      key: const Key('repeat-button'),
                      onPressed: deps.guidance.repeat,
                      icon: Icon(Icons.replay, size: DisplaySize.of(context).iconSize),
                      // Shrinks rather than breaking the word at large text sizes.
                      label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Repeat', maxLines: 1)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
