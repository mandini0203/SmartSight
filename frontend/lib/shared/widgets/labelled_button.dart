import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// A large button that always shows a text label next to its icon.
/// Critical actions never rely on an icon alone.
class LabelledButton extends StatelessWidget {
  const LabelledButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.primary = true,
    this.semanticHint,
    this.expand = true,
    this.stacked = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final String? semanticHint;
  final bool expand;

  /// Icon above the label, for buttons sharing a row.
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final iconSize = DisplaySize.of(context).iconSize;
    if (stacked) return _stacked(context, iconSize);
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: iconSize),
        const SizedBox(width: 10),
        Flexible(child: Text(label, textAlign: TextAlign.center)),
      ],
    );
    final button = primary
        ? FilledButton(onPressed: onPressed, child: child)
        : OutlinedButton(onPressed: onPressed, child: child);
    return Semantics(
      hint: semanticHint,
      child: expand ? SizedBox(width: double.infinity, child: button) : button,
    );
  }

  Widget _stacked(BuildContext context, double iconSize) {
    final child = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: iconSize),
        const SizedBox(height: 4),
        Text(label, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
      ],
    );
    const padding = EdgeInsets.symmetric(horizontal: 6, vertical: 10);
    final button = primary
        ? FilledButton(onPressed: onPressed, style: FilledButton.styleFrom(padding: padding), child: child)
        : OutlinedButton(onPressed: onPressed, style: OutlinedButton.styleFrom(padding: padding), child: child);
    return Semantics(hint: semanticHint, child: SizedBox(width: double.infinity, child: button));
  }
}
