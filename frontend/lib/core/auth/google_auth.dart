import 'package:google_sign_in/google_sign_in.dart';

/// OAuth "Web application" client ID from Google Cloud. Google issues the ID
/// token for this audience, and the backend accepts only this audience
/// (SMARTSIGHT_GOOGLE_CLIENT_IDS). Build with
/// `--dart-define=SMARTSIGHT_GOOGLE_SERVER_CLIENT_ID=<id>.apps.googleusercontent.com`.
const String kGoogleServerClientId = String.fromEnvironment('SMARTSIGHT_GOOGLE_SERVER_CLIENT_ID');

class GoogleAuthException implements Exception {
  const GoogleAuthException(this.userMessage);
  final String userMessage;
  @override
  String toString() => 'GoogleAuthException: $userMessage';
}

/// Shows Google's account chooser and returns an ID token for the backend.
abstract class GoogleAuth {
  bool get isConfigured;

  /// The ID token, or null if the user closed the account chooser.
  /// Throws [GoogleAuthException] for anything else.
  Future<String?> signIn();
  Future<void> signOut();
}

class DeviceGoogleAuth implements GoogleAuth {
  DeviceGoogleAuth({this.serverClientId = kGoogleServerClientId});

  final String serverClientId;
  Future<void>? _init;

  @override
  bool get isConfigured => serverClientId.isNotEmpty;

  Future<void> _ensureInit() => _init ??= GoogleSignIn.instance.initialize(serverClientId: serverClientId);

  @override
  Future<String?> signIn() async {
    if (!isConfigured) {
      throw const GoogleAuthException('Google sign-in is not set up in this version of the app.');
    }
    try {
      await _ensureInit();
      // Always show the chooser so the user can pick a different account.
      await GoogleSignIn.instance.signOut();
      final account = await GoogleSignIn.instance.authenticate();
      final token = account.authentication.idToken;
      if (token == null) throw const GoogleAuthException('Google did not return a sign-in token.');
      return token;
    } on GoogleSignInException catch (e) {
      switch (e.code) {
        case GoogleSignInExceptionCode.canceled:
          return null;
        case GoogleSignInExceptionCode.clientConfigurationError ||
              GoogleSignInExceptionCode.providerConfigurationError:
          throw const GoogleAuthException(
              'Google sign-in is not configured correctly for this app. Please use email and password.');
        default:
          throw GoogleAuthException('Google sign-in failed. ${e.description ?? ''}'.trim());
      }
    }
  }

  @override
  Future<void> signOut() async {
    if (!isConfigured) return;
    try {
      await _ensureInit();
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
  }
}
