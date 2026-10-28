import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// How spoken feedback is delivered.
enum SpeechMode {
  /// Screen-reader announcements when TalkBack is on, otherwise the app voice.
  automatic,

  /// Always use the app's text-to-speech voice.
  appVoice,

  /// Always send announcements to the screen reader.
  screenReader,
}

abstract class SpeechOutput {
  Future<void> speak(String text, {bool interrupt = true});

  /// Speaks and returns once speech has finished, so the microphone can be
  /// opened without recording the app's own voice.
  Future<void> speakAndWait(String text);
  Future<void> stop();
  Future<void> setRate(double rate);
}

class DeviceSpeechOutput implements SpeechOutput {
  DeviceSpeechOutput({required this.modeProvider, required this.screenReaderActive});

  final SpeechMode Function() modeProvider;

  /// Whether a screen reader is running (from MediaQuery.accessibleNavigation).
  final bool Function() screenReaderActive;
  final FlutterTts _tts = FlutterTts();
  bool _ready = false;

  Future<void> _init() async {
    if (_ready) return;
    try {
      await _tts.awaitSpeakCompletion(false);
      await _tts.setLanguage('en-GB');
    } catch (_) {
      // Fall back to the engine's default voice.
    }
    _ready = true;
  }

  bool get _useScreenReader {
    return switch (modeProvider()) {
      SpeechMode.screenReader => true,
      SpeechMode.appVoice => false,
      SpeechMode.automatic => screenReaderActive(),
    };
  }

  @override
  Future<void> speak(String text, {bool interrupt = true}) async {
    if (text.trim().isEmpty) return;
    if (_useScreenReader) {
      final view = WidgetsBinding.instance.platformDispatcher.implicitView;
      if (view != null) {
        await SemanticsService.sendAnnouncement(view, text, TextDirection.ltr);
      }
      return;
    }
    await _init();
    if (interrupt) await _tts.stop();
    await _tts.speak(text);
  }

  @override
  Future<void> speakAndWait(String text) async {
    if (text.trim().isEmpty) return;
    if (_useScreenReader) {
      await speak(text);
      // The screen reader gives no completion signal: allow about 2.5 words a second.
      final words = text.split(RegExp(r'\s+')).length;
      await Future<void>.delayed(Duration(milliseconds: 600 + words * 400));
      return;
    }
    await _init();
    await _tts.stop();
    await _tts.awaitSpeakCompletion(true);
    try {
      await _tts.speak(text);
    } finally {
      await _tts.awaitSpeakCompletion(false);
    }
  }

  @override
  Future<void> stop() => _tts.stop();

  @override
  Future<void> setRate(double rate) async {
    await _init();
    await _tts.setSpeechRate(rate.clamp(0.1, 1.0));
  }
}

/// Silences [inner] while [enabled] returns false ("voice off"). Stopping
/// and rate changes always pass through.
class SwitchableSpeechOutput implements SpeechOutput {
  SwitchableSpeechOutput(this.inner, {required this.enabled});

  final SpeechOutput inner;
  final bool Function() enabled;

  @override
  Future<void> speak(String text, {bool interrupt = true}) async {
    if (enabled()) await inner.speak(text, interrupt: interrupt);
  }

  @override
  Future<void> speakAndWait(String text) async {
    if (enabled()) await inner.speakAndWait(text);
  }

  @override
  Future<void> stop() => inner.stop();

  @override
  Future<void> setRate(double rate) => inner.setRate(rate);
}
