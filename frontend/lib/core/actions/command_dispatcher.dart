import '../api/api_exception.dart';
import '../api/models.dart';
import '../app_dependencies.dart';
import '../feedback/haptics.dart';
import '../voice/voice_command.dart';

/// Where an utterance was handled — useful for UI feedback and tests.
enum DispatchOutcome { appCommand, taskIntent, clarification, unsupported, failed, empty }

/// Executes recognised speech or typed requests.
///
/// App commands (navigation, start/pause/resume/stop/repeat, capture, help)
/// are interpreted on the phone by the deterministic CommandInterpreter and
/// work offline.
/// Everything else is a real-world task intention and is sent to the
/// backend's rule-based intent resolver.
class CommandDispatcher {
  CommandDispatcher({
    required this.deps,
    required this.go,
    required this.canPop,
    required this.pop,
  });

  final AppDependencies deps;
  final void Function(String location) go;
  final bool Function() canPop;
  final void Function() pop;

  Future<DispatchOutcome> handle(String text) async {
    if (text.trim().isEmpty) {
      await deps.guidance.announce("I didn't hear anything. Please try again.", remember: false);
      return DispatchOutcome.empty;
    }
    final match = deps.interpreter.interpret(text);
    if (match != null) {
      await execute(match.command);
      return DispatchOutcome.appCommand;
    }
    return _resolveTask(text);
  }

  Future<void> execute(VoiceCommand command) async {
    final g = deps.guidance;
    switch (command) {
      case NavigateCommand(:final destination):
        await deps.haptics.play(HapticCue.tap);
        go(destination.path);
        await g.announce('${destination.title}.', remember: false);
      case BackCommand():
        if (canPop()) {
          pop();
        } else {
          go(AppDestination.home.path);
        }
        await g.announce('Back.', remember: false);
      case ControlCommand(:final action):
        switch (action) {
          case ControlAction.start:
            await g.start();
          case ControlAction.pause:
            await g.pause();
          case ControlAction.resume:
            await g.resume();
          case ControlAction.stop:
            await g.stop();
          case ControlAction.repeat:
            await g.repeat();
          case ControlAction.capture:
            await g.captureOnce();
        }
      case SignOutCommand():
        if (!deps.auth.isSignedIn) {
          await g.announce('You are not signed in.', remember: false);
          return;
        }
        await deps.auth.signOut();
        go(AppDestination.home.path);
        await g.announce('Signed out. You are now using SmartSight as a guest.', remember: false);
      case VoiceToggleCommand(:final on):
        await deps.setVoiceEnabled(on);
      case HelpCommand():
        await g.announce(helpText, remember: false);
    }
  }

  static const helpText = 'You can say: smart scan, my items, doors and signs, colour finder, settings, or home. '
      'For your account say: my profile, log in, create account, or sign out. '
      'Say voice off to silence me, and voice on to hear me again. '
      'On a scanning screen say: capture, start, pause, resume, stop, or repeat. '
      'You can also ask: find my phone, find the exit, find a place to sit, what colour is this, '
      'or describe my surroundings.';

  Future<DispatchOutcome> _resolveTask(String text) async {
    final g = deps.guidance;
    IntentResult r;
    try {
      r = await deps.api.resolveIntent(text);
    } on ApiException catch (e) {
      await deps.haptics.play(HapticCue.error);
      await g.announce(
        e.kind == ApiErrorKind.unreachable || e.kind == ApiErrorKind.timeout
            ? "I couldn't understand that as an app command, and the server is unavailable for other requests."
            : e.userMessage,
        remember: false,
      );
      return DispatchOutcome.failed;
    }

    switch (r.status) {
      case IntentStatus.needsClarification:
        await g.announce(r.clarificationQuestion ?? r.message, remember: false);
        return DispatchOutcome.clarification;
      case IntentStatus.unsupported:
        await g.announce(r.message, remember: false);
        return DispatchOutcome.unsupported;
      case IntentStatus.resolved:
        break;
    }

    switch (r.intent) {
      case 'find_object':
        final label = r.targetLabel!;
        final item = r.personal ? deps.items.firstWithLabel(label) : null;
        if (item != null) {
          go('/items/find/${item.id}?autostart=1');
          await g.announce('Looking for ${item.name}.', remember: false);
        } else {
          go(Uri(path: '/scan', queryParameters: {'task': 'find_object', 'target': label, 'autostart': '1'})
              .toString());
          final note = r.personal ? ' You have not registered your ${r.targetObject}, so I will look for any.' : '';
          await g.announce('Looking for a ${r.targetObject}.$note', remember: false);
        }
      case 'find_seat':
        go('/scan?task=find_seat&autostart=1');
        await g.announce(r.message, remember: false);
      case 'find_exit' || 'read_signs':
        go('/doors-signs?autostart=1');
        await g.announce(r.message, remember: false);
      case 'identify_colour':
        go('/colour?autostart=1');
        await g.announce(r.message, remember: false);
      case 'describe_surroundings':
        go('/scan?task=describe_surroundings&autostart=1');
        await g.announce(r.message, remember: false);
      default:
        await g.announce("Sorry, I can't do that yet.", remember: false);
        return DispatchOutcome.unsupported;
    }
    return DispatchOutcome.taskIntent;
  }
}
