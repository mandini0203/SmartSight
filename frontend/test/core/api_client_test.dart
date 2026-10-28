import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartsight/core/api/api_client.dart';
import 'package:smartsight/core/api/api_exception.dart';
import 'package:smartsight/core/api/models.dart';

import '../helpers/fakes.dart';

final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]);

SmartSightApi apiWith(http.Client c) => SmartSightApi(baseUrl: 'http://backend.test/', client: c);

void main() {
  group('parses real recorded backend responses', () {
    final backend = FixtureBackend();
    final api = apiWith(backend.client);

    test('status', () async {
      final s = await api.status();
      expect(s.detectorReady, isTrue);
      expect(s.detectorName, contains('YOLOv8'));
    });

    test('supported classes', () async {
      final c = await api.supportedClasses();
      expect(c.length, 80);
      expect(c, contains('cell phone'));
    });

    test('detection', () async {
      final r = await api.detect(jpeg, frameId: 'f1');
      expect(r.frame.width, 810);
      expect(r.frame.frameId, 'f1');
      expect(r.modelFile, 'yolov8n.pt');
      expect(r.detections.map((d) => d.label), containsAll(['bus', 'person']));
      final d = r.detections.first;
      expect(d.bboxNormalised.x2, lessThanOrEqualTo(1));
      expect(d.position!.clockLabel, endsWith("o'clock"));
    });

    test('scan describe', () async {
      final r = await api.scan(jpeg, task: 'describe_surroundings');
      expect(r.context.guidance.message, contains('bus'));
      expect(r.context.reasoner.isTrainedModel, isFalse);
      expect(r.signs, isNull);
    });

    test('scan find_exit includes sign candidates', () async {
      final r = await api.scan(jpeg, task: 'find_exit');
      expect(r.signs, isNotNull);
      for (final c in r.signs!.candidates) {
        expect(c.evidence, isNotEmpty);
      }
    });

    test('colour', () async {
      final r = await api.identifyColour(jpeg, pointX: 0.5, pointY: 0.45);
      expect(r.primary.hex, startsWith('#'));
      expect(r.colours, isNotEmpty);
      expect(r.caveats, isNotEmpty);
    });

    test('intent', () async {
      final r = await api.resolveIntent('where is my phone');
      expect(r.status, IntentStatus.resolved);
      expect(r.intent, 'find_object');
      expect(r.targetLabel, 'cell phone');
      expect(r.personal, isTrue);
    });

    test('item match', () async {
      final r = await api.matchItem(jpeg, references: [jpeg], itemLabel: 'person', itemName: 'test');
      expect(r.status, MatchStatus.found);
      expect(r.bestSimilarity, greaterThan(0.8));
    });

    test('reference check', () async {
      final r = await api.checkReference(jpeg, itemLabel: 'person');
      expect(r.detected, isTrue);
    });

    test('seat context fixture', () {
      final ctx = ContextResult.fromJson(fixture('context_seats')['body'] as Map<String, dynamic>);
      expect(ctx.seats.first.status, SeatStatus.potentiallyUnoccupied);
      expect(ctx.seats.last.status, SeatStatus.likelyOccupied);
      expect(ctx.seats.every((s) => s.evidence.isNotEmpty), isTrue);
    });
  });

  test('multipart request carries the image and form fields', () async {
    late http.Request captured;
    final api = apiWith(MockClient((r) async {
      captured = r;
      return fixtureResponse('scan_describe_bus');
    }));
    await api.scan(jpeg, task: 'find_object', targetLabel: 'cell phone', frameId: 'x', fovDegrees: 70);
    final body = latin1.decode(captured.bodyBytes);
    expect(captured.url.toString(), 'http://backend.test/api/v1/scan');
    expect(captured.headers['content-type'], startsWith('multipart/form-data'));
    expect(body, contains('name="image"'));
    expect(body, contains('name="task"'));
    expect(body, contains('find_object'));
    expect(body, contains('name="target_label"'));
    expect(body, contains('name="camera_fov_degrees"'));
  });

  group('error mapping', () {
    Future<ApiException> errorFor(http.Client c) async {
      try {
        await apiWith(c).detect(jpeg);
      } on ApiException catch (e) {
        return e;
      }
      fail('expected ApiException');
    }

    test('422 invalid image uses the server message', () async {
      final e = await errorFor(MockClient((_) async => fixtureResponse('error_invalid_image')));
      expect(e.kind, ApiErrorKind.invalidRequest);
      expect(e.code, 'invalid_image');
      expect(e.userMessage, contains('could not be decoded'));
    });

    test('unsupported class', () async {
      final e = await errorFor(MockClient((_) async => fixtureResponse('error_unsupported_class')));
      expect(e.kind, ApiErrorKind.unsupported);
    });

    test('503 busy', () async {
      final e = await errorFor(MockClient((_) async => http.Response(
          '{"error":{"code":"service_unavailable","message":"The server is busy."}}', 503)));
      expect(e.kind, ApiErrorKind.busy);
      expect(e.userMessage, 'The server is busy.');
    });

    test('504 timeout', () async {
      final e = await errorFor(MockClient((_) async => http.Response('{"error":{"code":"inference_timeout"}}', 504)));
      expect(e.kind, ApiErrorKind.timeout);
    });

    test('500 with non-JSON body', () async {
      final e = await errorFor(MockClient((_) async => http.Response('<html>oops</html>', 500)));
      expect(e.kind, ApiErrorKind.server);
    });

    test('network unreachable', () async {
      final e = await errorFor(MockClient((_) async => throw const SocketException('no route')));
      expect(e.kind, ApiErrorKind.unreachable);
    });

    test('client timeout', () async {
      final api = SmartSightApi(
        baseUrl: 'http://backend.test',
        client: MockClient((_) => Completer<http.Response>().future),
        requestTimeout: const Duration(milliseconds: 50),
      );
      await expectLater(api.detect(jpeg), throwsA(isA<ApiException>().having((e) => e.kind, 'kind', ApiErrorKind.timeout)));
    });

    test('health check never throws', () async {
      expect(await apiWith(MockClient((_) async => throw const SocketException('x'))).isHealthy(), isFalse);
    });
  });
}
