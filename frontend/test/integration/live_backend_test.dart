// End-to-end contract test: the app's real HTTP client against a running
// SmartSight backend doing real YOLOv8 inference.
//
// Skipped unless SMARTSIGHT_LIVE_BACKEND is set, e.g.
//   SMARTSIGHT_LIVE_BACKEND=http://127.0.0.1:8000 \
//   SMARTSIGHT_TEST_IMAGES=<dir containing bus.jpg and zidane.jpg> \
//   flutter test test/integration/live_backend_test.dart
@Tags(['live'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartsight/core/api/api_client.dart';
import 'package:smartsight/core/api/api_exception.dart';
import 'package:smartsight/core/api/models.dart';

void main() {
  final url = Platform.environment['SMARTSIGHT_LIVE_BACKEND'];
  final imagesDir = Platform.environment['SMARTSIGHT_TEST_IMAGES'];
  final skip = url == null || imagesDir == null
      ? 'Set SMARTSIGHT_LIVE_BACKEND and SMARTSIGHT_TEST_IMAGES to run live tests'
      : null;

  late SmartSightApi api;
  late Uint8List bus, zidane;

  setUpAll(() {
    if (skip != null) return;
    api = SmartSightApi(baseUrl: url!);
    bus = File('$imagesDir/bus.jpg').readAsBytesSync();
    zidane = File('$imagesDir/zidane.jpg').readAsBytesSync();
  });

  test('health and status', () async {
    expect(await api.isHealthy(), isTrue);
    final s = await api.status();
    expect(s.detectorReady, isTrue);
  }, skip: skip);

  test('real detection on bus.jpg', () async {
    final sw = Stopwatch()..start();
    final r = await api.detect(bus, frameId: 'live-1');
    sw.stop();
    expect(r.frame.frameId, 'live-1');
    expect(r.detections.map((d) => d.label), containsAll(['bus', 'person']));
    // ignore: avoid_print
    print('detect round trip: ${sw.elapsedMilliseconds} ms (server ${r.totalMs.round()} ms)');
  }, skip: skip);

  test('scan for every task', () async {
    for (final task in ['describe_surroundings', 'find_seat', 'find_exit', 'find_object']) {
      final r = await api.scan(bus, task: task, targetLabel: task == 'find_object' ? 'bus' : null);
      expect(r.context.task, task);
      expect(r.context.guidance.message, isNotEmpty);
      expect(r.context.reasoner.isTrainedModel, isFalse);
      if (task == 'find_exit') expect(r.signs, isNotNull);
    }
  }, skip: skip);

  test('colour, intent, item matching', () async {
    final c = await api.identifyColour(bus, pointX: 0.5, pointY: 0.5);
    expect(c.colours, isNotEmpty);
    final i = await api.resolveIntent('where is my phone');
    expect(i.targetLabel, 'cell phone');
    final same = await api.matchItem(zidane, references: [zidane], itemLabel: 'person');
    expect(same.status, MatchStatus.found);
    final other = await api.matchItem(zidane, references: [bus], itemLabel: 'person');
    expect(other.status, isNot(MatchStatus.found));
  }, skip: skip);

  test('invalid upload is rejected with a readable error', () async {
    await expectLater(
      api.detect(Uint8List.fromList(List.filled(100, 7))),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'invalid_image')),
    );
  }, skip: skip);

  test('unreachable backend gives an unreachable error', () async {
    final dead = SmartSightApi(baseUrl: 'http://127.0.0.1:9', requestTimeout: const Duration(seconds: 3));
    await expectLater(
      dead.detect(bus),
      throwsA(isA<ApiException>().having((e) => e.kind, 'kind', ApiErrorKind.unreachable)),
    );
  }, skip: skip);
}
