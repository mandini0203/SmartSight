import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api/api_client.dart';
import 'api/models.dart';

enum BackendState { unknown, online, degraded, offline }

/// Periodically checks that the backend is reachable so screens can warn the
/// user before they rely on it.
class BackendMonitor extends ChangeNotifier {
  BackendMonitor(this._api, {this.interval = const Duration(seconds: 20)});

  SmartSightApi Function() _api;
  final Duration interval;
  Timer? _timer;
  BackendState _state = BackendState.unknown;
  BackendStatus? _status;
  DateTime? _checkedAt;
  List<String>? _classes;

  BackendState get state => _state;
  BackendStatus? get status => _status;
  DateTime? get checkedAt => _checkedAt;

  /// Detector classes reported by the backend (null until first fetched).
  List<String>? get supportedClasses => _classes;

  void start() {
    _timer?.cancel();
    unawaited(check());
    _timer = Timer.periodic(interval, (_) => check());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void setApi(SmartSightApi Function() api) {
    _api = api;
    _classes = null;
    unawaited(check());
  }

  Future<BackendState> check() async {
    final api = _api();
    try {
      final s = await api.status();
      _status = s;
      _state = !s.detectorReady
          ? BackendState.offline
          : (s.status == 'ok' ? BackendState.online : BackendState.degraded);
      _classes ??= await api.supportedClasses();
    } catch (_) {
      _status = null;
      _state = BackendState.offline;
    }
    _checkedAt = DateTime.now();
    notifyListeners();
    return _state;
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
