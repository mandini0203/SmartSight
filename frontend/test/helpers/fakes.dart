// Test doubles for device services. These exist only in tests; the app never
// uses them, and none of them fabricate detections — API responses come from
// fixtures recorded from the real backend (see test/fixtures/README.md).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartsight/core/api/api_client.dart';
import 'package:smartsight/core/app_dependencies.dart';
import 'package:smartsight/core/auth/google_auth.dart';
import 'package:smartsight/core/auth/token_store.dart';
import 'package:smartsight/core/camera/frame_source.dart';
import 'package:smartsight/core/config/settings_controller.dart';
import 'package:smartsight/core/feedback/haptics.dart';
import 'package:smartsight/core/feedback/speech_output.dart';
import 'package:smartsight/core/permissions/permission_service.dart';
import 'package:smartsight/core/storage/item_repository.dart';
import 'package:smartsight/core/voice/speech_input.dart';

class FakeSpeechInput implements SpeechInput {
  final List<String?> queue = [];
  @override
  bool get isAvailable => true;
  @override
  Future<bool> initialise() async => true;
  @override
  Future<String?> listenOnce({Duration timeout = const Duration(seconds: 8)}) async =>
      queue.isEmpty ? null : queue.removeAt(0);
  @override
  Future<void> cancel() async {}
}

class FakeSpeechOutput implements SpeechOutput {
  final List<String> spoken = [];
  @override
  Future<void> speak(String text, {bool interrupt = true}) async => spoken.add(text);
  @override
  Future<void> speakAndWait(String text) async => spoken.add(text);
  @override
  Future<void> stop() async {}
  @override
  Future<void> setRate(double rate) async {}
}

class FakeHaptics implements Haptics {
  final List<HapticCue> cues = [];
  @override
  Future<void> play(HapticCue cue) async => cues.add(cue);
}

class FakePermissions implements PermissionService {
  PermissionResult camera = PermissionResult.granted;
  PermissionResult microphone = PermissionResult.granted;
  @override
  Future<PermissionResult> requestCamera() async => camera;
  @override
  Future<PermissionResult> requestMicrophone() async => microphone;
  @override
  Future<void> openSettings() async {}
}

/// Camera stand-in: returns a tiny placeholder JPEG header. The bytes are only
/// forwarded to the mocked HTTP layer; they are never "detected".
class FakeFrameSource extends FrameSource {
  FakeFrameSource({DateTime Function()? clock}) : now = clock ?? DateTime.now;

  DateTime Function() now;
  CameraState _state = CameraState.uninitialised;
  int captures = 0;
  Duration captureDelay = Duration.zero;

  @override
  CameraState get state => _state;
  @override
  String? get errorMessage => null;
  @override
  Future<void> initialise() async {
    _state = CameraState.ready;
    notifyListeners();
  }

  @override
  Future<CapturedFrame> capture() async {
    if (captureDelay > Duration.zero) await Future<void>.delayed(captureDelay);
    captures++;
    return CapturedFrame(
        jpeg: Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]), capturedAt: now(), id: 'test$captures');
  }

  @override
  Widget buildPreview() => const ColoredBox(color: Colors.black);
  @override
  double get previewAspectRatio => 3 / 4;
  @override
  Future<void> release() async {
    _state = CameraState.uninitialised;
    notifyListeners();
  }
}

class MemoryItemRepository extends ItemRepository {
  final List<PersonalItem> _items = [];
  final Map<String, List<Uint8List>> _photos = {};

  @override
  List<PersonalItem> get items => List.unmodifiable(_items);
  @override
  Future<void> load() async {}

  @override
  Future<PersonalItem> add({required String name, required String label, required List<Uint8List> photos}) async {
    final id = 'item${_items.length + 1}';
    final item = PersonalItem(
        id: id, name: name, label: label, referencePaths: [for (var i = 0; i < photos.length; i++) '$id/$i'],
        createdAt: DateTime(2026));
    _items.add(item);
    _photos[id] = photos;
    notifyListeners();
    return item;
  }

  @override
  Future<void> delete(String id) async {
    _items.removeWhere((i) => i.id == id);
    _photos.remove(id);
    notifyListeners();
  }

  @override
  Future<List<Uint8List>> references(PersonalItem item) async => _photos[item.id] ?? [];
}

