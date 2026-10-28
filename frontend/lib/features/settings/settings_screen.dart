import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/app_dependencies.dart';
import '../../core/backend_monitor.dart';
import '../../core/config/settings_controller.dart';
import '../../core/feedback/speech_output.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/labelled_button.dart';
import '../../shared/widgets/result_widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _url;
  String? _connection;
  bool _testing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _url = TextEditingController(text: AppScope.of(context).settings.value.backendUrl);
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _saveUrlAndTest() async {
    final deps = AppScope.of(context);
    final url = _url.text.trim();
    if (!isValidBackendUrl(url)) {
      setState(() => _connection = 'Enter an address like http://192.168.1.20:8000');
      return;
    }
    setState(() => _testing = true);
    await deps.settings.update(deps.settings.value.copyWith(backendUrl: url));
    final state = await deps.backend.check();
    final s = deps.backend.status;
    final msg = switch (state) {
      BackendState.online => 'Connected. ${s?.detectorName} is ready.',
      BackendState.degraded => 'Connected with limited features: ${s?.loadErrors.keys.join(', ')}.',
      _ => 'Could not connect to $url.',
    };
    if (!mounted) return;
    setState(() {
      _testing = false;
      _connection = msg;
    });
    await deps.guidance.announce(msg, remember: false);
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final s = settings.value;
        void set(AppSettings v) => settings.update(v);
        return AppScaffold(
          title: 'Settings',
          children: [
            const SectionHeading('Appearance'),
            const Text('Screen size', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Row(children: [
              for (final d in DisplaySize.values) ...[
                if (d != DisplaySize.values.first) const SizedBox(width: 8),
                Expanded(
                  child: _SizeOption(
                    size: d,
                    selected: s.displaySize == d,
                    onSelected: () {
                      set(s.copyWith(displaySize: d));
                      AppScope.of(context).guidance.announce('Screen size: ${d.title}.', remember: false);
                    },
                  ),
                ),
              ],
            ]),
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 12),
              child: Text(s.displaySize.description, style: const TextStyle(fontSize: 16)),
            ),
            const Text('Colours', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            for (final p in ColourPalette.values)
              _PaletteOption(
                palette: p,
                selected: s.colourPalette == p,
                onSelected: () {
                  set(s.copyWith(colourPalette: p));
                  AppScope.of(context).guidance.announce('Colours: ${p.title}.', remember: false);
                },
              ),
            const SizedBox(height: 12),
            const Text('Light or dark', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            SegmentedButton<ThemeMode>(
              key: const Key('theme-mode'),
              showSelectedIcon: true,
              style: SegmentedButton.styleFrom(minimumSize: const Size(0, 56)),
              segments: const [
                ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.phone_android), label: Text('Phone')),
                ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode), label: Text('Light')),
                ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode), label: Text('Dark')),
              ],
              selected: {s.themeMode},
              onSelectionChanged: s.colourPalette.alwaysDark ? null : (v) => set(s.copyWith(themeMode: v.first)),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                s.colourPalette.alwaysDark
                    ? 'Yellow on black is always dark.'
                    : 'Text turns light on dark colours and dark on light colours automatically.',
                style: const TextStyle(fontSize: 16),
              ),
            ),
            const SectionHeading('Server'),
            TextField(
              key: const Key('backend-url-field'),
              controller: _url,
              keyboardType: TextInputType.url,
              style: const TextStyle(fontSize: 18),
              decoration: const InputDecoration(labelText: 'SmartSight server address'),
            ),
            const SizedBox(height: 8),
            LabelledButton(
              key: const Key('test-connection-button'),
              icon: Icons.wifi_find,
              label: _testing ? 'Testing…' : 'Save and test connection',
              onPressed: _testing ? null : _saveUrlAndTest,
            ),
            if (_connection != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Semantics(liveRegion: true, child: Text(_connection!, style: const TextStyle(fontSize: 18))),
              ),
            const SectionHeading('Voice'),
            SwitchListTile(
              key: const Key('voice-switch'),
              title: const Text('SmartSight voice', style: TextStyle(fontSize: 18)),
              subtitle: const Text('Speak guidance and replies. You can also say "voice on" or "voice off".'),
              value: s.voiceEnabled,
              onChanged: (v) => AppScope.of(context).setVoiceEnabled(v),
            ),
            _SliderTile(
              label: 'Speech rate',
              value: s.speechRate,
              min: 0.2,
              max: 1.0,
              divisions: 8,
              valueText: '${(s.speechRate * 100).round()}%',
              onChanged: (v) => set(s.copyWith(speechRate: v)),
            ),
            RadioGroup<SpeechMode>(
              groupValue: s.speechMode,
              onChanged: (v) => set(s.copyWith(speechMode: v)),
              child: const Column(children: [
                RadioListTile(
                  value: SpeechMode.automatic,
                  title: Text('Automatic'),
                  subtitle: Text('Use the screen reader when it is on, otherwise the app voice'),
                ),
                RadioListTile(value: SpeechMode.appVoice, title: Text('Always use the app voice')),
                RadioListTile(value: SpeechMode.screenReader, title: Text('Always use screen reader announcements')),
              ]),
            ),
            SwitchListTile(
              title: const Text('Detailed spoken guidance', style: TextStyle(fontSize: 18)),
              subtitle: const Text('Also read positions of several objects'),
              value: s.verboseGuidance,
              onChanged: (v) => set(s.copyWith(verboseGuidance: v)),
            ),
            SwitchListTile(
              title: const Text('Vibration feedback', style: TextStyle(fontSize: 18)),
              subtitle: const Text('Different patterns for found, warning and error'),
              value: s.hapticsEnabled,
              onChanged: (v) => set(s.copyWith(hapticsEnabled: v)),
            ),
            const SectionHeading('Scanning'),
            _SliderTile(
              label: 'Continuous guidance: photo every',
              value: s.scanIntervalSeconds.toDouble(),
              min: 2,
              max: 10,
              divisions: 8,
              valueText: '${s.scanIntervalSeconds} seconds',
              onChanged: (v) => set(s.copyWith(scanIntervalSeconds: v.round())),
            ),
            _SliderTile(
              label: 'Treat results as out of date after',
              value: s.staleAfterSeconds.toDouble(),
              min: 4,
              max: 20,
              divisions: 16,
              valueText: '${s.staleAfterSeconds} seconds',
              onChanged: (v) => set(s.copyWith(staleAfterSeconds: v.round())),
            ),
            _SliderTile(
              label: 'Camera field of view (for distance estimates)',
              value: s.cameraFovDegrees,
              min: 40,
              max: 100,
              divisions: 60,
              valueText: '${s.cameraFovDegrees.round()} degrees',
              onChanged: (v) => set(s.copyWith(cameraFovDegrees: v.roundToDouble())),
            ),
            const SectionHeading('About'),
            const ProvenanceNote([
              'Object detection: pretrained YOLOv8 (COCO, 80 object types), running on your SmartSight server.',
              'Scene guidance, seat assessment and request understanding: rule-based (not trained models).',
              'Distances: approximate estimates from typical object sizes.',
              'Photos are sent to your server only when you analyse; nothing is uploaded elsewhere.',
              kSafetyNote,
            ]),
          ],
        );
      },
    );
  }
}

