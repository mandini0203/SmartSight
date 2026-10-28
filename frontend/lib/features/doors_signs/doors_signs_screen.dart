import 'package:flutter/material.dart';

import '../../core/api/models.dart';
import '../../core/camera/frame_source.dart';
import '../../core/feedback/haptics.dart';
import '../../core/guidance/guidance_controller.dart';
import '../../shared/analysis_screen_mixin.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/camera_panel.dart';
import '../../shared/widgets/guidance_controls.dart';
import '../../shared/widgets/result_widgets.dart';

class DoorsSignsScreen extends StatefulWidget {
  const DoorsSignsScreen({super.key, this.autostart = false});
  final bool autostart;

  @override
  State<DoorsSignsScreen> createState() => _DoorsSignsScreenState();
}

class _DoorsSignsScreenState extends State<DoorsSignsScreen> with AnalysisScreenMixin {
  ScanResult? _result;
  DateTime? _resultAt;

  @override
  String get analysisOwner => 'doors-signs';
  @override
  bool get autostart => widget.autostart;

  @override
  Future<GuidanceOutcome> analyseFrame(CapturedFrame frame) async {
    final r = await deps.api.scan(frame.jpeg,
        task: 'find_exit', frameId: frame.id, fovDegrees: deps.settings.value.cameraFovDegrees);
    if (mounted) {
      setState(() {
        _result = r;
        _resultAt = frame.capturedAt;
      });
    }
    final found = r.signs?.candidates.isNotEmpty ?? false;
    return GuidanceOutcome(r.context.guidance.message, cue: found ? HapticCue.found : HapticCue.success);
  }

  @override
  Widget build(BuildContext context) {
    final signs = _result?.signs;
    final candidates = signs?.candidates ?? const <SignCandidate>[];
    final frame = signs?.frame;
    return AppScaffold(
      title: 'Doors and Signs',
      children: [
        const Text('Hold the phone upright and turn slowly. Exit signs are often high on walls or above doors.',
            style: TextStyle(fontSize: 18)),
        const SizedBox(height: 12),
        CameraPanel(
          overlay: [
            if (frame != null)
              for (final (i, c) in candidates.indexed)
                OverlayBox(
                  BoundingBox(c.bboxPx.x1 / frame.width, c.bboxPx.y1 / frame.height, c.bboxPx.x2 / frame.width,
                      c.bboxPx.y2 / frame.height),
                  c.kindLabel,
                  highlight: i == 0,
                ),
          ],
        ),
        const GuidanceControls(captureLabel: 'Look for exits now'),
        const SectionHeading('Result'),
        GuidanceCard(
          message: _result?.context.guidance.message,
          resultAt: _resultAt,
          confidence: _result?.context.guidance.confidence,
          error: lastError,
        ),
        if (_result != null && lastError == null) ...[
          SectionHeading('Candidates (${candidates.length})'),
          if (candidates.isEmpty) const Text('No exit signs or doors detected.', style: TextStyle(fontSize: 18)),
          for (final c in candidates)
            EvidenceTile(
              title: '${c.kindLabel} · ${(c.confidence * 100).round()}%',
              subtitle: [c.position.description, if (c.distance != null) c.distance!.label].join('\n'),
              evidence: c.evidence,
            ),
          ProvenanceNote([
            if (signs != null) 'Door/sign detector: ${signs.detector.description}',
            'Candidates can be missed or wrong. Confirm before relying on them.',
          ]),
        ],
        const ProvenanceNote([kSafetyNote]),
      ],
    );
  }
}
