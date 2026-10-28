import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/app_dependencies.dart';
import '../../core/voice/voice_command.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/result_widgets.dart';

class _Feature {
  const _Feature(this.destination, this.icon, this.description);
  final AppDestination destination;
  final IconData icon;
  final String description;
}

const _features = [
  _Feature(AppDestination.scan, Icons.travel_explore, 'Describe around you, find a seat or object'),
  _Feature(AppDestination.items, Icons.inventory_2, 'Register and find your belongings'),
  _Feature(AppDestination.doorsSigns, Icons.door_front_door, 'Find exit signs and doors'),
  _Feature(AppDestination.colour, Icons.palette, 'Identify the colour of an object'),
  _Feature(AppDestination.profile, Icons.account_circle, 'Your account and details'),
  _Feature(AppDestination.settings, Icons.settings, 'Colours, voice, vibration and server'),
];

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _request = TextEditingController();
  bool _sending = false;

  Future<void> _send() async {
    final text = _request.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    await AppScope.of(context).dispatcher.handle(text);
    if (mounted) {
      setState(() => _sending = false);
      _request.clear();
    }
  }

  @override
  void dispose() {
    _request.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Home',
      children: [
        ListenableBuilder(
          listenable: AppScope.of(context).auth,
          builder: (context, _) {
            final user = AppScope.of(context).auth.user;
            final scheme = Theme.of(context).colorScheme;
            final size = DisplaySize.of(context);
            final compact = size == DisplaySize.normal;
            return Container(
              padding: EdgeInsets.symmetric(horizontal: size.gap + 4, vertical: compact ? 8 : size.gap + 4),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                children: [
                  Icon(Icons.waving_hand, size: size.iconSize + 6, color: scheme.onPrimaryContainer),
                  SizedBox(width: size.gap),
                  Expanded(
                    child: Text(
                      user == null
                          ? 'What would you like to do?'
                          : 'Hello, ${user.firstName}. What would you like to do?',
                      style: (compact ? Theme.of(context).textTheme.titleMedium : Theme.of(context).textTheme.titleLarge)
                          ?.copyWith(fontWeight: FontWeight.w700, color: scheme.onPrimaryContainer),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        SizedBox(height: DisplaySize.of(context).gap + 2),
        const _FeatureGrid(_features),
        const SectionHeading('Ask for something'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                key: const Key('request-field'),
                controller: _request,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                style: const TextStyle(fontSize: 18),
                decoration: const InputDecoration(
                  labelText: 'Type a request',
                  hintText: 'For example: find my phone',
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              key: const Key('send-request'),
              onPressed: _sending ? null : _send,
              icon: const Icon(Icons.send),
              label: const Text('Send'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Or use Speak command below. Say "help" to hear what you can say.',
          style: TextStyle(fontSize: 16),
        ),
        const ProvenanceNote([kSafetyNote]),
      ],
    );
  }
}

/// The features as rounded widget-style cards, two per row: square, or
/// shorter at the Normal screen size. Cards
/// grow taller rather than clip when the system text size is large.
class _FeatureGrid extends StatelessWidget {
  const _FeatureGrid(this.features);
  final List<_Feature> features;

  @override
  Widget build(BuildContext context) {
    final size = DisplaySize.of(context);
    final gap = size.gap;
    return LayoutBuilder(builder: (context, c) {
      final cardHeight = (c.maxWidth - gap) / 2 * size.cardHeightRatio;
      return Column(
        children: [
          for (var i = 0; i < features.length; i += 2)
            Padding(
              padding: EdgeInsets.only(bottom: gap),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _FeatureCard(features[i], minHeight: cardHeight)),
                    SizedBox(width: gap),
                    Expanded(
                      child: i + 1 < features.length
                          ? _FeatureCard(features[i + 1], minHeight: cardHeight)
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    });
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard(this.f, {required this.minHeight});
  final _Feature f;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Every card uses the theme's main colour; the icons tell them apart.
    final (bg, fg) = (scheme.primary, scheme.onPrimary);
    final size = DisplaySize.of(context);
    final compact = size == DisplaySize.normal;
    final badge = size.iconSize * (compact ? 1.5 : 1.75);
    final radius = BorderRadius.circular(size == DisplaySize.normal ? 22 : 28);
    return Semantics(
      button: true,
      label: '${f.destination.title}. ${f.description}',
      excludeSemantics: true,
      child: Material(
        color: bg,
        borderRadius: radius,
        elevation: 2,
        shadowColor: Colors.black54,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('tile-${f.destination.name}'),
          onTap: () => context.go(f.destination.path),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Stack(
              children: [
                // Large faded icon in the corner, as on phone home-screen widgets.
                Positioned(
                  right: -18,
                  bottom: -18,
                  child: Icon(f.icon, size: badge * 2.1, color: fg.withValues(alpha: 0.12)),
                ),
                Padding(
                  padding: EdgeInsets.all(compact ? 12 : size.gap + 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: badge,
                        height: badge,
                        decoration: BoxDecoration(
                          color: fg.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(f.icon, size: badge * 0.6, color: fg),
                      ),
                      SizedBox(height: compact ? 6 : size.gap),
                      const Spacer(),
                      Text(f.destination.title,
                          style: TextStyle(
                              fontSize: compact ? 18 : 20, fontWeight: FontWeight.w800, color: fg, height: 1.15)),
                      const SizedBox(height: 4),
                      // Compact cards keep the description to two lines; the
                      // full text is always in the spoken label.
                      Text(f.description,
                          maxLines: compact ? 2 : null,
                          overflow: compact ? TextOverflow.ellipsis : null,
                          style: TextStyle(fontSize: compact ? 13 : 14, color: fg, height: 1.25)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
