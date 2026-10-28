import 'package:flutter/material.dart';

import '../../core/api/models.dart';
import '../../core/camera/frame_source.dart';
import '../../core/feedback/haptics.dart';
import '../../core/guidance/guidance_controller.dart';
import '../../core/storage/item_repository.dart';
import '../../shared/analysis_screen_mixin.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/camera_panel.dart';
import '../../shared/widgets/guidance_controls.dart';
import '../../shared/widgets/result_widgets.dart';

class FindItemScreen extends StatefulWidget {
  const FindItemScreen({super.key, required this.itemId, this.autostart = false});

  final String itemId;
  final bool autostart;

  @override
  State<FindItemScreen> createState() => _FindItemScreenState();
}

class _FindItemScreenState extends State<FindItemScreen> with AnalysisScreenMixin {
  ItemMatchResult? _result;
  DateTime? _resultAt;
  List<dynamic>? _refs;

  PersonalItem? get _item => deps.items.byId(widget.itemId);

  @override
  String get analysisOwner => 'find-item';
  @override
  bool get autostart => widget.autostart;

  @override
  Future<GuidanceOutcome> analyseFrame(CapturedFrame frame) async {
    final item = _item;
    if (item == null) return const GuidanceOutcome('This item no longer exists.', cue: HapticCue.error);
    final refs = await deps.items.references(item);
    _refs = refs;
    if (refs.isEmpty) return const GuidanceOutcome('This item has no reference photos.', cue: HapticCue.error);
    final r = await deps.api.matchItem(frame.jpeg,
        references: refs, itemLabel: item.label, itemName: item.name, frameId: frame.id);
    if (mounted) {
      setState(() {
        _result = r;
        _resultAt = frame.capturedAt;
      });
    }
    return GuidanceOutcome(r.message, cue: switch (r.status) {
      MatchStatus.found => HapticCue.found,
      MatchStatus.possiblyFound => HapticCue.warning,
      _ => HapticCue.success,
    });
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    if (item == null) {
      return const AppScaffold(title: 'Find item', children: [Text('Item not found.', style: TextStyle(fontSize: 18))]);
    }
    final r = _result;
    return AppScaffold(
      title: 'Find ${item.name}',
      children: [
        Text('Searching for ${kRegistrableItemTypes[item.label] ?? item.label} that looks like your photos. '
            'Sweep the camera slowly.', style: const TextStyle(fontSize: 18)),
        const SizedBox(height: 12),
        const CameraPanel(),
        const GuidanceControls(captureLabel: 'Search now'),
        const SectionHeading('Result'),
        GuidanceCard(message: r?.message, resultAt: _resultAt, error: lastError),
        if (r != null)
          ProvenanceNote([
            if (r.bestSimilarity != null) 'Best similarity: ${(r.bestSimilarity! * 100).round()}% '
                '(${r.candidateCount} candidate${r.candidateCount == 1 ? '' : 's'}).',
            'Matcher: ${r.matcher.description}',
            if (_refs != null) 'Compared with ${_refs!.length} reference photos.',
          ]),
        const ProvenanceNote([kSafetyNote]),
      ],
    );
  }
}
