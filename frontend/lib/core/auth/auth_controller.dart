import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../api/api_exception.dart';
import 'google_auth.dart';
import 'profile.dart';
import 'token_store.dart';

/// The signed-in account, or none (guest).
///
/// Holds a short-lived access token in memory and the rotating refresh token
/// in [TokenStore]. A cached copy of the profile keeps the user signed in
/// while the server is unreachable; the session ends only when the server
/// rejects the refresh token.
class AuthController extends ChangeNotifier {
  AuthController({
    required SmartSightApi Function() api,
    required this.store,
    required this.google,
    DateTime Function()? clock,
  })  : _apiOf = api,
        _now = clock ?? DateTime.now;

  static const _kRefresh = 'refresh_token';
  static const _kUser = 'user_profile';
  static const _kWelcome = 'welcome_done';

  final SmartSightApi Function() _apiOf;
  final TokenStore store;
  final GoogleAuth google;
  final DateTime Function() _now;

  UserProfile? _user;
  String? _refresh;
  String? _access;
  DateTime? _accessExpiry;
  bool _welcomeDone = false;
  Future<void>? _refreshing;

  UserProfile? get user => _user;
  bool get isSignedIn => _user != null;

  /// A new Google account must fill in its details before using the app.
  bool get needsProfile => _user != null && !_user!.profileComplete;

  /// The user has signed in or chosen to continue as a guest at least once.
  bool get welcomeDone => _welcomeDone;

  Future<void> restore() async {
    _welcomeDone = await store.read(_kWelcome) == '1';
    final refresh = await store.read(_kRefresh);
    final cached = await store.read(_kUser);
    if (refresh != null && cached != null) {
      try {
        _user = UserProfile.fromJson(jsonDecode(cached) as Map<String, dynamic>);
        _refresh = refresh;
      } catch (_) {
        await _clearLocal(notify: false);
      }
    }
    notifyListeners();
    // Check the session and pick up profile changes made on another phone,
    // without delaying start-up.
    if (isSignedIn) unawaited(reloadProfile().catchError((_) {}));
  }

  Future<void> markWelcomeDone() async {
    if (_welcomeDone) return;
    _welcomeDone = true;
    await store.write(_kWelcome, '1');
    notifyListeners();
  }

  // ---------------------------------------------------------------- sign in
  Future<AuthSession> login(String email, String password) async =>
      _adopt(await _apiOf().login(email.trim().toLowerCase(), password));

  Future<AuthSession> register({required String email, required String password, required ProfileDraft profile}) async =>
      _adopt(await _apiOf().register(email: email.trim().toLowerCase(), password: password, profile: profile));

  /// Null when the user closed Google's account chooser.
  Future<AuthSession?> signInWithGoogle() async {
    final idToken = await google.signIn();
    if (idToken == null) return null;
    try {
      return await _adopt(await _apiOf().googleLogin(idToken));
    } on ApiException {
      await google.signOut();
      rethrow;
    }
  }

  Future<void> signOut() async {
    final refresh = _refresh;
    await _clearLocal();
    await google.signOut();
    if (refresh != null) {
      try {
        await _apiOf().logout(refresh);
      } on ApiException {
        // Offline: the refresh token simply expires on the server.
      }
    }
  }

  // ---------------------------------------------------------------- profile
  Future<UserProfile> updateProfile(ProfileDraft draft) async {
    final u = await authed((api, token) => api.updateMe(token, draft));
    await _setUser(u);
    return u;
  }

  Future<void> reloadProfile() async {
    final u = await authed((api, token) => api.me(token));
    await _setUser(u);
  }

  Future<void> deleteAccount() async {
    await authed((api, token) => api.deleteMe(token));
    await _clearLocal();
    await google.signOut();
  }

  // ----------------------------------------------------------------- tokens
  /// Runs a call that needs the access token. If the server rejects the
  /// token, refreshes once and retries.
  Future<T> authed<T>(Future<T> Function(SmartSightApi api, String accessToken) call) async {
    try {
      return await call(_apiOf(), await accessToken());
    } on ApiException catch (e) {
      if (e.kind != ApiErrorKind.unauthorized || !isSignedIn) rethrow;
      return call(_apiOf(), await accessToken(forceRefresh: true));
    }
  }

  Future<String> accessToken({bool forceRefresh = false}) async {
    if (!isSignedIn) throw const ApiException(ApiErrorKind.unauthorized, 'Please sign in first.');
    final expiry = _accessExpiry;
    if (!forceRefresh && _access != null && expiry != null && _now().isBefore(expiry)) return _access!;
    // One refresh at a time: refresh tokens rotate, and the server ends every
    // session if an already-used one is presented again.
    await (_refreshing ??= _refreshTokens().whenComplete(() => _refreshing = null));
    return _access!;
  }

  Future<void> _refreshTokens() async {
    final refresh = _refresh;
    if (refresh == null) throw const ApiException(ApiErrorKind.unauthorized, 'Please sign in first.');
    try {
      await _adopt(await _apiOf().refreshSession(refresh));
    } on ApiException catch (e) {
      if (e.kind == ApiErrorKind.unauthorized) await _clearLocal();
      rethrow;
    }
  }

  Future<AuthSession> _adopt(AuthSession s) async {
    _access = s.accessToken;
    // Renew a little early so a request never arrives with an expired token.
    _accessExpiry = _now().add(s.expiresIn - const Duration(seconds: 30));
    _refresh = s.refreshToken;
    _user = s.user;
    _welcomeDone = true;
    await store.write(_kRefresh, s.refreshToken);
    await store.write(_kUser, jsonEncode(s.user.toJson()));
    await store.write(_kWelcome, '1');
    notifyListeners();
    return s;
  }

  Future<void> _setUser(UserProfile u) async {
    _user = u;
    await store.write(_kUser, jsonEncode(u.toJson()));
    notifyListeners();
  }

  Future<void> _clearLocal({bool notify = true}) async {
    _user = null;
    _refresh = null;
    _access = null;
    _accessExpiry = null;
    await store.delete(_kRefresh);
    await store.delete(_kUser);
    if (notify) notifyListeners();
  }
}
