import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/api/models.dart';
import '../../core/app_dependencies.dart';
import '../../core/camera/frame_source.dart';
import '../../core/permissions/permission_service.dart';

/// A box to draw over the preview, in normalised (0..1) coordinates.
class OverlayBox {
  const OverlayBox(this.box, this.label, {this.highlight = false});
  final BoundingBox box;
  final String label;
  final bool highlight;
}

/// Live camera preview with permission handling, error states, optional
/// tap-to-select and an overlay of the last analysed result.
class CameraPanel extends StatefulWidget {
  const CameraPanel({
    super.key,
    this.overlay = const [],
    this.onTapNormalised,
    this.tapHint,
    this.maxHeightFraction = 0.5,
    this.floating,
  });

  final List<OverlayBox> overlay;

  /// Controls floating along the bottom of the preview, like the mode
  /// switcher in a phone camera app (e.g. task choices). Shown above the
  /// message instead while the camera is not ready.
  final Widget? floating;
  final void Function(Offset normalised)? onTapNormalised;
  final String? tapHint;
  final double maxHeightFraction;

  @override
  State<CameraPanel> createState() => _CameraPanelState();
}

class _CameraPanelState extends State<CameraPanel> {
  late FrameSource _frames;
  PermissionResult? _permission;
  Offset? _tapPoint;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (!mounted) return;
    final deps = AppScope.of(context);
    _frames = deps.frames;
    final p = await deps.permissions.requestCamera();
    if (!mounted) return;
    setState(() => _permission = p);
    if (p == PermissionResult.granted) {
      await _frames.acquire();
      _leased = true;
    } else {
      await deps.guidance.announce('Camera permission is needed to analyse your surroundings.', remember: false);
    }
  }

  bool _leased = false;

  @override
  void dispose() {
    if (_leased) _frames.releaseLease();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final deps = AppScope.of(context);
    // Bigger text sizes leave a little more room for the controls below.
    final sizeFactor = switch (DisplaySize.of(context)) {
      DisplaySize.normal => 0.82,
      DisplaySize.large => 0.75,
      DisplaySize.larger => 0.7,
    };
    final maxH = MediaQuery.sizeOf(context).height * widget.maxHeightFraction * sizeFactor;
    if (_permission == null) {
      return _message(context, 'Starting camera…', busy: true);
    }
    if (_permission != PermissionResult.granted) {
      return _message(
        context,
        'Camera permission is not granted. SmartSight needs the camera to describe your surroundings.',
        action: _permission == PermissionResult.permanentlyDenied
            ? ('Open app settings', deps.permissions.openSettings)
            : ('Allow camera', _start),
      );
    }
    return ListenableBuilder(
      listenable: deps.frames,
      builder: (context, _) {
        final f = deps.frames;
        switch (f.state) {
          case CameraState.ready:
            break;
          case CameraState.uninitialised || CameraState.initialising:
            return _message(context, 'Starting camera…', busy: true);
          case CameraState.permissionDenied || CameraState.unavailable:
            return _message(context, f.errorMessage ?? 'The camera is unavailable.',
                action: ('Try again', () => f.initialise()));
        }
        final ratio = f.previewAspectRatio;
        // Full width, as tall as allowed: the picture is cropped at the
        // edges rather than shrunk. Boxes and taps are drawn on the
        // uncropped picture and scaled with it, so they stay aligned.
        return LayoutBuilder(builder: (context, outer) {
          final w = outer.maxWidth;
          final h = (w / ratio).clamp(0.0, maxH);
          const frameH = 1000.0;
          // How much the cover fit shrinks the picture; the overlay is drawn
          // inside the fit, so its lines and labels are enlarged to match.
          final fitScale = [w / (frameH * ratio), h / frameH].reduce((a, b) => a > b ? a : b);
          return SizedBox(
            width: w,
            height: h,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Stack(fit: StackFit.expand, children: [
                Semantics(
                  label: 'Camera view',
                  hint: widget.tapHint,
                  image: true,
                  child: FittedBox(
                    fit: BoxFit.cover,
                    clipBehavior: Clip.hardEdge,
                    child: SizedBox(
                      width: frameH * ratio,
                      height: frameH,
                      child: GestureDetector(
                        onTapUp: widget.onTapNormalised == null
                            ? null
                            : (d) {
                                final n = Offset(
                                  (d.localPosition.dx / (frameH * ratio)).clamp(0.0, 1.0),
                                  (d.localPosition.dy / frameH).clamp(0.0, 1.0),
                                );
                                setState(() => _tapPoint = n);
                                widget.onTapNormalised!(n);
                              },
                        child: Stack(fit: StackFit.expand, children: [
                          f.buildPreview(),
                          CustomPaint(
                              painter: _OverlayPainter(widget.overlay, _tapPoint, Theme.of(context).colorScheme,
                                  scale: 1 / fitScale)),
                        ]),
                      ),
                    ),
                  ),
                ),
                if (widget.floating != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: DecoratedBox(
                      // Dark fade so the controls stay readable over any picture.
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.black.withValues(alpha: 0), Colors.black.withValues(alpha: 0.75)],
                        ),
                      ),
                      child: Padding(padding: const EdgeInsets.fromLTRB(8, 28, 8, 10), child: widget.floating!),
                    ),
                  ),
              ]),
            ),
          );
        });
      },
    );
  }

  Widget _message(BuildContext context, String text, {bool busy = false, (String, VoidCallback)? action}) {
    final card = Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (busy) const Padding(padding: EdgeInsets.only(bottom: 12), child: CircularProgressIndicator()),
            Semantics(liveRegion: true, child: Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18))),
            if (action != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: FilledButton(onPressed: action.$2, child: Text(action.$1)),
              ),
          ],
        ),
      ),
    );
    final floating = widget.floating;
    if (floating == null) return card;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [floating, const SizedBox(height: 8), card]);
  }
}

class _OverlayPainter extends CustomPainter {
  _OverlayPainter(this.boxes, this.tap, this.scheme, {this.scale = 1});

  final List<OverlayBox> boxes;
  final Offset? tap;
  final ColorScheme scheme;

  /// Multiplies line widths and text so they look the same on screen
  /// whatever the preview is scaled by.
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    for (final b in boxes) {
      final r = Rect.fromLTRB(b.box.x1 * size.width, b.box.y1 * size.height, b.box.x2 * size.width,
          b.box.y2 * size.height);
      // Okabe–Ito yellow and sky blue: distinct for colour-blind users; the
      // target also has a thicker outline.
      final colour = b.highlight ? Palette.yellow : Palette.skyBlue;
      canvas.drawRect(r, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (b.highlight ? 5 : 3) * scale
        ..color = colour);
      final tp = TextPainter(
        text: TextSpan(
          text: ' ${b.label} ',
          style: TextStyle(color: Colors.black, fontSize: 16 * scale, fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width);
      final labelRect = Rect.fromLTWH(r.left, (r.top - tp.height).clamp(0, size.height), tp.width, tp.height);
      canvas.drawRect(labelRect, Paint()..color = colour);
      tp.paint(canvas, labelRect.topLeft);
    }
    if (tap != null) {
      final p = Offset(tap!.dx * size.width, tap!.dy * size.height);
      canvas.drawCircle(p, 18 * scale, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4 * scale
        ..color = const Color(0xFFFFFFFF));
      canvas.drawCircle(p, 22 * scale, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 * scale
        ..color = const Color(0xFF000000));
    }
  }

  @override
  bool shouldRepaint(_OverlayPainter old) => old.boxes != boxes || old.tap != tap || old.scale != scale;
}
