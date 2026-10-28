import 'package:flutter/foundation.dart';

import '../core/app_dependencies.dart';
import '../core/voice/form_speech.dart';
import 'voice_input.dart';

/// One question in a voice-guided form.
class VoiceStep {
  const VoiceStep({
    required this.prompt,
    required this.apply,
    this.optional = false,
    this.private = false,
    this.when,
  });

  final String prompt;

  /// Fills the field from the recognised words. Returns what to say back
  /// ("First name: Nimal."), or throws [VoiceStepError] to ask again.
  final String Function(String spoken) apply;
  final bool optional;

  /// Do not show the answer in the voice bar (passwords).
  final bool private;

  /// The step is asked only when this returns true (checked when reached).
  final bool Function()? when;
}

class VoiceStepError implements Exception {
  const VoiceStepError(this.message);
  final String message;
}

/// Walks the user through a form by voice: asks each question, listens,
/// fills the field and reads it back. Say "skip", "back", "repeat" or "stop".
class VoiceFormFiller {
  VoiceFormFiller(this.deps);

  final AppDependencies deps;
  final ValueNotifier<bool> running = ValueNotifier(false);
  bool _stopRequested = false;
  bool _disposed = false;

  static const _maxAttempts = 3;

  void stop() {
    _stopRequested = true;
    deps.speechInput.cancel();
  }

  Future<void> run(List<VoiceStep> steps, {required String intro, required String outro}) async {
    if (running.value) return;
    running.value = true;
    _stopRequested = false;
    try {
      await deps.speechOutput.speakAndWait('$intro You can say skip, back, repeat, or stop at any time.');
      var i = 0;
      var attempts = 0;
      while (i < steps.length && !_stopRequested) {
        final step = steps[i];
        if (step.when != null && !step.when!()) {
          i++;
          continue;
        }
        final prompt = step.optional ? '${step.prompt} This is optional; say skip to leave it blank.' : step.prompt;
        final heard = await askByVoice(deps, prompt, private: step.private);
        if (_stopRequested) break;
        if (heard == null) {
          attempts++;
          if (attempts >= _maxAttempts) {
            await deps.speechOutput.speakAndWait("I didn't hear an answer. Moving on.");
            (i, attempts) = (i + 1, 0);
          } else {
            await deps.speechOutput.speakAndWait("I didn't hear that.");
          }
          continue;
        }
        switch (matchFormControl(heard)) {
          case FormVoiceControl.stop:
            _stopRequested = true;
            continue;
          case FormVoiceControl.skip:
            (i, attempts) = (i + 1, 0);
            continue;
          case FormVoiceControl.back:
            i = _previous(steps, i);
            attempts = 0;
            continue;
          case FormVoiceControl.repeat:
            continue;
          case null:
            break;
        }
        try {
          await deps.speechOutput.speakAndWait(step.apply(heard));
          (i, attempts) = (i + 1, 0);
        } on VoiceStepError catch (e) {
          attempts++;
          await deps.speechOutput.speakAndWait(e.message);
          if (attempts >= _maxAttempts) {
            await deps.speechOutput.speakAndWait('Moving on. You can fix this field later.');
            (i, attempts) = (i + 1, 0);
          }
        }
      }
      await deps.speechOutput.speakAndWait(_stopRequested ? 'Stopped filling the form by voice.' : outro);
    } finally {
      deps.listening.value = false;
      if (_disposed) {
        running.dispose();
      } else {
        running.value = false;
      }
    }
  }

  int _previous(List<VoiceStep> steps, int i) {
    var j = i - 1;
    while (j > 0 && steps[j].when != null && !steps[j].when!()) {
      j--;
    }
    return j < 0 ? 0 : j;
  }

  /// Safe while a run is in progress: the run stops and cleans up itself.
  void dispose() {
    _disposed = true;
    if (running.value) {
      stop();
    } else {
      running.dispose();
    }
  }
}
