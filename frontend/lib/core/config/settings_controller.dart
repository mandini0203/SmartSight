import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/theme.dart';
import '../feedback/speech_output.dart';

/// Emulator loopback to the development machine. Override in Settings or with
/// `--dart-define=SMARTSIGHT_BACKEND_URL=http://192.168.1.20:8000`.
const String kDefaultBackendUrl =
    String.fromEnvironment('SMARTSIGHT_BACKEND_URL', defaultValue: 'http://10.0.2.2:8000');

class AppSettings {
  const AppSettings({
    this.backendUrl = kDefaultBackendUrl,
    this.speechRate = 0.5,
    this.speechMode = SpeechMode.automatic,
    this.hapticsEnabled = true,
    this.scanIntervalSeconds = 4,
    this.staleAfterSeconds = 8,
    this.cameraFovDegrees = 66,
    this.verboseGuidance = false,
    this.voiceEnabled = true,
    this.themeMode = ThemeMode.system,
    this.colourPalette = ColourPalette.blueOrange,
    this.displaySize = DisplaySize.large,
  });

  final String backendUrl;
  final double speechRate;
  final SpeechMode speechMode;
  final bool hapticsEnabled;

  /// Seconds between automatic captures while continuous guidance runs.
  final int scanIntervalSeconds;

  /// Results older than this are not spoken as current observations.
  final int staleAfterSeconds;
  final double cameraFovDegrees;
  final bool verboseGuidance;

  /// The app speaks its guidance and replies. Voice commands keep working
  /// while it is off, so "voice on" can switch it back.
  final bool voiceEnabled;

  /// Light, dark, or follow the phone.
  final ThemeMode themeMode;

  /// Whole-app colours, including colour-blind-safe and high-contrast sets.
  final ColourPalette colourPalette;

  /// Size of text, buttons and cards across the app.
  final DisplaySize displaySize;

  AppSettings copyWith({
    String? backendUrl,
    double? speechRate,
    SpeechMode? speechMode,
    bool? hapticsEnabled,
    int? scanIntervalSeconds,
    int? staleAfterSeconds,
    double? cameraFovDegrees,
    bool? verboseGuidance,
    bool? voiceEnabled,
    ThemeMode? themeMode,
    ColourPalette? colourPalette,
    DisplaySize? displaySize,
  }) =>
      AppSettings(
        backendUrl: backendUrl ?? this.backendUrl,
        speechRate: speechRate ?? this.speechRate,
        speechMode: speechMode ?? this.speechMode,
        hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
        scanIntervalSeconds: scanIntervalSeconds ?? this.scanIntervalSeconds,
        staleAfterSeconds: staleAfterSeconds ?? this.staleAfterSeconds,
        cameraFovDegrees: cameraFovDegrees ?? this.cameraFovDegrees,
        verboseGuidance: verboseGuidance ?? this.verboseGuidance,
        voiceEnabled: voiceEnabled ?? this.voiceEnabled,
        themeMode: themeMode ?? this.themeMode,
        colourPalette: colourPalette ?? this.colourPalette,
        displaySize: displaySize ?? this.displaySize,
      );
}

/// Valid backend URL: http(s) with a host.
bool isValidBackendUrl(String url) {
  final u = Uri.tryParse(url.trim());
  return u != null && (u.scheme == 'http' || u.scheme == 'https') && u.host.isNotEmpty;
}

class SettingsController extends ChangeNotifier {
  SettingsController([this._settings = const AppSettings()]);

  AppSettings _settings;
  SharedPreferences? _prefs;

  AppSettings get value => _settings;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _prefs = p;
    final d = const AppSettings();
    _settings = AppSettings(
      backendUrl: p.getString('backendUrl') ?? d.backendUrl,
      speechRate: p.getDouble('speechRate') ?? d.speechRate,
      speechMode: SpeechMode.values.asNameMap()[p.getString('speechMode')] ?? d.speechMode,
      hapticsEnabled: p.getBool('hapticsEnabled') ?? d.hapticsEnabled,
      scanIntervalSeconds: p.getInt('scanIntervalSeconds') ?? d.scanIntervalSeconds,
      staleAfterSeconds: p.getInt('staleAfterSeconds') ?? d.staleAfterSeconds,
      cameraFovDegrees: p.getDouble('cameraFovDegrees') ?? d.cameraFovDegrees,
      verboseGuidance: p.getBool('verboseGuidance') ?? d.verboseGuidance,
      voiceEnabled: p.getBool('voiceEnabled') ?? d.voiceEnabled,
      themeMode: ThemeMode.values.asNameMap()[p.getString('themeMode')] ?? d.themeMode,
      colourPalette: ColourPalette.values.asNameMap()[p.getString('colourPalette')] ?? d.colourPalette,
      displaySize: DisplaySize.values.asNameMap()[p.getString('displaySize')] ?? d.displaySize,
    );
    notifyListeners();
  }

  Future<void> update(AppSettings s) async {
    _settings = s;
    notifyListeners();
    final p = _prefs;
    if (p == null) return;
    await p.setString('backendUrl', s.backendUrl);
    await p.setDouble('speechRate', s.speechRate);
    await p.setString('speechMode', s.speechMode.name);
    await p.setBool('hapticsEnabled', s.hapticsEnabled);
    await p.setInt('scanIntervalSeconds', s.scanIntervalSeconds);
    await p.setInt('staleAfterSeconds', s.staleAfterSeconds);
    await p.setDouble('cameraFovDegrees', s.cameraFovDegrees);
    await p.setBool('verboseGuidance', s.verboseGuidance);
    await p.setBool('voiceEnabled', s.voiceEnabled);
    await p.setString('themeMode', s.themeMode.name);
    await p.setString('colourPalette', s.colourPalette.name);
    await p.setString('displaySize', s.displaySize.name);
  }
}
