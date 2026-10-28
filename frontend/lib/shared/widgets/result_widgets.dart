import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/models.dart';
import '../../core/app_dependencies.dart';

/// The main guidance sentence, with how old it is. Results older than the
/// stale threshold are visibly and audibly marked as out of date.
class GuidanceCard extends StatefulWidget {
  const GuidanceCard({super.key, required this.message, required this.resultAt, this.confidence, this.error});

  final String? message;
  final DateTime? resultAt;
  final double? confidence;
  final String? error;

  @override
  State<GuidanceCard> createState() => _GuidanceCardState();
}

class _GuidanceCardState extends State<GuidanceCard> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.resultAt != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final staleAfter = AppScope.of(context).settings.value.staleAfterSeconds;
    final age = widget.resultAt == null ? null : DateTime.now().difference(widget.resultAt!);
    final stale = age != null && age.inSeconds > staleAfter;

    if (widget.error != null) {
      return Card(
        color: scheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Semantics(
            liveRegion: true,
            child: Text(widget.error!, style: TextStyle(fontSize: 20, color: scheme.onErrorContainer)),
          ),
        ),
      );
    }
    if (widget.message == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('No result yet. Point the camera and choose Analyse now.', style: TextStyle(fontSize: 18)),
        ),
      );
    }
    final ageText = age == null ? '' : (age.inSeconds < 2 ? 'Just now' : '${age.inSeconds} seconds ago');
    return Card(
      color: stale ? scheme.surfaceContainerHighest : scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              liveRegion: !stale,
              child: Text(
                widget.message!,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: stale ? scheme.onSurfaceVariant : scheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              [
                if (stale) 'Out of date — from $ageText. Analyse again for a current view.' else ageText,
                if (widget.confidence != null) 'Confidence ${(widget.confidence! * 100).round()}%',
              ].join(' · '),
              style: TextStyle(fontSize: 16, color: stale ? scheme.error : null, fontWeight: stale ? FontWeight.bold : null),
            ),
          ],
        ),
      ),
    );
  }
}

/// Expandable "why" section listing rule evidence.
class EvidenceTile extends StatelessWidget {
  const EvidenceTile({super.key, required this.title, required this.evidence, this.subtitle});

  final String title;
  final String? subtitle;
  final List<String> evidence;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        title: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        subtitle: subtitle == null ? null : Text(subtitle!, style: const TextStyle(fontSize: 16)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Why:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          for (final e in evidence) Text('• $e', style: const TextStyle(fontSize: 16)),
        ],
      ),
    );
  }
}

class DetectionTile extends StatelessWidget {
  const DetectionTile(this.d, {super.key});
  final Detection d;

  @override
  Widget build(BuildContext context) {
    final parts = [
      if (d.position != null) d.position!.description,
      if (d.distance != null) d.distance!.label,
    ];
    return Card(
      child: ListTile(
        title: Text('${d.label} · ${(d.confidence * 100).round()}%',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        subtitle: Text(parts.join('\n'), style: const TextStyle(fontSize: 16)),
      ),
    );
  }
}

/// States which component produced the result — never overstated.
class ProvenanceNote extends StatelessWidget {
  const ProvenanceNote(this.lines, {super.key});
  final List<String> lines;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(lines.join('\n'), style: Theme.of(context).textTheme.bodyMedium),
      );
}

const kSafetyNote = 'SmartSight gives assistive information and can be wrong. '
    'It does not replace your cane, guide dog or other mobility aid.';
