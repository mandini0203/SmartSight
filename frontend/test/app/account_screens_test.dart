import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:smartsight/app/app.dart';
import 'package:smartsight/core/auth/nic.dart';
import 'package:smartsight/features/account/profile_form.dart';
import 'package:smartsight/shared/voice_form_filler.dart';

import '../helpers/accounts.dart';
import '../helpers/fakes.dart';

Finder appBarTitle(String title) => find.descendant(of: find.byType(AppBar), matching: find.text(title));

Finder field(String key) => find.descendant(of: find.byKey(Key(key)), matching: find.byType(TextField));

Future<TestEnv> pumpApp(WidgetTester tester, String location, {TestEnv? env}) async {
  usePhoneScreen(tester);
  final e = env ?? TestEnv();
  await tester.pumpWidget(SmartSightApp(deps: e.deps, initialLocation: location));
  await tester.pumpAndSettle();
  return e;
}

http.Response http200(Map<String, dynamic> body) =>
    http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});

Future<void> enter(WidgetTester tester, String key, String text) async {
  await scrollTo(tester, find.byKey(Key(key)));
  await tester.enterText(field(key), text);
  await tester.pumpAndSettle();
}

Future<void> tapKey(WidgetTester tester, String key) async {
  await scrollTo(tester, find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

void main() {
  group('registration form', () {
    testWidgets('a valid NIC fills in birthday, age and gender', (tester) async {
      await pumpApp(tester, '/register');
      await enter(tester, 'nic-field', '986234567V');
      final age = ageOn(DateTime(1998, 5, 2));
      await scrollTo(tester, find.byKey(const Key('birthday-tile')));
      expect(find.text('2 May 1998 · Age $age'), findsOneWidget);
      expect(find.text('Filled in from your NIC.'), findsWidgets);
      await scrollTo(tester, find.byKey(const Key('gender-field')));
      expect(find.descendant(of: find.byKey(const Key('gender-field')), matching: find.text('Female')), findsOneWidget);
    });

    testWidgets('WhatsApp number is asked for only when it differs', (tester) async {
      await pumpApp(tester, '/register');
      await scrollTo(tester, find.byKey(const Key('whatsapp-same-checkbox')));
      expect(find.byKey(const Key('whatsapp-field')), findsNothing);
      await tester.tap(find.byKey(const Key('whatsapp-same-checkbox')));
      await tester.pumpAndSettle();
      await scrollTo(tester, find.byKey(const Key('whatsapp-field')));
      expect(find.byKey(const Key('whatsapp-field')), findsOneWidget);
    });

    testWidgets('missing fields are reported, spoken and shown under each field', (tester) async {
      final env = await pumpApp(tester, '/register');
      await tapKey(tester, 'create-account-button');
      expect(env.speechOut.spoken.last, startsWith('Please fix'));
      expect(env.backend.requests, isNot(contains('/api/v1/auth/register')));
      await scrollTo(tester, find.text('Enter your first name.'));
      expect(find.text('Enter your first name.'), findsOneWidget);
    });

    testWidgets('a complete form creates the account and greets the user', (tester) async {
      final env = TestEnv();
      Map<String, dynamic>? sent;
      env.backend.overrides['/api/v1/auth/register'] = (r) {
        sent = jsonDecode(r.body) as Map<String, dynamic>;
        return sessionResponse(isNew: true, status: 201);
      };
      await pumpApp(tester, '/register', env: env);
      await enter(tester, 'email-field', 'Nimal@Example.com');
      await enter(tester, 'password-field', 'secret123');
      await enter(tester, 'first-name-field', 'Nimal');
      await enter(tester, 'last-name-field', 'Perera');
      await enter(tester, 'nic-field', '199812300001');
      await enter(tester, 'address1-field', '12 Galle Road');
      await enter(tester, 'address3-field', 'Colombo');
      await enter(tester, 'postal-code-field', '00400');
      await enter(tester, 'mobile-field', '077 123 4567');
      await tapKey(tester, 'create-account-button');

      expect(sent, isNotNull);
      expect(sent!['email'], 'nimal@example.com');
      expect(sent!['nic'], '199812300001');
      expect(sent!['birthday'], '1998-05-02');
      expect(sent!['gender'], 'male');
      expect(sent!['mobile'], '+94771234567');
      expect(sent!['whatsapp_same_as_mobile'], isTrue);
      expect(sent!['address_line2'], isNull);
      expect(appBarTitle('Home'), findsOneWidget);
      expect(find.text('Hello, Nimal. What would you like to do?'), findsOneWidget);
      expect(env.speechOut.spoken, contains('Welcome, Nimal. Your account has been created.'));
    });

    testWidgets('server errors such as a used email are shown', (tester) async {
      final env = TestEnv();
      env.backend.overrides['/api/v1/auth/register'] =
          (_) => errorResponse(409, 'email_in_use', 'An account with this email already exists. Sign in instead.');
      await pumpApp(tester, '/register', env: env);
      await enter(tester, 'email-field', 'a@b.com');
      await enter(tester, 'password-field', 'secret123');
      await enter(tester, 'first-name-field', 'Nimal');
      await enter(tester, 'last-name-field', 'Perera');
      await enter(tester, 'nic-field', '199812300001');
      await enter(tester, 'address1-field', '12 Galle Road');
      await enter(tester, 'postal-code-field', '00400');
      await enter(tester, 'mobile-field', '0771234567');
      await tapKey(tester, 'create-account-button');
      expect(find.text('An account with this email already exists. Sign in instead.'), findsOneWidget);
      expect(appBarTitle('Create account'), findsOneWidget);
    });

    testWidgets('a field can be filled with its microphone button', (tester) async {
      final env = await pumpApp(tester, '/register');
      env.speechIn.queue.add('john dot perera at gmail dot com');
      await scrollTo(tester, find.byKey(const Key('email-field')));
      await tester.tap(find.descendant(
          of: find.byKey(const Key('email-field')), matching: find.byTooltip('Speak email')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field('email-field')).controller!.text, 'john.perera@gmail.com');
      expect(env.speechOut.spoken.last, 'Email: john.perera@gmail.com.');
    });
  });

  test('the whole form can be filled by voice', () async {
    final env = TestEnv();
    final form = ProfileFormController(includeAccount: true);
    env.speechIn.queue.addAll([
      'nimal at example dot com',
      'secret 1234', // recognisers return spoken numbers as digits
      'nimal',
      'perera',
      'nine eight six two three four five six seven v',
      '12 galle road',
      'skip',
      'colombo',
      'zero zero four zero zero',
      'zero seven seven one two three four five six seven',
      'yes',
      'twenty two point five',
      'totally blind',
    ]);
    final filler = VoiceFormFiller(env.deps);
    await filler.run(form.voiceSteps(), intro: 'Start.', outro: 'Done.');
    expect(form.email.text, 'nimal@example.com');
    expect(form.password.text, 'secret1234');
    expect((form.firstName.text, form.lastName.text), ('Nimal', 'Perera'));
    expect(form.nic.text, '986234567V');
    expect(form.birthday, DateTime(1998, 5, 2));
    expect(form.gender?.wire, 'female');
    expect((form.addressLine1.text, form.addressLine2.text, form.addressLine3.text), ('12 galle road', '', 'Colombo'));
    expect(form.postalCode.text, '00400');
    expect(form.mobile.text, '0771234567');
    expect(form.whatsappSameAsMobile, isTrue);
    expect(form.bmi.text, '22.5');
    expect(form.eyesight?.wire, 'total');
    expect(form.validate(), isEmpty);
    expect(env.speechOut.spoken.last, 'Done.');
    expect(env.speechOut.spoken.any((s) => s.contains('secret')), isFalse, reason: 'passwords are never read back');
  });

  group('login', () {
    testWidgets('wrong password shows and speaks the reason', (tester) async {
      final env = TestEnv();
      env.backend.overrides['/api/v1/auth/login'] =
          (_) => errorResponse(401, 'invalid_credentials', 'The email or password is incorrect.');
      await pumpApp(tester, '/login', env: env);
      await enter(tester, 'login-email-field', 'a@b.com');
      await enter(tester, 'login-password-field', 'nope');
      await tapKey(tester, 'login-button');
      expect(find.text('The email or password is incorrect.'), findsOneWidget);
      expect(env.speechOut.spoken.last, 'The email or password is incorrect.');
    });

    testWidgets('continue as guest goes home and is remembered', (tester) async {
      final env = await pumpApp(tester, '/login');
      await tapKey(tester, 'guest-button');
      expect(appBarTitle('Home'), findsOneWidget);
      expect(env.deps.auth.welcomeDone, isTrue);
      expect(env.deps.auth.isSignedIn, isFalse);
    });

    testWidgets('a new Google account must complete its profile first', (tester) async {
      final env = TestEnv();
      env.backend.overrides['/api/v1/auth/google'] = (_) => sessionResponse(
          user: userJson(first: 'Asha', complete: false, hasPassword: false, google: true), isNew: true);
      Map<String, dynamic>? saved;
      env.backend.overrides['/api/v1/me'] = (r) {
        saved = jsonDecode(r.body) as Map<String, dynamic>;
        return http200(userJson(first: 'Asha', google: true, hasPassword: false));
      };
      await pumpApp(tester, '/login', env: env);
      await tapKey(tester, 'google-sign-in-button');
      expect(appBarTitle('Complete your profile'), findsOneWidget);

      // Other screens are not reachable until the profile is complete.
      await env.deps.dispatcher.handle('colour finder');
      await tester.pumpAndSettle();
      expect(appBarTitle('Complete your profile'), findsOneWidget);

      await enter(tester, 'last-name-field', 'Silva');
      await enter(tester, 'nic-field', '199812300001');
      await enter(tester, 'address1-field', '1 Lake Drive');
      await enter(tester, 'postal-code-field', '20000');
      await enter(tester, 'mobile-field', '0711111111');
      await tapKey(tester, 'save-profile-button');
      expect(saved!['first_name'], 'Asha');
      expect(appBarTitle('Home'), findsOneWidget);
    });
  });

  group('profile', () {
    testWidgets('guests see sign-in options', (tester) async {
      await pumpApp(tester, '/profile');
      expect(appBarTitle('My Profile'), findsOneWidget);
      expect(find.textContaining('using SmartSight as a guest'), findsOneWidget);
      expect(find.byKey(const Key('profile-login-button')), findsOneWidget);
    });

    testWidgets('signed-in users see their details and can sign out by voice', (tester) async {
      final env = TestEnv();
      env.backend.overrides['/api/v1/auth/login'] = (_) => sessionResponse();
      await env.deps.auth.login('nimal@example.com', 'secret123');
      await pumpApp(tester, '/profile', env: env);
      expect(find.text('Hello, Nimal'), findsOneWidget);
      expect(find.text('2 May 1998 (age 28)'), findsOneWidget);
      expect(find.text('Severe vision impairment'), findsOneWidget);

      await env.deps.dispatcher.handle('sign out');
      await tester.pumpAndSettle();
      expect(env.deps.auth.isSignedIn, isFalse);
      expect(appBarTitle('Home'), findsOneWidget);
      expect(env.speechOut.spoken.last, 'Signed out. You are now using SmartSight as a guest.');
    });
  });
}