class MemoryTokenStore implements TokenStore {
  final Map<String, String> values = {};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

class FakeGoogleAuth implements GoogleAuth {
  /// Returned by [signIn]; null simulates closing the account chooser.
  String? idToken = 'google-id-token-for-tests';
  int signOuts = 0;
  @override
  bool get isConfigured => true;
  @override
  Future<String?> signIn() async => idToken;
  @override
  Future<void> signOut() async => signOuts++;
}

/// Loads a fixture recorded from the real backend.
Map<String, dynamic> fixture(String name) {
  final f = File('test/fixtures/$name.json');
  return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
}

http.Response fixtureResponse(String name) {
  final j = fixture(name);
  return http.Response(jsonEncode(j['body']), j['status_code'] as int,
      headers: {'content-type': 'application/json'});
}

/// Routes requests to recorded fixtures. Records request paths for assertions.
class FixtureBackend {
  final List<String> requests = [];
  final List<http.BaseRequest> raw = [];
  bool offline = false;

  /// Overrides for specific paths.
  final Map<String, http.Response Function(http.Request)> overrides = {};

  http.Client get client => MockClient((request) async {
        requests.add(request.url.path);
        raw.add(request);
        if (offline) throw const SocketException('offline');
        final o = overrides[request.url.path];
        if (o != null) return o(request);
        switch (request.url.path) {
          case '/health':
            return http.Response('{"status":"ok","version":"1.0.0","time":"2026-10-21T00:00:00Z"}', 200);
          case '/api/v1/status':
            return fixtureResponse('status');
          case '/api/v1/detection/classes':
            return fixtureResponse('classes');
          case '/api/v1/detection':
            return fixtureResponse('detection_bus');
          case '/api/v1/scan':
            final body = utf8.decode(request.bodyBytes, allowMalformed: true);
            return fixtureResponse(body.contains('find_exit') ? 'scan_find_exit_bus' : 'scan_describe_bus');
          case '/api/v1/signs/detect':
            return fixtureResponse('signs_bus');
          case '/api/v1/colour/identify':
            return fixtureResponse('colour_bus');
          case '/api/v1/items/match':
            return fixtureResponse('items_match_found');
          case '/api/v1/items/check-reference':
            return fixtureResponse('items_check_reference');
          case '/api/v1/intent/resolve':
            final text = (jsonDecode(request.body) as Map)['text'] as String;
            if (text.contains('keys')) return fixtureResponse('intent_keys');
            if (text.trim() == 'find') return fixtureResponse('intent_clarify');
            return fixtureResponse('intent_find_phone');
        }
        return http.Response('{"error":{"code":"not_found","message":"Not Found"}}', 404);
      });
}

class TestEnv {
  TestEnv({DateTime Function()? clock}) {
    frames = FakeFrameSource(clock: clock);
    deps = AppDependencies(
      settings: settings,
      apiFactory: (url) => SmartSightApi(baseUrl: url, client: backend.client),
      speechInput: speechIn,
      speechOutput: speechOut,
      haptics: haptics,
      frames: frames,
      permissions: permissions,
      items: items,
      tokenStore: tokens,
      googleAuth: google,
      clock: clock,
    );
  }

  final settings = SettingsController(const AppSettings(backendUrl: 'http://backend.test'));
  final backend = FixtureBackend();
  final speechIn = FakeSpeechInput();
  final speechOut = FakeSpeechOutput();
  final haptics = FakeHaptics();
  final permissions = FakePermissions();
  final items = MemoryItemRepository();
  final tokens = MemoryTokenStore();
  final google = FakeGoogleAuth();
  late final FakeFrameSource frames;
  late final AppDependencies deps;
}

/// Placeholder image bytes (a minimal JPEG marker pair) for fake photos.
final Uint8List fixtureBytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]);

/// Scrolls the page's list until [finder] is built, then brings its first
/// match into view. Works when the finder matches several widgets.
Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  final list = find.byType(Scrollable).first;
  for (final step in const [Offset(0, -250), Offset(0, 250)]) {
    for (var i = 0; i < 40 && finder.evaluate().isEmpty; i++) {
      await tester.drag(list, step);
      await tester.pump();
    }
  }
  expect(finder, findsWidgets, reason: 'not found after scrolling');
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
}

/// Use a typical Android phone viewport (412 x 915 dp) instead of 800 x 600.
void usePhoneScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1080 / 412;
  addTearDown(tester.view.reset);
}
