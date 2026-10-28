import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../auth/profile.dart';
import 'api_exception.dart';
import 'models.dart';

/// HTTP client for the SmartSight FastAPI backend.
///
/// Every call has a timeout and converts transport and server failures into
/// [ApiException]s with a short, speakable message.
class SmartSightApi {
  SmartSightApi({
    required String baseUrl,
    http.Client? client,
    this.requestTimeout = const Duration(seconds: 25),
    this.healthTimeout = const Duration(seconds: 4),
  })  : baseUri = Uri.parse(baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl),
        _client = client ?? http.Client();

  final Uri baseUri;
  final http.Client _client;
  final Duration requestTimeout;
  final Duration healthTimeout;

  Uri _u(String path) => baseUri.replace(path: '${baseUri.path}$path');

  void close() => _client.close();

  // ---------------------------------------------------------------- health
  Future<bool> isHealthy() async {
    try {
      final r = await _client.get(_u('/health')).timeout(healthTimeout);
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<BackendStatus> status() async =>
      BackendStatus.fromJson(await _json(() => _client.get(_u('/api/v1/status')), healthTimeout));

  Future<List<String>> supportedClasses() async {
    final j = await _json(() => _client.get(_u('/api/v1/detection/classes')), healthTimeout);
    return (j['classes'] as List).cast<String>();
  }

  // ------------------------------------------------------------- vision
  Future<DetectionResult> detect(Uint8List jpeg, {String? frameId, double? fovDegrees}) async {
    final j = await _multipart('/api/v1/detection', {'image': jpeg}, {
      'frame_id': ?frameId,
      if (fovDegrees != null) 'camera_fov_degrees': '$fovDegrees',
    });
    return DetectionResult.fromJson(j);
  }

  /// Detection plus rule-based context in one round trip.
  Future<ScanResult> scan(
    Uint8List jpeg, {
    required String task,
    String? targetLabel,
    String? frameId,
    double? fovDegrees,
  }) async {
    final j = await _multipart('/api/v1/scan', {'image': jpeg}, {
      'task': task,
      'target_label': ?targetLabel,
      'frame_id': ?frameId,
      if (fovDegrees != null) 'camera_fov_degrees': '$fovDegrees',
    });
    return ScanResult.fromJson(j);
  }

  Future<SignsResult> detectSigns(Uint8List jpeg, {String? frameId, double? fovDegrees}) async {
    final j = await _multipart('/api/v1/signs/detect', {'image': jpeg}, {
      'frame_id': ?frameId,
      if (fovDegrees != null) 'camera_fov_degrees': '$fovDegrees',
    });
    return SignsResult.fromJson(j);
  }

  /// Colour of a region. [pointX]/[pointY] are 0..1 fractions of the image.
  Future<ColourResult> identifyColour(Uint8List jpeg, {double? pointX, double? pointY, String? frameId}) async {
    final j = await _multipart('/api/v1/colour/identify', {'image': jpeg}, {
      'frame_id': ?frameId,
      if (pointX != null && pointY != null) ...{
        'point_x': '$pointX',
        'point_y': '$pointY',
        'normalised': 'true',
      },
    });
    return ColourResult.fromJson(j);
  }

  Future<ItemMatchResult> matchItem(
    Uint8List sceneJpeg, {
    required List<Uint8List> references,
    required String itemLabel,
    String? itemName,
    String? frameId,
  }) async {
    final j = await _multipart(
      '/api/v1/items/match',
      {'image': sceneJpeg},
      {'item_label': itemLabel, 'item_name': ?itemName, 'frame_id': ?frameId},
      references: references,
    );
    return ItemMatchResult.fromJson(j);
  }

  Future<ReferenceCheck> checkReference(Uint8List jpeg, {required String itemLabel}) async {
    final j = await _multipart('/api/v1/items/check-reference', {'image': jpeg}, {'item_label': itemLabel});
    return ReferenceCheck.fromJson(j);
  }

  // -------------------------------------------------------------- intent
  Future<IntentResult> resolveIntent(String text) async {
    final j = await _json(
      () => _client.post(
        _u('/api/v1/intent/resolve'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'text': text}),
      ),
      requestTimeout,
    );
    return IntentResult.fromJson(j);
  }

  // ------------------------------------------------------------ accounts
  Future<AuthSession> register({required String email, required String password, required ProfileDraft profile}) async =>
      AuthSession.fromJson(await _sendJson('POST', '/api/v1/auth/register',
          {'email': email, 'password': password, ...profile.toJson()}));

  Future<AuthSession> login(String email, String password) async =>
      AuthSession.fromJson(await _sendJson('POST', '/api/v1/auth/login', {'email': email, 'password': password}));

  Future<AuthSession> googleLogin(String idToken) async =>
      AuthSession.fromJson(await _sendJson('POST', '/api/v1/auth/google', {'id_token': idToken}));

  Future<AuthSession> refreshSession(String refreshToken) async =>
      AuthSession.fromJson(await _sendJson('POST', '/api/v1/auth/refresh', {'refresh_token': refreshToken}));

  Future<void> logout(String refreshToken) => _sendJson('POST', '/api/v1/auth/logout', {'refresh_token': refreshToken});

  Future<UserProfile> me(String accessToken) async =>
      UserProfile.fromJson(await _sendJson('GET', '/api/v1/me', null, accessToken: accessToken));

  Future<UserProfile> updateMe(String accessToken, ProfileDraft profile) async =>
      UserProfile.fromJson(await _sendJson('PUT', '/api/v1/me', profile.toJson(), accessToken: accessToken));

  Future<void> deleteMe(String accessToken) => _sendJson('DELETE', '/api/v1/me', null, accessToken: accessToken);

  Future<List<RemoteItem>> myItems(String accessToken) async {
    final j = await _request(() => _client.get(_u('/api/v1/me/items'), headers: _bearer(accessToken)), requestTimeout);
    return [for (final e in j as List) RemoteItem.fromJson(e as Map<String, dynamic>)];
  }

  Future<void> uploadMyItem(
    String accessToken, {
    required String id,
    required String name,
    required String label,
    required List<Uint8List> photos,
  }) =>
      _multipart('/api/v1/me/items', const {}, {'id': id, 'name': name, 'label': label},
          references: photos, filesField: 'photos', headers: _bearer(accessToken));

  Future<void> deleteMyItem(String accessToken, String id) =>
      _sendJson('DELETE', '/api/v1/me/items/${Uri.encodeComponent(id)}', null, accessToken: accessToken);

  Future<Uint8List> myItemPhoto(String accessToken, String id, int index) async {
    final r = await _transport(
        () => _client.get(_u('/api/v1/me/items/${Uri.encodeComponent(id)}/photos/$index'), headers: _bearer(accessToken)),
        requestTimeout);
    if (r.statusCode == 200) return r.bodyBytes;
    _throwFor(r, null);
  }

  // ------------------------------------------------------------ plumbing
  Map<String, String> _bearer(String token) => {'authorization': 'Bearer $token'};

  Future<Map<String, dynamic>> _sendJson(String method, String path, Map<String, dynamic>? body,
      {String? accessToken}) async {
    final j = await _request(() {
      final req = http.Request(method, _u(path));
      if (accessToken != null) req.headers.addAll(_bearer(accessToken));
      if (body != null) {
        req.headers['content-type'] = 'application/json';
        req.body = jsonEncode(body);
      }
      return _client.send(req).then(http.Response.fromStream);
    }, requestTimeout);
    return j as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _multipart(
    String path,
    Map<String, Uint8List> images,
    Map<String, String> fields, {
    List<Uint8List> references = const [],
    String filesField = 'references',
    Map<String, String> headers = const {},
  }) {
    return _json(() async {
      final req = http.MultipartRequest('POST', _u(path))
        ..fields.addAll(fields)
        ..headers.addAll(headers);
      images.forEach((name, bytes) => req.files.add(http.MultipartFile.fromBytes(name, bytes, filename: '$name.jpg')));
      for (var i = 0; i < references.length; i++) {
        req.files.add(http.MultipartFile.fromBytes(filesField, references[i], filename: '${filesField}_$i.jpg'));
      }
      return http.Response.fromStream(await _client.send(req));
    }, requestTimeout);
  }

  Future<Map<String, dynamic>> _json(Future<http.Response> Function() send, Duration timeout) async =>
      await _request(send, timeout) as Map<String, dynamic>;

  /// Sends, decodes the JSON body (a map, a list, or `{}` for 204) and maps
  /// failures to [ApiException].
  Future<Object> _request(Future<http.Response> Function() send, Duration timeout) async {
    final r = await _transport(send, timeout);
    if (r.statusCode == 204) return const <String, dynamic>{};
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(r.bodyBytes));
    } catch (_) {
      decoded = null;
    }
    if (r.statusCode >= 200 && r.statusCode < 300 && (decoded is Map<String, dynamic> || decoded is List)) {
      return decoded!;
    }
    _throwFor(r, decoded is Map<String, dynamic> ? decoded : null);
  }

