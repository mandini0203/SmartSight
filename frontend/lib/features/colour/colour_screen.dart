import 'package:flutter/material.dart';

import '../../core/api/models.dart';
import '../../core/camera/frame_source.dart';
import '../../core/guidance/guidance_controller.dart';
import '../../shared/analysis_screen_mixin.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/camera_panel.dart';
import '../../shared/widgets/labelled_button.dart';
import '../../shared/widgets/result_widgets.dart';

class ColourScreen extends StatefulWidget {
  const ColourScreen({super.key, this.autostart = false});
  final bool autostart;

  @override
  State<ColourScreen> createState() => _ColourScreenState();
}

class _ColourScreenState extends State<ColourScreen> with AnalysisScreenMixin {
  ColourResult? _result;
  DateTime? _resultAt;

  /// Point selected by tapping the preview (normalised); null = centre.
  Offset? _point;

  @override
  String get analysisOwner => 'colour';
  @override
  bool get autostart => widget.autostart;

  @override
  Future<GuidanceOutcome> analyseFrame(CapturedFrame frame) async {
    final p = _point;
    final r = await deps.api.identifyColour(frame.jpeg, pointX: p?.dx, pointY: p?.dy, frameId: frame.id);
    if (mounted) {
      setState(() {
        _result = r;
        _resultAt = frame.capturedAt;
      });
    }
    final source = r.regionSource.startsWith('detection:') ? 'The ${r.regionSource.substring(10)}: ' : '';
    return GuidanceOutcome('$source${r.message}');
  }

  void _selectPoint(Offset p) {
    setState(() => _point = p);
    deps.guidance.captureOnce();
  }

  void _useCentre() {
    setState(() => _point = null);
    deps.guidance.captureOnce();
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    return AppScaffold(
      title: 'Colour Finder',
      children: [
        const Text(
          'Point the camera at an object and choose Identify colour. '
          'If you can see the screen, tap the object in the camera view to select it.',
          style: TextStyle(fontSize: 18),
        ),
        const SizedBox(height: 12),
        CameraPanel(
          onTapNormalised: _selectPoint,
          tapHint: 'Double tap to identify the colour at this point',
        ),
        const SizedBox(height: 8),
        LabelledButton(
          key: const Key('identify-colour-button'),
          icon: Icons.palette,
          label: 'Identify colour at centre',
          onPressed: _useCentre,
        ),
        const SectionHeading('Result'),
        GuidanceCard(message: r?.message, resultAt: _resultAt, confidence: r?.confidence, error: lastError),
        if (r != null && lastError == null) ...[
          for (final c in r.colours)
            Card(
              child: ListTile(
                leading: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Color(c.argb),
                    border: Border.all(color: Theme.of(context).colorScheme.onSurface, width: 2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                title: Text(c.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                subtitle: Text('${(c.fraction * 100).round()}% of the region', style: const TextStyle(fontSize: 16)),
              ),
            ),
          ProvenanceNote([
            'Region: ${switch (r.regionSource) {
              'centre' => 'centre of the photo',
              'point' => 'area around the selected point',
              final s when s.startsWith('detection:') => 'detected ${s.substring(10)}',
              final s => s,
            }}.',
            ...r.caveats,
            'Method: colour clustering and nearest named colour (not a trained model).',
          ]),
        ],
      ],
    );
  }
}
