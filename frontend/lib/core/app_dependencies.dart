import 'package:flutter/widgets.dart';

import 'actions/command_dispatcher.dart';
import 'api/api_client.dart';
import 'auth/account_item_remote.dart';
import 'auth/auth_controller.dart';
import 'auth/google_auth.dart';
import 'auth/token_store.dart';
import 'backend_monitor.dart';
import 'camera/frame_source.dart';
import 'config/settings_controller.dart';
import 'feedback/haptics.dart';
import 'feedback/speech_output.dart';
import 'guidance/guidance_controller.dart';
import 'permissions/permission_service.dart';
import 'storage/item_repository.dart';
import 'voice/command_interpreter.dart';
import 'voice/speech_input.dart';

/// Everything the UI needs, created once and provided through [AppScope].
/// Tests construct this with fakes.
class AppDependencies {
  AppDependencies({
    required this.settings,
    required SmartSightApi Function(String baseUrl) apiFactory,
    required this.speechInput,
    required SpeechOutput speechOutput,
    required this.haptics,
    required this.frames,
    required this.permissions,
    required this.items,
    required TokenStore tokenStore,
    required GoogleAuth googleAuth,
    DateTime Function()? clock,
  })  : _apiFactory = apiFactory,
        speechOutput = SwitchableSpeechOutput(speechOutput, enabled: () => settings.value.voiceEnabled),
        interpreter = CommandInterpreter() {
    _api = apiFactory(settings.value.backendUrl);
    _apiUrl = settings.value.backendUrl;
    backend = BackendMonitor(() => api);
    guidance = GuidanceController(
      frames: frames,
      speech: this.speechOutput,
      haptics: haptics,
      settings: () => settings.value,
      clock: clock,
    );
    settings.addListener(_onSettingsChanged);
    auth = AuthController(api: () => _api, store: tokenStore, google: googleAuth, clock: clock);
    auth.addListener(_onAuthChanged);
  }

  final SettingsController settings;
  final SmartSightApi Function(String baseUrl) _apiFactory;
  final SpeechInput speechInput;
  /// The app's voice; silent while voice is switched off.
  final SpeechOutput speechOutput;
  final Haptics haptics;
  final FrameSource frames;
  final PermissionService permissions;
  final ItemRepository items;
  final CommandInterpreter interpreter;
  late final BackendMonitor backend;
  late final GuidanceController guidance;
  late final AuthController auth;

  /// Set by the app once the router exists.
  late CommandDispatcher dispatcher;

  /// Shared voice-bar state, so "Heard: ..." stays visible after the spoken
  /// command navigates to another screen.
  final ValueNotifier<bool> listening = ValueNotifier(false);
  final ValueNotifier<String?> lastHeard = ValueNotifier(null);

  late SmartSightApi _api;
  late String _apiUrl;

  SmartSightApi get api => _api;

  void _onSettingsChanged() {
    final s = settings.value;
    if (s.backendUrl != _apiUrl) {
      _api.close();
      _apiUrl = s.backendUrl;
      _api = _apiFactory(s.backendUrl);
      backend.setApi(() => _api);
    }
    speechOutput.setRate(s.speechRate);
  }

  bool get voiceEnabled => settings.value.voiceEnabled;

  /// Switches the app's voice on or off (header button, Settings, or saying
  /// "voice on" / "voice off"). Each change is confirmed out loud while the
  /// voice can still be heard, and by vibration.
  Future<void> setVoiceEnabled(bool on) async {
    if (on == voiceEnabled) {
      await guidance.announce(on ? 'Voice is already on.' : 'Voice is already off.', remember: false);
      return;
    }
    await haptics.play(HapticCue.tap);
    if (on) {
      await settings.update(settings.value.copyWith(voiceEnabled: true));
      await guidance.announce('Voice on.', remember: false);
    } else {
      await speechOutput.speakAndWait('Voice off. Say voice on to hear me again.');
      await settings.update(settings.value.copyWith(voiceEnabled: false));
      await speechOutput.stop();
    }
  }

  /// Shows the signed-in user's items (synced with the server), or the guest
  /// list kept only on this phone.
  void _onAuthChanged() {
    final id = auth.user?.id;
    if (id != items.ownerId) items.switchAccount(id, remote: id == null ? null : AccountItemRemote(auth));
  }

  /// Production wiring.
  static AppDependencies device(SettingsController settings) {
    return AppDependencies(
      settings: settings,
      apiFactory: (url) => SmartSightApi(baseUrl: url),
      speechInput: DeviceSpeechInput(),
      speechOutput: DeviceSpeechOutput(
        modeProvider: () => settings.value.speechMode,
        screenReaderActive: () =>
            WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.accessibleNavigation,
      ),
      haptics: DeviceHaptics(enabled: () => settings.value.hapticsEnabled),
      frames: DeviceFrameSource(),
      permissions: DevicePermissionService(),
      items: FileItemRepository(),
      tokenStore: SecureTokenStore(),
      googleAuth: DeviceGoogleAuth(),
    );
  }
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.deps, required super.child});

  final AppDependencies deps;

  static AppDependencies of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found');
    return scope!.deps;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => oldWidget.deps != deps;
}
