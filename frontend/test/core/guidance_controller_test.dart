import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartsight/core/api/api_exception.dart';
import 'package:smartsight/core/config/settings_controller.dart';
import 'package:smartsight/core/feedback/haptics.dart';
import 'package:smartsight/core/guidance/guidance_controller.dart';

import '../helpers/fakes.dart';

class Harness {
  Harness(FakeAsync async) : _now = async.getClock(DateTime(2026, 10, 21, 12)).now {
    frames = FakeFrameSource(clock: () => now);
    g = GuidanceController(
      frames: frames,
      speech: speech,
      haptics: haptics,
      settings: () => settings,
      clock: () => now,
    );
  }

  final DateTime Function() _now;
  DateTime get now => _now();
  AppSettings settings = const AppSettings(scanIntervalSeconds: 4, staleAfterSeconds: 8);
  final speech = FakeSpeechOutput();
  final haptics = FakeHaptics();
  late final FakeFrameSource frames;
  late final GuidanceController g;
  int calls = 0;
  Duration taskDelay = const Duration(milliseconds: 500);
  Object? failWith;

  Future<GuidanceOutcome> task(dynamic frame) async {
    calls++;
    await Future<void>.delayed(taskDelay);
    if (failWith != null) throw failWith!;
    return GuidanceOutcome('Result $calls');
  }
}

void main() {
  test('capture once speaks the result and remembers it for repeat', () {
    fakeAsync((async) {
      final h = Harness(async);
      h.g.attach('t', h.task);
      h.g.captureOnce();
      async.elapse(const Duration(seconds: 1));
      expect(h.speech.spoken, ['Result 1']);
      expect(h.haptics.cues, [HapticCue.success]);
      h.g.repeat();
      async.flushMicrotasks();
      expect(h.speech.spoken.last, 'Result 1');
    });
  });

  test('start samples frames at the configured interval; pause/resume/stop control it', () {
    fakeAsync((async) {
      final h = Harness(async);
      h.g.attach('t', h.task);
      h.g.start();
      async.elapse(const Duration(seconds: 9)); // ticks at 0, 4, 8
      expect(h.g.state, GuidanceState.running);
      expect(h.calls, 3);
      expect(h.speech.spoken, containsAllInOrder(['Guidance started.', 'Result 1', 'Result 2']));

      h.g.pause();
      async.elapse(const Duration(seconds: 12));
      expect(h.g.state, GuidanceState.paused);
      expect(h.calls, 3, reason: 'no captures while paused');
      expect(h.speech.spoken.last, 'Guidance paused.');

      h.g.resume();
      async.elapse(const Duration(seconds: 1));
      expect(h.g.state, GuidanceState.running);
      expect(h.calls, 4);

      h.g.stop();
      async.elapse(const Duration(seconds: 12));
      expect(h.g.state, GuidanceState.idle);
      expect(h.calls, 4, reason: 'no captures after stop');
      expect(h.speech.spoken.last, 'Guidance stopped.');
    });
  });

  test('repeat replays the last guidance, not the control acknowledgement', () {
    fakeAsync((async) {
      final h = Harness(async);
      h.g.attach('t', h.task);
      h.g.start();
      async.elapse(const Duration(seconds: 1));
      h.g.pause();
      async.flushMicrotasks();
      h.g.repeat();
      async.flushMicrotasks();
      expect(h.speech.spoken.last, 'Result 1');
    });
  });

  test('a result in flight when paused is discarded, not spoken', () {
    fakeAsync((async) {
      final h = Harness(async);
      h.taskDelay = const Duration(seconds: 2);
      h.g.attach('t', h.task);
      h.g.start();
      async.elapse(const Duration(milliseconds: 500));
      h.g.pause();
      async.elapse(const Duration(seconds: 3));
      expect(h.speech.spoken, isNot(contains('Result 1')));
    });
  });

  test('ticks while busy are dropped (bounded queue of one)', () {
    fakeAsync((async) {
      final h = Harness(async);
      h.settings = const AppSettings(scanIntervalSeconds: 2, staleAfterSeconds: 20);
      h.taskDelay = const Duration(seconds: 5);
      h.g.attach('t', h.task);
      h.g.start();
      async.elapse(const Duration(seconds: 7));
      expect(h.g.ticksDropped, greaterThanOrEqualTo(2));
      expect(h.calls, lessThanOrEqualTo(2));
      h.g.stop();
      async.elapse(const Duration(seconds: 10));
    });
  });

  test('stale results are discarded and never presented as current', () {
    fakeAsync((async) {
      final h = Harness(async);
      h.taskDelay = const Duration(seconds: 10); // longer than staleAfterSeconds (8)
      h.g.attach('t', h.task);
      h.g.captureOnce();
      async.elapse(const Duration(seconds: 11));
      expect(h.g.resultsDiscardedAsStale, 1);
      expect(h.speech.spoken, isNot(contains('Result 1')));
      expect(h.speech.spoken.last, contains('out of date'));
    });
  });

  test('repeat of an old message says it may be out of date', () {
    fakeAsync((async) {
      final h = Harness(async);
      h.g.attach('t', h.task);
      h.g.captureOnce();
      async.elapse(const Duration(seconds: 30));
      h.g.repeat();
      async.flushMicrotasks();
      expect(h.speech.spoken.last, startsWith('From '));
      expect(h.speech.spoken.last, contains('may be out of date: Result 1'));
    });
  });

  test('three consecutive failures pause continuous guidance', () {
    fakeAsync((async) {
      final h = Harness(async);
      h.failWith = const ApiException(ApiErrorKind.unreachable, 'Cannot reach the SmartSight server.');
      h.g.attach('t', h.task);
      h.g.start();
      async.elapse(const Duration(seconds: 13));
      expect(h.g.state, GuidanceState.paused);
      expect(h.speech.spoken.last, contains('Guidance paused'));
      expect(h.haptics.cues.where((c) => c == HapticCue.error).length, 3);
      // The same error is announced once, not on every tick.
      expect(h.speech.spoken.where((s) => s == 'Cannot reach the SmartSight server.').length, 1);
    });
  });

  test('identical continuous results are not re-spoken every tick', () {
    fakeAsync((async) {
      final h = Harness(async);
      h.g.attach('t', (f) async => const GuidanceOutcome('Same'));
      h.g.start();
      async.elapse(const Duration(seconds: 9));
      expect(h.speech.spoken.where((s) => s == 'Same').length, 1);
      h.g.stop();
    });
  });

  test('controls without a screen task explain what to do', () {
    fakeAsync((async) {
      final h = Harness(async);
      h.g.start();
      h.g.captureOnce();
      async.flushMicrotasks();
      expect(h.g.state, GuidanceState.idle);
      expect(h.speech.spoken.first, 'There is nothing to scan on this screen.');
    });
  });

  test('detaching the owner stops guidance', () {
    fakeAsync((async) {
      final h = Harness(async);
      h.g.attach('a', h.task);
      h.g.start();
      async.elapse(const Duration(seconds: 1));
      h.g.detach('a');
      async.elapse(const Duration(seconds: 10));
      expect(h.g.state, GuidanceState.idle);
      expect(h.g.hasTask, isFalse);
      expect(h.calls, 1);
    });
  });

}
