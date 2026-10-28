import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/app.dart';
import 'core/app_dependencies.dart';
import 'core/config/settings_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final settings = SettingsController();
  await settings.load();
  final deps = AppDependencies.device(settings);
  // Restoring a session switches the item list to that account.
  await deps.auth.restore();
  if (!deps.auth.isSignedIn) await deps.items.load();
  await deps.speechOutput.setRate(settings.value.speechRate);

  // First launch: offer sign-in, registration or guest use.
  final start = deps.auth.isSignedIn || deps.auth.welcomeDone ? '/' : '/login';
  runApp(SmartSightApp(deps: deps, initialLocation: start));
}
