enum ApiErrorKind { unreachable, timeout, busy, invalidRequest, server, unsupported, unauthorized, conflict, notFound }

/// An error from the SmartSight backend, with a message suitable for speech.
class ApiException implements Exception {
  const ApiException(this.kind, this.userMessage, {this.code, this.statusCode});

  final ApiErrorKind kind;
  final String userMessage;
  final String? code;
  final int? statusCode;

  bool get isOffline => kind == ApiErrorKind.unreachable || kind == ApiErrorKind.timeout;

  @override
  String toString() => 'ApiException($kind, $statusCode, $code): $userMessage';
}
