import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartsight/app/app.dart';
import 'package:smartsight/core/actions/command_dispatcher.dart';
import 'package:smartsight/core/voice/command_interpreter.dart';
import 'package:smartsight/core/voice/voice_command.dart';

import '../helpers/fakes.dart';

Finder appBarTitle(String title) =>
    find.descendant(of: find.byType(AppBar), matching: find.text(title));

Future<TestEnv> pumpApp(WidgetTester tester, {String initial = '/'}) async {
  usePhoneScreen(tester);
  final env = TestEnv();
  await tester.pumpWidget(SmartSightApp(deps: env.deps, initialLocation: initial));
  await tester.pumpAndSettle();
  return env;
}

void main() {
  group('voice navigation reaches the right screen for every navigation alias', () {
    for (final entry in CommandInterpreter.aliases.entries) {
      final cmd = entry.key;
      if (cmd is! NavigateCommand) continue;
      for (final phrase in entry.value) {
        testWidgets('"$phrase" -> ${cmd.destination.title}', (tester) async {
          // Start somewhere else so that navigating home is observable too.
          final env = await pumpApp(tester, initial: cmd.destination == AppDestination.home ? '/settings' : '/');
          final outcome = await env.deps.dispatcher.handle(phrase);
          await tester.pumpAndSettle();
          expect(outcome, DispatchOutcome.appCommand);
          final title = cmd.destination.title;
          expect(appBarTitle(title), findsOneWidget);
          expect(env.speechOut.spoken.last, '${cmd.destination.title}.');
        });
      }
    }
  });

  testWidgets('speaking through the Speak command button navigates', (tester) async {
    final env = await pumpApp(tester);
    env.speechIn.queue.add('open colour finder');
    await tester.tap(find.byKey(const Key('voice-command-button')));
    await tester.pumpAndSettle();
    expect(appBarTitle('Colour Finder'), findsOneWidget);
    expect(find.textContaining('Heard: "open colour finder"'), findsOneWidget);
  });

  testWidgets('back returns to home', (tester) async {
    final env = await pumpApp(tester, initial: '/scan');
    expect(appBarTitle('Smart Scan'), findsOneWidget);
    await env.deps.dispatcher.handle('go back');
    await tester.pumpAndSettle();
    expect(appBarTitle('Home'), findsOneWidget);
  });

  testWidgets('touch navigation from home tiles', (tester) async {
    await pumpApp(tester);
    for (final d in [AppDestination.scan, AppDestination.items, AppDestination.doorsSigns, AppDestination.colour,
        AppDestination.settings]) {
      await scrollTo(tester, find.byKey(Key('tile-${d.name}')));
      await tester.tap(find.byKey(Key('tile-${d.name}')));
      await tester.pumpAndSettle();
      expect(appBarTitle(d.title), findsOneWidget, reason: d.title);
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
  });

  group('task intentions go to the backend and open the right screen', () {
    testWidgets('"where is my phone" opens Smart Scan in find-object mode', (tester) async {
      final env = await pumpApp(tester);
      final outcome = await env.deps.dispatcher.handle('where is my phone');
      await tester.pumpAndSettle();
      expect(outcome, DispatchOutcome.taskIntent);
      expect(env.backend.requests, contains('/api/v1/intent/resolve'));
      expect(appBarTitle('Smart Scan'), findsOneWidget);
      expect(find.text('Object to find'), findsOneWidget);
      // Autostart captured a frame and the real recorded scan result was shown.
      expect(env.frames.captures, 1);
      expect(env.backend.requests, contains('/api/v1/scan'));
    });

    testWidgets('a registered personal item is searched with the matcher', (tester) async {
      final env = TestEnv();
      await env.items.add(name: 'My phone', label: 'cell phone', photos: [fixtureBytes]);
      await tester.pumpWidget(SmartSightApp(deps: env.deps));
      await tester.pumpAndSettle();
      await env.deps.dispatcher.handle('where is my phone');
      await tester.pumpAndSettle();
      expect(appBarTitle('Find My phone'), findsOneWidget);
      expect(env.backend.requests, contains('/api/v1/items/match'));
    });

    testWidgets('unsupported object is explained, no navigation', (tester) async {
      final env = await pumpApp(tester);
      final outcome = await env.deps.dispatcher.handle('find my keys');
      await tester.pumpAndSettle();
      expect(outcome, DispatchOutcome.unsupported);
      expect(appBarTitle('Home'), findsOneWidget);
      expect(env.speechOut.spoken.last, contains("can't recognise keys"));
    });

    testWidgets('ambiguous request asks for clarification', (tester) async {
      final env = await pumpApp(tester);
      final outcome = await env.deps.dispatcher.handle('find');
      expect(outcome, DispatchOutcome.clarification);
      expect(env.speechOut.spoken.last, 'What would you like me to find?');
    });

    testWidgets('typed request on home uses the same path', (tester) async {
      final env = await pumpApp(tester);
      await scrollTo(tester, find.byKey(const Key('send-request')));
      await tester.enterText(find.byKey(const Key('request-field')), 'where is my phone');
      await tester.tap(find.byKey(const Key('send-request')));
      await tester.pumpAndSettle();
      expect(appBarTitle('Smart Scan'), findsOneWidget);
      expect(env.backend.requests, contains('/api/v1/intent/resolve'));
    });

    testWidgets('app commands still work when the backend is offline', (tester) async {
      final env = await pumpApp(tester);
      env.backend.offline = true;
      await env.deps.dispatcher.handle('open settings');
      await tester.pumpAndSettle();
      expect(appBarTitle('Settings'), findsOneWidget);
      final outcome = await env.deps.dispatcher.handle('find my phone');
      expect(outcome, DispatchOutcome.failed);
      expect(env.speechOut.spoken.last, contains('server is unavailable'));
    });
  });

  testWidgets('help lists commands', (tester) async {
    final env = await pumpApp(tester);
    await env.deps.dispatcher.handle('what can I say');
    expect(env.speechOut.spoken.last, CommandDispatcher.helpText);
  });
}
