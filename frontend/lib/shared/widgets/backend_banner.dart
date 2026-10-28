import 'package:flutter/material.dart';

import '../../core/app_dependencies.dart';
import '../../core/backend_monitor.dart';

/// Warns when the backend is unreachable or degraded.
class BackendBanner extends StatelessWidget {
  const BackendBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final monitor = AppScope.of(context).backend;
    return ListenableBuilder(
      listenable: monitor,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        final (String? text, Color? bg, Color? fg) = switch (monitor.state) {
          BackendState.offline => (
              'Server unavailable. Camera analysis is paused.',
              scheme.errorContainer,
              scheme.onErrorContainer,
            ),
          BackendState.degraded => (
              'Server running with limited features: ${monitor.status?.loadErrors.keys.join(', ')}.',
              scheme.tertiaryContainer,
              scheme.onTertiaryContainer,
            ),
          _ => (null, null, null),
        };
        if (text == null) return const SizedBox.shrink();
        return Semantics(
          liveRegion: true,
          container: true,
          child: Card(
            color: bg,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
              child: Row(
                children: [
                  Icon(Icons.cloud_off, color: fg, semanticLabel: 'Warning'),
                  const SizedBox(width: 10),
                  Expanded(child: Text(text, style: TextStyle(color: fg, fontSize: 16))),
                  TextButton(
                    onPressed: monitor.check,
                    style: TextButton.styleFrom(foregroundColor: fg, minimumSize: const Size(64, 48)),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
