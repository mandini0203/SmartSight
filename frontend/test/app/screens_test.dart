import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartsight/app/app.dart';
import 'package:smartsight/core/permissions/permission_service.dart';

import '../helpers/fakes.dart';

Future<TestEnv> pumpAt(WidgetTester tester, String location, {TestEnv? env}) async {
  usePhoneScreen(tester);
  final e = env ?? TestEnv();
  await tester.pumpWidget(SmartSightApp(deps: e.deps, initialLocation: location));
  await tester.pumpAndSettle();
  return e;
}

void main() {
  testWidgets('Smart Scan: capture shows real recorded guidance and detections', (tester) async {
    final env = await pumpAt(tester, '/scan');
    await scrollTo(tester, find.byKey(const Key('capture-button')));
    await tester.tap(find.byKey(const Key('capture-button')));
    await tester.pumpAndSettle();
    expect(env.backend.requests, contains('/api/v1/scan'));
    await scrollTo(tester, find.textContaining('I can see'));
    expect(find.textContaining('I can see'), findsWidgets);
    await scrollTo(tester, find.textContaining('Detected objects'));
    expect(find.textContaining('Detected objects'), findsOneWidget);
    await scrollTo(tester, find.textContaining('rule-based reasoning (not a trained model)'));
    expect(find.textContaining('rule-based reasoning (not a trained model)'), findsOneWidget);
    expect(env.speechOut.spoken.last, contains('I can see'));
  });

  testWidgets('voice "capture" acts on the current screen', (tester) async {
    final env = await pumpAt(tester, '/doors-signs');
    await env.deps.dispatcher.handle('capture');
    await tester.pumpAndSettle();
    expect(env.backend.requests, contains('/api/v1/scan'));
    await scrollTo(tester, find.textContaining('Candidates ('));
    expect(find.textContaining('Candidates ('), findsOneWidget);
  });

  testWidgets('start / pause / resume / stop buttons follow guidance state', (tester) async {
    final env = await pumpAt(tester, '/scan');
    await scrollTo(tester, find.byKey(const Key('start-button')));
    await tester.tap(find.byKey(const Key('start-button')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const Key('pause-button')), findsOneWidget);
    await scrollTo(tester, find.byKey(const Key('pause-button')));
    await tester.tap(find.byKey(const Key('pause-button')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const Key('resume-button')), findsOneWidget);
    await scrollTo(tester, find.byKey(const Key('resume-button')));
    await tester.tap(find.byKey(const Key('resume-button')));
    await tester.pump(const Duration(milliseconds: 200));
    await scrollTo(tester, find.byKey(const Key('stop-button')));
    await tester.tap(find.byKey(const Key('stop-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('start-button')), findsOneWidget);
    expect(env.speechOut.spoken, containsAllInOrder(['Guidance started.', 'Guidance paused.', 'Guidance resumed.',
        'Guidance stopped.']));
  });

  testWidgets('backend offline: clear error, no stale result shown as current', (tester) async {
    final env = TestEnv();
    env.backend.offline = true;
    await pumpAt(tester, '/scan', env: env);
    expect(find.textContaining('Server unavailable'), findsOneWidget);
    await scrollTo(tester, find.byKey(const Key('capture-button')));
    await tester.tap(find.byKey(const Key('capture-button')));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.textContaining('Cannot reach the SmartSight server'));
    expect(find.textContaining('Cannot reach the SmartSight server'), findsWidgets);
    expect(find.textContaining('I can see'), findsNothing);
  });

  testWidgets('a result from before the backend went offline is not shown as current', (tester) async {
    final env = await pumpAt(tester, '/scan');
    await scrollTo(tester, find.byKey(const Key('capture-button')));
    await tester.tap(find.byKey(const Key('capture-button')));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.textContaining('Detected objects'));
    env.backend.offline = true;
    await scrollTo(tester, find.byKey(const Key('capture-button')));
    await tester.tap(find.byKey(const Key('capture-button')));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.textContaining('Cannot reach the SmartSight server'));
    expect(find.textContaining('I can see'), findsNothing);
    expect(find.textContaining('Detected objects'), findsNothing);
  });

  testWidgets('camera permission denied shows an explanation and a labelled action', (tester) async {
    final env = TestEnv();
    env.permissions.camera = PermissionResult.permanentlyDenied;
    await pumpAt(tester, '/colour', env: env);
    expect(find.textContaining('Camera permission is not granted'), findsOneWidget);
    expect(find.text('Open app settings'), findsOneWidget);
  });

  testWidgets('Colour Finder identifies the colour and lists swatches', (tester) async {
    final env = await pumpAt(tester, '/colour');
    await scrollTo(tester, find.byKey(const Key('identify-colour-button')));
    await tester.tap(find.byKey(const Key('identify-colour-button')));
    await tester.pumpAndSettle();
    expect(env.backend.requests, contains('/api/v1/colour/identify'));
    await scrollTo(tester, find.textContaining('of the region'));
    expect(find.textContaining('of the region'), findsWidgets);
    await scrollTo(tester, find.textContaining('not a trained model'));
    expect(find.textContaining('not a trained model'), findsOneWidget);
  });

  testWidgets('register an item, then find it', (tester) async {
    final env = await pumpAt(tester, '/items');
    await scrollTo(tester, find.byKey(const Key('register-item-button')));
    await tester.tap(find.byKey(const Key('register-item-button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('item-name-field')), 'Blue phone');
    await scrollTo(tester, find.byKey(const Key('take-reference-button')));
    await scrollTo(tester, find.byKey(const Key('take-reference-button')));
    await tester.tap(find.byKey(const Key('take-reference-button')));
    await tester.pumpAndSettle();
    expect(env.backend.requests, contains('/api/v1/items/check-reference'));
    await scrollTo(tester, find.byKey(const Key('save-item-button')));
    await scrollTo(tester, find.byKey(const Key('save-item-button')));
    await tester.tap(find.byKey(const Key('save-item-button')));
    await tester.pumpAndSettle();
    expect(env.items.items.single.name, 'Blue phone');
    expect(find.text('Blue phone'), findsOneWidget);

    await scrollTo(tester, find.text('Find'));
    await tester.tap(find.text('Find'));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.byKey(const Key('capture-button')));
    await tester.tap(find.byKey(const Key('capture-button')));
    await tester.pumpAndSettle();
    expect(env.backend.requests, contains('/api/v1/items/match'));
    await scrollTo(tester, find.textContaining('Matcher:'));
    expect(find.textContaining('Matcher:'), findsOneWidget);
  });

  testWidgets('register refuses to save without a name', (tester) async {
    final env = await pumpAt(tester, '/items/register');
    await scrollTo(tester, find.byKey(const Key('save-item-button')));
    await scrollTo(tester, find.byKey(const Key('save-item-button')));
    await tester.tap(find.byKey(const Key('save-item-button')));
    await tester.pumpAndSettle();
    expect(env.items.items, isEmpty);
    expect(env.speechOut.spoken.last, contains('enter a name'));
  });

  testWidgets('settings rejects an invalid server address', (tester) async {
    await pumpAt(tester, '/settings');
    await scrollTo(tester, find.byKey(const Key('backend-url-field')));
    await tester.enterText(find.byKey(const Key('backend-url-field')), 'not a url');
    await scrollTo(tester, find.byKey(const Key('test-connection-button')));
    await tester.tap(find.byKey(const Key('test-connection-button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Enter an address like'), findsOneWidget);
  });

  testWidgets('settings tests a valid server address', (tester) async {
    final env = await pumpAt(tester, '/settings');
    await scrollTo(tester, find.byKey(const Key('backend-url-field')));
    await tester.enterText(find.byKey(const Key('backend-url-field')), 'http://192.168.1.20:8000');
    await scrollTo(tester, find.byKey(const Key('test-connection-button')));
    await tester.tap(find.byKey(const Key('test-connection-button')));
    await tester.pumpAndSettle();
    expect(env.settings.value.backendUrl, 'http://192.168.1.20:8000');
    expect(find.textContaining('Connected'), findsOneWidget);
  });

  testWidgets('smart scan task cards switch the task and explain it', (tester) async {
    await pumpAt(tester, '/scan');
    expect(find.text('Hear what is around you and where things are.'), findsOneWidget);
    expect(find.text('Object to find'), findsNothing);
    await tester.tap(find.byKey(const Key('task-findObject')));
    await tester.pumpAndSettle();
    expect(find.text('Choose an object below, then point the camera around.'), findsOneWidget);
    expect(find.text('Object to find'), findsOneWidget);
  });
}
