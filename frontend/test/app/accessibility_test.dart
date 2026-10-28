import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartsight/app/app.dart';

import '../helpers/fakes.dart';

/// Automated accessibility checks for every screen, in light and dark themes
/// and with large text. These catch tap-target, labelling and contrast
/// regressions; they do not replace testing with TalkBack users.
void main() {
  const screens = {
    'Home': '/',
    'Smart Scan': '/scan',
    'My Items': '/items',
    'Register item': '/items/register',
    'Doors and Signs': '/doors-signs',
    'Colour Finder': '/colour',
    'Settings': '/settings',
    'Log in': '/login',
    'Create account': '/register',
    'My Profile': '/profile',
  };

  for (final brightness in Brightness.values) {
    for (final entry in screens.entries) {
      testWidgets('${entry.key} meets Android tap-target, labelling and contrast guidelines (${brightness.name})',
          (tester) async {
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        usePhoneScreen(tester);
        final handle = tester.ensureSemantics();
        final env = TestEnv();
        await tester.pumpWidget(SmartSightApp(deps: env.deps, initialLocation: entry.value));
        await tester.pumpAndSettle();
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    }
  }

  testWidgets('screens work with 2x text scale without overflow', (tester) async {
    for (final location in screens.values) {
      final env = TestEnv();
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2.0), size: Size(412, 915)),
        child: SmartSightApp(key: ValueKey(location), deps: env.deps, initialLocation: location),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: location);
    }
  });

  testWidgets('critical actions have text labels, not just icons', (tester) async {
    final handle = tester.ensureSemantics();
    final env = TestEnv();
    await tester.pumpWidget(SmartSightApp(deps: env.deps, initialLocation: '/scan'));
    await tester.pumpAndSettle();
    for (final label in ['Speak command', 'Repeat', 'Analyse now', 'Start', 'Stop']) {
      expect(find.bySemanticsLabel(RegExp(label)), findsWidgets, reason: label);
    }
    handle.dispose();
  });

  testWidgets('screen titles are exposed as headers', (tester) async {
    final handle = tester.ensureSemantics();
    final env = TestEnv();
    await tester.pumpWidget(SmartSightApp(deps: env.deps, initialLocation: '/scan'));
    await tester.pumpAndSettle();
    final node = tester.getSemantics(find.descendant(of: find.byType(AppBar), matching: find.text('Smart Scan')));
    expect(node.flagsCollection.isHeader, isTrue);
    handle.dispose();
  });
}
