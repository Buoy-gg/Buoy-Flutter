import 'package:flutter/material.dart';

import '../macos_colors.dart';

/// Ports packages/shared/src/ui/components/ExpandedInfoRow.tsx — the
/// `label: [badge]` rows inside expanded DevTools cards (used by storage/
/// zustand), plus the [PillBadge] pill they render.
///
/// Row: flex row, gap 10, label 10/600 muted monospace minWidth 70.
class ExpandedInfoRow extends StatelessWidget {
  const ExpandedInfoRow({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 70),
          child: Text(
            '$label:',
            style: const TextStyle(
              fontSize: 10,
              color: MacOSColors.textMuted,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
            ),
          ),
        ),
        const SizedBox(width: 10),
        child,
      ],
    );
  }
}

enum PillBadgeSize { sm, md }

/// PillBadge — the rounded-full pill used in expanded card rows. `md`
/// (default): padH 8 / padV 3 / font 10; `sm`: padH 5 / padV 1 / font 9.
/// bg `color20`, border `color40`, monospace 700 label with letter-spacing.
class PillBadge extends StatelessWidget {
  const PillBadge({
    super.key,
    required this.color,
    required this.child,
    this.icon,
    this.size = PillBadgeSize.md,
  });

  final Color color;
  final Widget child;
  final Widget? icon;
  final PillBadgeSize size;

  @override
  Widget build(BuildContext context) {
    final isSm = size == PillBadgeSize.sm;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isSm ? 5 : 8,
        vertical: isSm ? 1 : 3,
      ),
      decoration: BoxDecoration(
        color: color.hexAlpha(0x20),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.hexAlpha(0x40)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Padding(padding: const EdgeInsets.only(right: 4), child: icon),
          DefaultTextStyle.merge(
            style: TextStyle(
              fontSize: isSm ? 9 : 10,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
              letterSpacing: isSm ? 0.3 : 0.5,
              color: color,
            ),
            child: child,
          ),
        ],
      ),
    );
  }
}
