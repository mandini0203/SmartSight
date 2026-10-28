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

enum ScanTask {
  describe('describe_surroundings', 'Describe surroundings', 'Describe',
      'Hear what is around you and where things are.'),
  findSeat('find_seat', 'Find a place to sit', 'Find seat', 'Finds a free seat near you, like a chair or bench.'),
  findObject('find_object', 'Find an object', 'Find object', 'Choose an object below, then point the camera around.');

  const ScanTask(this.apiName, this.label, this.shortLabel, this.description);
  final String apiName;
  final String label;

  /// Fits on the floating pill over the camera; screen readers use [label].
  final String shortLabel;
  final String description;

  static ScanTask fromName(String? name) =>
      ScanTask.values.firstWhere((t) => t.apiName == name, orElse: () => ScanTask.describe);
}

/// Common everyday objects listed first in the object picker.
const _commonTargets = [
  'cell phone', 'backpack', 'handbag', 'bottle', 'cup', 'laptop', 'book', 'remote', 'chair', 'person',
  'dining table', 'couch', 'bed', 'toilet', 'sink', 'tv', 'umbrella', 'suitcase', 'keyboard', 'mouse',
];

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key, this.initialTask = ScanTask.describe, this.initialTarget, this.autostart = false});

  final ScanTask initialTask;
  final String? initialTarget;
  final bool autostart;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> with AnalysisScreenMixin {
  late ScanTask _task = widget.initialTask;
  late String _target = widget.initialTarget ?? 'cell phone';
  ScanResult? _result;
  DateTime? _resultAt;

  @override
  String get analysisOwner => 'scan';
  @override
  bool get autostart => widget.autostart;

  @override
  Future<GuidanceOutcome> analyseFrame(CapturedFrame frame) async {
    final r = await deps.api.scan(
      frame.jpeg,
      task: _task.apiName,
      targetLabel: _task == ScanTask.findObject ? _target : null,
      frameId: frame.id,
      fovDegrees: deps.settings.value.cameraFovDegrees,
    );
    if (mounted) {
      setState(() {
        _result = r;
        _resultAt = frame.capturedAt;
      });
    }
    final g = r.context.guidance;
    final verbose = deps.settings.value.verboseGuidance && g.details.isNotEmpty;
    final found = r.context.relevantObjectIds.isNotEmpty && _task != ScanTask.describe;
    return GuidanceOutcome(
      verbose ? '${g.message} ${g.details.take(3).join('. ')}.' : g.message,
      cue: found ? HapticCue.found : HapticCue.success,
    );
  }

  void _setTask(ScanTask t) {
    setState(() => _task = t);
    deps.guidance.stop(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    final classes = deps.backend.supportedClasses;
    final targets = {..._commonTargets.where((c) => classes == null || classes.contains(c)), ...?classes}.toList();
    final relevant = r?.context.relevantObjectIds.toSet() ?? {};

    return AppScaffold(
      title: 'Smart Scan',
      children: [
        CameraPanel(
          floating: _TaskPills(selected: _task, onSelected: _setTask),
          overlay: [
            for (final d in r?.detection.detections ?? const <Detection>[])
              OverlayBox(d.bboxNormalised, d.label, highlight: relevant.contains(d.id)),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(children: [
            Icon(Icons.info_outline, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(_task.description,
                  style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
          ]),
        ),
        if (_task == ScanTask.findObject)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: DropdownButtonFormField<String>(
              initialValue: targets.contains(_target) ? _target : targets.first,
              decoration: const InputDecoration(labelText: 'Object to find'),
              items: [for (final c in targets) DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 18)))],
              onChanged: (v) => setState(() => _target = v ?? _target),
            ),
          ),
        const GuidanceControls(),
        const SectionHeading('Result'),
        GuidanceCard(
          message: r?.context.guidance.message,
          resultAt: _resultAt,
          confidence: r?.context.guidance.confidence,
          error: lastError,
        ),
        // After a failed analysis, older details are hidden so they are not taken as current.
        if (r != null && lastError == null) ..._details(r),
        const ProvenanceNote([kSafetyNote]),
      ],
    );
  }

  List<Widget> _details(ScanResult r) {
    final ctx = r.context;
    return [
      if (ctx.seats.isNotEmpty) ...[
        const SectionHeading('Seats'),
        for (final s in ctx.seats)
          EvidenceTile(
            title: '${s.label}: ${s.status.label}',
            subtitle: '${s.position.description} · confidence ${(s.confidence * 100).round()}%',
            evidence: s.evidence,
          ),
      ],
      if (ctx.relationships.isNotEmpty) ...[
        const SectionHeading('Possible relationships'),
        for (final rel in ctx.relationships.take(8))
          EvidenceTile(
            title: rel.sentence,
            subtitle: 'Inferred, not certain · ${(rel.confidence * 100).round()}%',
            evidence: rel.evidence,
          ),
      ],
      SectionHeading('Detected objects (${r.detection.detections.length})'),
      if (r.detection.detections.isEmpty)
        const Text('No objects above the confidence threshold.', style: TextStyle(fontSize: 18)),
      for (final d in r.detection.detections) DetectionTile(d),
      EvidenceTile(title: 'How this was worked out', evidence: ctx.guidance.evidence),
      ProvenanceNote([
        'Detector: ${r.detection.modelName} (${r.detection.modelFile}), pretrained on COCO; '
            'it recognises 80 everyday object types only.',
        'Guidance: ${ctx.reasoner.isTrainedModel ? 'trained model' : 'rule-based reasoning (not a trained model)'}.',
        'Server time ${r.detection.totalMs.round()} ms.',
      ]),
    ];
  }
}

/// The three scan tasks as a text-only mode switcher along the bottom of
/// the camera view, like the modes in a phone camera app. The chosen one is
/// a filled pill, so it stands out by shape as well as colour.
class _TaskPills extends StatelessWidget {
  const _TaskPills({required this.selected, required this.onSelected});

  final ScanTask selected;
  final ValueChanged<ScanTask> onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final t in ScanTask.values) ...[
          if (t != ScanTask.values.first) const SizedBox(width: 4),
          Expanded(child: _TaskPill(task: t, selected: t == selected, onTap: () => onSelected(t))),
        ],
      ],
    );
  }
}

class _TaskPill extends StatelessWidget {
  const _TaskPill({required this.task, required this.selected, required this.onTap});

  final ScanTask task;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = selected ? scheme.onPrimary : Colors.white;
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: task.label,
      hint: task.description,
      excludeSemantics: true,
      child: Material(
        key: Key('task-${task.name}'),
        color: selected ? scheme.primary : Colors.transparent,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    task.shortLabel.toUpperCase(),
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 14,
                      letterSpacing: 0.8,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      color: fg,
                      shadows: selected ? null : const [Shadow(blurRadius: 4, color: Colors.black)],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
