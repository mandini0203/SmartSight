import 'package:flutter/material.dart';

import '../../core/app_dependencies.dart';
import '../../core/guidance/guidance_controller.dart';
import 'labelled_button.dart';

/// Capture-and-analyse plus continuous guidance controls, all labelled and
/// also reachable by voice (capture / start / pause / resume / stop / repeat).
class GuidanceControls extends StatelessWidget {
  const GuidanceControls({super.key, this.captureLabel = 'Analyse now'});

  final String captureLabel;

  @override
  Widget build(BuildContext context) {
    final g = AppScope.of(context).guidance;
    return ListenableBuilder(
      listenable: g,
      builder: (context, _) {
        final state = g.state;
        final status = switch (state) {
          GuidanceState.running => g.busy ? 'Continuous guidance: analysing…' : 'Continuous guidance: on',
          GuidanceState.paused => 'Continuous guidance: paused',
          GuidanceState.idle => g.busy ? 'Analysing photo…' : 'Ready',
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Semantics(
                liveRegion: true,
                child: Row(children: [
                  if (g.busy)
                    const Padding(
                      padding: EdgeInsets.only(right: 10),
                      child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 3)),
                    ),
                  Expanded(child: Text(status, style: Theme.of(context).textTheme.titleMedium)),
                ]),
              ),
            ),
            // Capture, start / pause / resume and stop share one row.
            IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(
                  flex: 4,
                  child: LabelledButton(
                    key: const Key('capture-button'),
                    icon: Icons.camera_alt,
                    label: captureLabel,
                    stacked: true,
                    onPressed: g.busy && state == GuidanceState.idle ? null : g.captureOnce,
                    semanticHint: 'Takes one photo and describes it',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: switch (state) {
                    GuidanceState.idle => LabelledButton(
                        key: const Key('start-button'),
                        icon: Icons.play_arrow,
                        label: 'Start',
                        primary: false,
                        stacked: true,
                        onPressed: g.start,
                        semanticHint: 'Starts continuous guidance',
                      ),
                    GuidanceState.running => LabelledButton(
                        key: const Key('pause-button'),
                        icon: Icons.pause,
                        label: 'Pause',
                        primary: false,
                        stacked: true,
                        onPressed: g.pause,
                      ),
                    GuidanceState.paused => LabelledButton(
                        key: const Key('resume-button'),
                        icon: Icons.play_arrow,
                        label: 'Resume',
                        primary: false,
                        stacked: true,
                        onPressed: g.resume,
                      ),
                  },
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: LabelledButton(
                    key: const Key('stop-button'),
                    icon: Icons.stop,
                    label: 'Stop',
                    primary: false,
                    stacked: true,
                    onPressed: state == GuidanceState.idle ? null : g.stop,
                  ),
                ),
              ]),
            ),
          ],
        );
      },
    );
  }
}
