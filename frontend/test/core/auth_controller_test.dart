import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:smartsight/core/api/api_exception.dart';

import '../helpers/accounts.dart';
import '../helpers/fakes.dart';

void main() {
  test('login stores the session and the profile', () async {
    final env = TestEnv();
    env.backend.overrides['/api/v1/auth/login'] = (r) {
      expect(jsonDecode(r.body), {'email': 'nimal@example.com', 'password': 'secret123'});
      return sessionResponse();
    };
    await env.deps.auth.login('  Nimal@Example.com ', 'secret123');
    expect(env.deps.auth.isSignedIn, isTrue);
    expect(env.deps.auth.user!.firstName, 'Nimal');
    expect(env.deps.auth.welcomeDone, isTrue);
    expect(env.tokens.values['refresh_token'], startsWith('refresh-token'));
    expect(env.tokens.values['user_profile'], contains('Nimal'));
  });

  test('wrong password surfaces the server message', () async {
    final env = TestEnv();
    env.backend.overrides['/api/v1/auth/login'] =
        (_) => errorResponse(401, 'invalid_credentials', 'The email or password is incorrect.');
    await expectLater(
      env.deps.auth.login('a@b.com', 'x'),
      throwsA(isA<ApiException>()
          .having((e) => e.kind, 'kind', ApiErrorKind.unauthorized)
          .having((e) => e.userMessage, 'message', 'The email or password is incorrect.')),
    );
    expect(env.deps.auth.isSignedIn, isFalse);
  });

  test('an expired access token is refreshed once, even for concurrent calls', () async {
    var now = DateTime(2026, 10, 23, 12);
    final env = TestEnv(clock: () => now);
    env.backend.overrides['/api/v1/auth/login'] = (_) => sessionResponse(expiresIn: 60);
    var refreshes = 0;
    env.backend.overrides['/api/v1/auth/refresh'] = (r) {
      refreshes++;
      return sessionResponse(expiresIn: 60);
    };
    await env.deps.auth.login('a@b.com', 'secret123');
    final first = await env.deps.auth.accessToken();
    expect(refreshes, 0);

    now = now.add(const Duration(seconds: 45)); // inside the 30-second safety margin
    final tokens = await Future.wait([env.deps.auth.accessToken(), env.deps.auth.accessToken()]);
    expect(refreshes, 1);
    expect(tokens[0], tokens[1]);
    expect(tokens[0], isNot(first));
  });

  test('a rejected refresh token signs the user out', () async {
    var now = DateTime(2026, 10, 23, 12);
    final env = TestEnv(clock: () => now);
    env.backend.overrides['/api/v1/auth/login'] = (_) => sessionResponse(expiresIn: 60);
    env.backend.overrides['/api/v1/auth/refresh'] =
        (_) => errorResponse(401, 'invalid_refresh_token', 'Your session has ended. Please sign in again.');
    await env.deps.auth.login('a@b.com', 'secret123');
    now = now.add(const Duration(minutes: 5));
    await expectLater(env.deps.auth.accessToken(), throwsA(isA<ApiException>()));
    expect(env.deps.auth.isSignedIn, isFalse);
    expect(env.tokens.values.containsKey('refresh_token'), isFalse);
  });

  test('restoring while offline keeps the cached profile', () async {
    final env = TestEnv();
    env.backend.overrides['/api/v1/auth/login'] = (_) => sessionResponse();
    await env.deps.auth.login('a@b.com', 'secret123');

    final restarted = TestEnv();
    restarted.tokens.values.addAll(env.tokens.values);
    restarted.backend.offline = true;
    await restarted.deps.auth.restore();
    await Future<void>.delayed(Duration.zero);
    expect(restarted.deps.auth.isSignedIn, isTrue);
    expect(restarted.deps.auth.user!.email, 'nimal@example.com');
  });

  test('sign out revokes the session and signs out of Google', () async {
    final env = TestEnv();
    env.backend.overrides['/api/v1/auth/login'] = (_) => sessionResponse();
    String? revoked;
    env.backend.overrides['/api/v1/auth/logout'] = (r) {
      revoked = (jsonDecode(r.body) as Map)['refresh_token'] as String;
      return http.Response('', 204);
    };
    await env.deps.auth.login('a@b.com', 'secret123');
    final refresh = env.tokens.values['refresh_token'];
    await env.deps.auth.signOut();
    expect(revoked, refresh);
    expect(env.deps.auth.isSignedIn, isFalse);
    expect(env.google.signOuts, 1);
    expect(env.deps.auth.welcomeDone, isTrue, reason: 'signing out should not show the first-run screen again');
  });

  test('Google: cancel returns null; the ID token is sent to the server', () async {
    final env = TestEnv();
    env.google.idToken = null;
    expect(await env.deps.auth.signInWithGoogle(), isNull);

    env.google.idToken = 'id-token-from-google';
    env.backend.overrides['/api/v1/auth/google'] = (r) {
      expect(jsonDecode(r.body), {'id_token': 'id-token-from-google'});
      return sessionResponse(user: userJson(complete: false, hasPassword: false, google: true), isNew: true);
    };
    final s = await env.deps.auth.signInWithGoogle();
    expect(s!.isNewUser, isTrue);
    expect(env.deps.auth.needsProfile, isTrue);
  });

  test('authenticated calls send the bearer token', () async {
    final env = TestEnv();
    env.backend.overrides['/api/v1/auth/login'] = (_) => sessionResponse();
    env.backend.overrides['/api/v1/me'] = (r) {
      expect(r.headers['authorization'], startsWith('Bearer access-'));
      return http.Response(jsonEncode(userJson(first: 'Kamal')), 200);
    };
    await env.deps.auth.login('a@b.com', 'secret123');
    await env.deps.auth.reloadProfile();
    expect(env.deps.auth.user!.firstName, 'Kamal');
  });
}