class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.valueText,
    required this.onChanged,
  });

  final String label, valueText;
  final double value, min, max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$label: $valueText', style: const TextStyle(fontSize: 18)),
            Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              label: valueText,
              semanticFormatterCallback: (_) => valueText,
              onChanged: onChanged,
            ),
          ],
        ),
      );
}

/// One colour theme: a preview of its colours, its name and who it helps.
class _PaletteOption extends StatelessWidget {
  const _PaletteOption({required this.palette, required this.selected, required this.onSelected});

  final ColourPalette palette;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final preview = buildColourScheme(palette, Theme.of(context).brightness);
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      label: '${palette.title}. ${palette.description}',
      excludeSemantics: true,
      child: Card(
        key: Key('palette-${palette.name}'),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: selected ? scheme.primary : scheme.outlineVariant, width: selected ? 3 : 1.5),
        ),
        child: InkWell(
          onTap: onSelected,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // A small sample of the theme: its background, a button and text.
                // Decorative, so it keeps its size at large text scales.
                MediaQuery.withNoTextScaling(child: Container(
                  width: 72,
                  height: 64,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: preview.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: preview.outline, width: 1.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Aa', style: TextStyle(color: preview.onSurface, fontWeight: FontWeight.w800, fontSize: 16)),
                      const Spacer(),
                      Row(children: [
                        for (final c in [preview.primary, preview.secondary, preview.tertiary])
                          Container(
                            width: 14,
                            height: 14,
                            margin: const EdgeInsets.only(right: 2),
                            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                          ),
                      ]),
                    ],
                  ),
                )),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(palette.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                      Text(palette.description, style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(selected ? Icons.check_circle : Icons.circle_outlined,
                    size: 30, color: selected ? scheme.primary : scheme.outline),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One screen size choice, with a sample of its text size.
class _SizeOption extends StatelessWidget {
  const _SizeOption({required this.size, required this.selected, required this.onSelected});

  final DisplaySize size;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = selected ? scheme.onPrimary : scheme.onSurface;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      label: 'Screen size ${size.title}. ${size.description}',
      excludeSemantics: true,
      child: Material(
        key: Key('size-${size.name}'),
        color: selected ? scheme.primary : scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: selected ? scheme.primary : scheme.outline, width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onSelected,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // The sample shows the real difference, so it ignores the
                // current text scale.
                MediaQuery.withNoTextScaling(
                  child: SizedBox(
                    height: 40,
                    child: Center(
                      child: Text('Aa',
                          style: TextStyle(fontSize: 22 * size.textFactor + 4, fontWeight: FontWeight.w800, color: fg)),
                    ),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (selected) ...[Icon(Icons.check, size: 18, color: fg), const SizedBox(width: 4)],
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(size.title,
                            maxLines: 1, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: fg)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
