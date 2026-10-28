import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartsight/app/app.dart';
import 'package:smartsight/app/theme.dart';
import 'package:smartsight/core/voice/command_interpreter.dart';
import 'package:smartsight/core/voice/voice_command.dart';

import '../helpers/fakes.dart';

Future<TestEnv> pumpApp(WidgetTester tester, {String initial = '/'}) async {
  final env = TestEnv();
  await tester.pumpWidget(SmartSightApp(deps: env.deps, initialLocation: initial));
  await tester.pumpAndSettle();
  return env;
}

void main() {
  group('voice on / off', () {
    test('"voice on" and "voice off" are app commands', () {
      final i = CommandInterpreter();
      expect(i.interpret('voice off')?.command, const VoiceToggleCommand(on: false));
      expect(i.interpret('Voice on.')?.command, const VoiceToggleCommand(on: true));
      expect(i.interpret('please turn the voice off')?.command, const VoiceToggleCommand(on: false));
    });

    testWidgets('every screen header has the logo and the voice switch', (tester) async {
      for (final location in ['/', '/scan', '/items', '/settings', '/profile', '/login']) {
        await tester.pumpWidget(SmartSightApp(key: ValueKey(location), deps: TestEnv().deps, initialLocation: location));
        await tester.pumpAndSettle();
        expect(find.descendant(of: find.byType(AppBar), matching: find.byKey(const Key('app-logo'))), findsOneWidget,
            reason: location);
        expect(find.descendant(of: find.byType(AppBar), matching: find.byKey(const Key('voice-toggle'))),
            findsOneWidget,
            reason: location);
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('saying "voice off" silences the app until "voice on"', (tester) async {
      final env = await pumpApp(tester);
      await env.deps.dispatcher.handle('voice off');
      await tester.pumpAndSettle();
      expect(env.speechOut.spoken.last, 'Voice off. Say voice on to hear me again.');
      expect(env.settings.value.voiceEnabled, isFalse);
      expect(find.text('Voice off'), findsOneWidget);

      final before = env.speechOut.spoken.length;
      await env.deps.dispatcher.handle('help');
      expect(env.speechOut.spoken.length, before, reason: 'nothing is spoken while the voice is off');

      await env.deps.dispatcher.handle('voice on');
      await tester.pumpAndSettle();
      expect(env.settings.value.voiceEnabled, isTrue);
      expect(env.speechOut.spoken.last, 'Voice on.');
      expect(find.text('Voice on'), findsOneWidget);
    });

    testWidgets('the header button toggles the voice', (tester) async {
      final env = await pumpApp(tester, initial: '/scan');
      await tester.tap(find.byKey(const Key('voice-toggle')));
      await tester.pumpAndSettle();
      expect(env.settings.value.voiceEnabled, isFalse);
      expect(find.textContaining('Voice is off'), findsOneWidget);
      await tester.tap(find.byKey(const Key('voice-toggle')));
      await tester.pumpAndSettle();
      expect(env.settings.value.voiceEnabled, isTrue);
    });

    testWidgets('the voice switch is announced as a toggle', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester);
      final node = tester.getSemantics(find.byKey(const Key('voice-toggle')));
      expect(node.label, 'Voice');
      expect(node.flagsCollection.isToggled, Tristate.isTrue);
      handle.dispose();
    });

    testWidgets('the logo goes home', (tester) async {
      await pumpApp(tester, initial: '/settings');
      await tester.tap(find.byKey(const Key('app-logo')));
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byType(AppBar), matching: find.text('Home')), findsOneWidget);
    });
  });

  group('colour themes', () {
    for (final palette in ColourPalette.values) {
      for (final b in Brightness.values) {
        test('${palette.name} ${b.name}: text is readable (WCAG AA)', () {
          final s = buildColourScheme(palette, b);
          for (final (bg, fg, name) in [
            (s.surface, s.onSurface, 'surface'),
            (s.surfaceContainerLow, s.onSurface, 'card'),
            (s.primary, s.onPrimary, 'primary'),
            (s.secondary, s.onSecondary, 'secondary'),
            (s.tertiary, s.onTertiary, 'tertiary'),
            (s.error, s.onError, 'error'),
            (s.primaryContainer, s.onPrimaryContainer, 'primaryContainer'),
            (s.errorContainer, s.onErrorContainer, 'errorContainer'),
            (s.surface, s.primary, 'primary on surface'),
          ]) {
            expect(contrastRatio(bg, fg), greaterThanOrEqualTo(4.5), reason: name);
          }
        });
      }
    }

    test('dark colours get light text and light colours get dark text', () {
      expect(onColour(const Color(0xFF003366)), Colors.white);
      expect(onColour(const Color(0xFFFFE600)).computeLuminance(), lessThan(0.05));
    });

    testWidgets('choosing a colour theme in Settings applies it to the whole app', (tester) async {
      final env = await pumpApp(tester, initial: '/settings');
      await tester.scrollUntilVisible(find.byKey(const Key('palette-yellowOnBlack')), 200);
      await tester.tap(find.byKey(const Key('palette-yellowOnBlack')));
      await tester.pumpAndSettle();
      expect(env.settings.value.colourPalette, ColourPalette.yellowOnBlack);
      final scheme = Theme.of(tester.element(find.byKey(const Key('app-logo')))).colorScheme;
      expect(scheme.brightness, Brightness.dark);
      expect(scheme.surface, const Color(0xFF000000));
      expect(env.speechOut.spoken.last, 'Colours: Yellow on black.');
    });
  });

  testWidgets('home shows the features as two cards per row', (tester) async {
    await pumpApp(tester);
    final scan = tester.getRect(find.byKey(const Key('tile-scan')));
    final items = tester.getRect(find.byKey(const Key('tile-items')));
    expect(scan.top, items.top);
    expect(scan.right, lessThan(items.left));
    expect(scan.height, greaterThanOrEqualTo(scan.width - 1), reason: 'cards are square at the Large size');
  });

  group('screen size', () {
    testWidgets('choosing a size in Settings scales text across the app', (tester) async {
      final env = await pumpApp(tester, initial: '/settings');
      double scaleOf(Finder f) => MediaQuery.textScalerOf(tester.element(f)).scale(10) / 10;
      expect(scaleOf(find.byKey(const Key('app-logo'))), closeTo(1.0, 0.001));
      for (final (size, factor) in [(DisplaySize.normal, 0.85), (DisplaySize.larger, 1.2)]) {
        await tester.tap(find.byKey(Key('size-${size.name}')));
        await tester.pumpAndSettle();
        expect(env.settings.value.displaySize, size);
        expect(scaleOf(find.byKey(const Key('app-logo'))), closeTo(factor, 0.001));
        expect(env.speechOut.spoken.last, 'Screen size: ${size.title}.');
      }
    });

    testWidgets('Normal fits every home feature on a phone screen without scrolling', (tester) async {
      // A 360 x 800 dp phone with its font size turned up, like the test device.
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final env = TestEnv();
      await env.settings.update(env.settings.value.copyWith(displaySize: DisplaySize.normal));
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(size: Size(360, 800), textScaler: TextScaler.linear(1.15)),
        child: SmartSightApp(deps: env.deps),
      ));
      await tester.pumpAndSettle();
      final barTop = tester.getTopLeft(find.byKey(const Key('voice-command-button'))).dy;
      for (final key in ['tile-scan', 'tile-items', 'tile-doorsSigns', 'tile-colour', 'tile-profile', 'tile-settings']) {
        expect(tester.getRect(find.byKey(Key(key))).bottom, lessThan(barTop), reason: key);
      }
    });
  });

  test('the Normal green theme for typical colour vision is offered first', () {
    expect(ColourPalette.values.first, ColourPalette.normal);
  });
}
