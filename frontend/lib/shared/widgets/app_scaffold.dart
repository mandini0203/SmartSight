import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/app_dependencies.dart';
import 'backend_banner.dart';
import 'voice_bar.dart';

/// Common page layout: header (logo, voice switch, page title), backend
/// status banner, scrollable body and the voice bar.
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    required this.title,
    required this.children,
    this.actions,
    this.showBackendBanner = true,
  });

  final String title;
  final List<Widget> children;
  final List<Widget>? actions;
  final bool showBackendBanner;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = DisplaySize.of(context);
    final titleStyle =
        Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: scheme.onSurface);
    // The title band grows with the system text size.
    final titleHeight = MediaQuery.textScalerOf(context).scale(titleStyle?.fontSize ?? 28) * 1.35 + size.gap * 1.5;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        toolbarHeight: size.headerHeight,
        title: const AppLogo(),
        actions: [...?actions, const VoiceToggleButton(), const SizedBox(width: 8)],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(titleHeight),
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(16, size.gap * 0.7, 16, size.gap * 0.8),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Semantics(
              header: true,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: titleStyle,
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            if (showBackendBanner) const BackendBanner(),
            ...children,
          ],
        ),
      ),
      bottomNavigationBar: const VoiceBar(),
    );
  }
}

/// The SmartSight name as the app logo. Tapping it goes to the home screen.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final badge = DisplaySize.of(context).iconSize * 1.45;
    final onBar = scheme.onPrimary;
    final style = TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 0.3, color: onBar);
    return Semantics(
      button: true,
      label: 'SmartSight logo, go to home',
      excludeSemantics: true,
      child: InkWell(
        key: const Key('app-logo'),
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.go('/'),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: badge,
                height: badge,
                decoration: BoxDecoration(color: onBar, borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.visibility, color: scheme.primary, size: badge * 0.65),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  // RichText rather than Text so the wordmark is not
                  // mistaken for a page title.
                  child: RichText(
                    textScaler: MediaQuery.textScalerOf(context),
                    text: TextSpan(style: style, children: [
                      const TextSpan(text: 'Smart'),
                      TextSpan(text: 'Sight', style: TextStyle(fontWeight: FontWeight.w400, color: onBar)),
                    ]),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Header switch for the app's voice. Also controlled by saying
/// "voice on" or "voice off".
class VoiceToggleButton extends StatelessWidget {
  const VoiceToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    final deps = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: deps.settings,
      builder: (context, _) {
        final on = deps.voiceEnabled;
        return Semantics(
          toggled: on,
          label: 'Voice',
          hint: on ? 'Double tap to switch the voice off' : 'Double tap to switch the voice on',
          excludeSemantics: true,
          child: Tooltip(
            message: on ? 'Voice is on' : 'Voice is off',
            child: Material(
              key: const Key('voice-toggle'),
              color: on ? scheme.onPrimary : Colors.transparent,
              shape: StadiumBorder(side: BorderSide(color: scheme.onPrimary, width: 2)),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: () => deps.setVoiceEnabled(!on),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(on ? Icons.volume_up : Icons.volume_off,
                            color: on ? scheme.primary : scheme.onPrimary, size: DisplaySize.of(context).iconSize),
                        const SizedBox(width: 6),
                        Text(
                          on ? 'Voice on' : 'Voice off',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: on ? scheme.primary : scheme.onPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Section heading that screen readers can jump between.
class SectionHeading extends StatelessWidget {
  const SectionHeading(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 8),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 26,
            decoration: BoxDecoration(color: scheme.secondary, borderRadius: BorderRadius.circular(3)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(text,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }
}
