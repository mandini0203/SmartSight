import '../core/app_dependencies.dart';
import '../core/feedback/haptics.dart';
import '../core/permissions/permission_service.dart';

/// Speaks [prompt], waits for it to finish, then listens for one answer.
///
/// Returns null when nothing was heard or the microphone is not allowed.
/// With [private] (passwords) the answer is not shown in the voice bar.
Future<String?> askByVoice(AppDependencies deps, String prompt, {bool private = false}) async {
  if (await deps.permissions.requestMicrophone() != PermissionResult.granted) {
    await deps.guidance.announce('Microphone permission is needed to fill the form by voice.', remember: false);
    return null;
  }
  await deps.speechOutput.speakAndWait(prompt);
  await deps.haptics.play(HapticCue.tap);
  deps.lastHeard.value = null;
  deps.listening.value = true;
  final heard = await deps.speechInput.listenOnce(timeout: const Duration(seconds: 10));
  deps.listening.value = false;
  if (!private) deps.lastHeard.value = heard;
  return heard;
}
