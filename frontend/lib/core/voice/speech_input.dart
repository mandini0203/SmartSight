import 'dart:async';

import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Converts one spoken utterance to text.
abstract class SpeechInput {
  Future<bool> initialise();
  bool get isAvailable;

  /// Listens until the user stops speaking; returns the final transcript or
  /// null if nothing was recognised.
  Future<String?> listenOnce({Duration timeout = const Duration(seconds: 8)});
  Future<void> cancel();
}

class DeviceSpeechInput implements SpeechInput {
  final SpeechToText _stt = SpeechToText();
  bool _available = false;

  @override
  bool get isAvailable => _available;

  @override
  Future<bool> initialise() async {
    try {
      _available = await _stt.initialize(onError: (_) {}, onStatus: (_) {});
    } catch (_) {
      _available = false;
    }
    return _available;
  }

  @override
  Future<String?> listenOnce({Duration timeout = const Duration(seconds: 8)}) async {
    if (!_available && !await initialise()) return null;
    final done = Completer<String?>();
    String latest = '';
    await _stt.listen(
      onResult: (SpeechRecognitionResult r) {
        latest = r.recognizedWords;
        if (r.finalResult && !done.isCompleted) done.complete(latest.isEmpty ? null : latest);
      },
      listenOptions: SpeechListenOptions(
        listenFor: timeout,
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.confirmation,
      ),
    );
    return done.future.timeout(timeout + const Duration(seconds: 2), onTimeout: () async {
      await _stt.stop();
      return latest.isEmpty ? null : latest;
    });
  }

  @override
  Future<void> cancel() => _stt.cancel();
}
