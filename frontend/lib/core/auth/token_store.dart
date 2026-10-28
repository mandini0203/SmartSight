import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Small key-value store for the session: the refresh token, a cached copy
/// of the profile (so the app works offline after sign-in) and flags.
abstract class TokenStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Android Keystore-backed encrypted storage.
class SecureTokenStore implements TokenStore {
  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      // Unreadable after a Keystore reset or backup restore: start signed out.
      await _storage.deleteAll();
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}
