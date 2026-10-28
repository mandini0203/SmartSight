import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/api_exception.dart';
import '../camera/frame_source.dart';
import '../config/settings_controller.dart';
import '../feedback/haptics.dart';
import '../feedback/speech_output.dart';

enum GuidanceState { idle, running, paused }

/// What a screen's analysis produced for one frame.
class GuidanceOutcome {
  const GuidanceOutcome(this.message, {this.cue = HapticCue.success});
  final String message;
  final HapticCue cue;
}

/// Analyses one captured frame (typically by calling the backend).
typedef GuidanceTask = Future<GuidanceOutcome> Function(CapturedFrame frame);

/// Runs capture-and-analyse once, or continuously with frame sampling.
///
/// Resource rules:
/// * at most one frame is in flight; timer ticks that arrive while busy are
///   dropped, not queued (bounded queue of size 1);
/// * frames are sampled every `scanIntervalSeconds`;
/// * a result older than `staleAfterSeconds` (from capture time) is discarded
///   and never spoken as a current observation;
/// * pausing or stopping invalidates any result still in flight;
/// * three consecutive failures in continuous mode pause guidance.
class GuidanceController extends ChangeNotifier {
  GuidanceController({
    required this.frames,
    required this.speech,
    required this.haptics,
    required this.settings,
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final FrameSource frames;
  final SpeechOutput speech;
  final Haptics haptics;
  final AppSettings Function() settings;
  final DateTime Function() _now;

  GuidanceState _state = GuidanceState.idle;
  String? _taskOwner;
  GuidanceTask? _task;
  Timer? _timer;
  int _generation = 0;
  bool _busy = false;
  int _consecutiveErrors = 0;

  String? _lastMessage;
  DateTime? _lastMessageAt;
  String? _lastError;
  int framesAnalysed = 0;
  int ticksDropped = 0;
  int resultsDiscardedAsStale = 0;

  GuidanceState get state => _state;
  bool get busy => _busy;
  bool get hasTask => _task != null;
  String? get taskOwner => _taskOwner;
  String? get lastMessage => _lastMessage;
  DateTime? get lastMessageAt => _lastMessageAt;
  String? get lastError => _lastError;

  Duration? get lastMessageAge => _lastMessageAt == null ? null : _now().difference(_lastMessageAt!);

  bool get lastMessageIsStale {
    final age = lastMessageAge;
    return age != null && age > Duration(seconds: settings().staleAfterSeconds);
  }

  /// A screen makes its analysis available to voice and touch controls.
  void attach(String owner, GuidanceTask task) {
    if (_taskOwner != owner) stop(silent: true);
    _taskOwner = owner;
    _task = task;
    notifyListeners();
  }

  void detach(String owner) {
    if (_taskOwner != owner) return;
    stop(silent: true);
    _task = null;
    _taskOwner = null;
    notifyListeners();
  }

  /// Capture and analyse a single frame.
  Future<void> captureOnce() async {
    if (_task == null) {
      await _say('Open Smart Scan, Doors and Signs, Colour Finder or an item search first.', remember: false);
      return;
    }
    if (_busy) {
      await _say('Still analysing the previous photo.', remember: false);
      return;
    }
    await _analyse(_generation, continuous: false);
  }

  Future<void> start() async {
    if (_task == null) {
      await _say('There is nothing to scan on this screen.', remember: false);
      return;
    }
    if (_state == GuidanceState.running) return;
    _consecutiveErrors = 0;
    _setState(GuidanceState.running);
    await haptics.play(HapticCue.tap);
    await _say('Guidance started.', remember: false);
    _schedule();
    unawaited(_tick());
  }

  Future<void> pause() async {
    if (_state != GuidanceState.running) {
      await _say(_state == GuidanceState.paused ? 'Guidance is already paused.' : 'Guidance is not running.', remember: false);
      return;
    }
    _cancelTimer();
    _generation++;
    _setState(GuidanceState.paused);
    await _say('Guidance paused.', remember: false);
  }

  Future<void> resume() async {
    if (_state != GuidanceState.paused) {
      if (_state == GuidanceState.idle) {
        await start();
      } else {
        await _say('Guidance is already running.', remember: false);
      }
      return;
    }
    _consecutiveErrors = 0;
    _setState(GuidanceState.running);
    await _say('Guidance resumed.', remember: false);
    _schedule();
    unawaited(_tick());
  }

  Future<void> stop({bool silent = false}) async {
    final wasActive = _state != GuidanceState.idle;
    _cancelTimer();
    _generation++;
    _setState(GuidanceState.idle);
    if (!silent) {
      await speech.stop();
      if (wasActive) await _say('Guidance stopped.', remember: false);
    }
  }

  Future<void> repeat() async {
    final msg = _lastMessage;
    if (msg == null) {
      await _say('There is nothing to repeat yet.', remember: false);
      return;
    }
    if (lastMessageIsStale) {
      final s = lastMessageAge!.inSeconds;
      await _say('From $s seconds ago, which may be out of date: $msg', remember: false);
    } else {
      await _say(msg, remember: false);
    }
  }

  // ------------------------------------------------------------------
  void _schedule() {
    _cancelTimer();
    _timer = Timer.periodic(Duration(seconds: settings().scanIntervalSeconds), (_) => _tick());
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick() async {
    if (_state != GuidanceState.running) return;
    if (_busy) {
      ticksDropped++;
      return;
    }
    await _analyse(_generation, continuous: true);
  }

  Future<void> _analyse(int generation, {required bool continuous}) async {
    final task = _task;
    if (task == null) return;
    _busy = true;
    notifyListeners();
    try {
      final frame = await frames.capture();
      final outcome = await task(frame);
      if (generation != _generation) return; // paused/stopped meanwhile
      final age = _now().difference(frame.capturedAt);
      if (age > Duration(seconds: settings().staleAfterSeconds)) {
        resultsDiscardedAsStale++;
        _lastError = 'A result arrived too late and was discarded.';
        if (!continuous) await _say('That result took too long and may be out of date. Please try again.');
        return;
      }
      framesAnalysed++;
      _consecutiveErrors = 0;
      _lastError = null;
      await haptics.play(outcome.cue);
      // In continuous mode, do not repeat an identical sentence every tick.
      if (!continuous || outcome.message != _lastMessage || lastMessageIsStale) {
        await _say(outcome.message);
      } else {
        _lastMessageAt = _now();
      }
    } on ApiException catch (e) {
      if (generation != _generation) return;
      await _handleError(e.userMessage, continuous);
    } on StateError catch (e) {
      if (generation != _generation) return;
      await _handleError(e.message.contains('in progress') ? 'Camera busy.' : 'The camera is not ready.', continuous);
    } catch (_) {
      if (generation != _generation) return;
      await _handleError('Something went wrong while analysing the photo.', continuous);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> _handleError(String message, bool continuous) async {
    _consecutiveErrors++;
    final repeated = message == _lastError;
    _lastError = message;
    await haptics.play(HapticCue.error);
    if (continuous && _consecutiveErrors >= 3) {
      _cancelTimer();
      _generation++;
      _setState(GuidanceState.paused);
      await _say('$message Guidance paused. Say resume to try again.', remember: false);
      return;
    }
    if (!repeated || !continuous) await _say(message, remember: false);
  }

  Future<void> _say(String text, {bool remember = true}) async {
    if (remember) {
      _lastMessage = text;
      _lastMessageAt = _now();
      notifyListeners();
    }
    await speech.speak(text);
  }

  /// For messages produced outside a frame analysis (e.g. intent replies).
  Future<void> announce(String text, {bool remember = true}) => _say(text, remember: remember);

  void _setState(GuidanceState s) {
    _state = s;
    notifyListeners();
  }

  @override
  void dispose() {
    _cancelTimer();
    super.dispose();
  }
}
