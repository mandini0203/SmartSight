import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/actions/command_dispatcher.dart';
import '../core/app_dependencies.dart';
import 'router.dart';
import 'theme.dart';

class SmartSightApp extends StatefulWidget {
  const SmartSightApp({super.key, required this.deps, this.initialLocation = '/'});

  final AppDependencies deps;
  final String initialLocation;

  @override
  State<SmartSightApp> createState() => _SmartSightAppState();
}

class _SmartSightAppState extends State<SmartSightApp> with WidgetsBindingObserver {
  late final GoRouter _router = buildRouter(auth: widget.deps.auth, initialLocation: widget.initialLocation);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.deps.dispatcher = CommandDispatcher(
      deps: widget.deps,
      go: _router.go,
      canPop: _router.canPop,
      pop: _router.pop,
    );
    widget.deps.backend.start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final d = widget.deps;
    switch (state) {
      case AppLifecycleState.paused || AppLifecycleState.hidden:
        // Never keep the camera or guidance running in the background.
        d.guidance.stop(silent: true);
        d.frames.suspend();
        d.backend.stop();
      case AppLifecycleState.resumed:
        d.frames.resumeIfLeased();
        d.backend.start();
      default:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.deps.backend.stop();
    widget.deps.guidance.stop(silent: true);
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      deps: widget.deps,
      child: ListenableBuilder(
        listenable: widget.deps.settings,
        builder: (context, _) {
          final s = widget.deps.settings.value;
          return MaterialApp.router(
            title: 'SmartSight',
            debugShowCheckedModeBanner: false,
            theme: buildTheme(Brightness.light, palette: s.colourPalette, size: s.displaySize),
            darkTheme: buildTheme(Brightness.dark, palette: s.colourPalette, size: s.displaySize),
            themeMode: s.themeMode,
            routerConfig: _router,
            // Screen size setting: scales the phone's own text size.
            builder: (context, child) {
              final mq = MediaQuery.of(context);
              return MediaQuery(
                data: mq.copyWith(textScaler: ScaledTextScaler(mq.textScaler, s.displaySize.textFactor)),
                child: child!,
              );
            },
          );
        },
      ),
    );
  }
}