  Future<http.Response> _transport(Future<http.Response> Function() send, Duration timeout) async {
    try {
      return await send().timeout(timeout);
    } on TimeoutException {
      throw const ApiException(ApiErrorKind.timeout, 'The server took too long to respond. Please try again.');
    } on SocketException {
      throw const ApiException(
          ApiErrorKind.unreachable, 'Cannot reach the SmartSight server. Check the connection and server address.');
    } on http.ClientException {
      throw const ApiException(
          ApiErrorKind.unreachable, 'Cannot reach the SmartSight server. Check the connection and server address.');
    } on HandshakeException {
      throw const ApiException(ApiErrorKind.unreachable, 'A secure connection to the server could not be made.');
    }
  }

  Never _throwFor(http.Response r, Map<String, dynamic>? body) {
    final err = body?['error'] as Map<String, dynamic>?;
    final code = err?['code'] as String?;
    final message = err?['message'] as String?;
    switch (r.statusCode) {
      case 401:
        throw ApiException(ApiErrorKind.unauthorized, message ?? 'Please sign in again.',
            code: code, statusCode: r.statusCode);
      case 404:
        throw ApiException(ApiErrorKind.notFound, message ?? 'Not found.', code: code, statusCode: r.statusCode);
      case 409:
        throw ApiException(ApiErrorKind.conflict, message ?? 'That conflicts with existing data.',
            code: code, statusCode: r.statusCode);
      case 429:
        throw ApiException(ApiErrorKind.busy, message ?? 'Too many attempts. Please wait and try again.',
            code: code, statusCode: r.statusCode);
      case 413:
        throw ApiException(ApiErrorKind.invalidRequest, 'The photo is too large to send.',
            code: code, statusCode: r.statusCode);
      case 415 || 422:
        throw ApiException(
            code == 'unsupported_class' ? ApiErrorKind.unsupported : ApiErrorKind.invalidRequest,
            message ?? 'The request was not accepted.',
            code: code,
            statusCode: r.statusCode);
      case 503:
        throw ApiException(ApiErrorKind.busy, message ?? 'The server is not ready. Please try again shortly.',
            code: code, statusCode: r.statusCode);
      case 504:
        throw ApiException(ApiErrorKind.timeout, 'Image analysis took too long. Please try again.',
            code: code, statusCode: r.statusCode);
      default:
        throw ApiException(ApiErrorKind.server, 'The server had a problem (${r.statusCode}).',
            code: code, statusCode: r.statusCode);
    }
  }
}
