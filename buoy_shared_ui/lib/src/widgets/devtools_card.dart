import 'package:flutter/material.dart';

import 'package:buoy_core/buoy_core.dart';
import '../macos_colors.dart';

/// Port of shared-ui's DevToolsCard — the unified list-row container.
/// RN constants: padding 12, marginV 4, radius 8, minHeight 44, borderWidth
/// 1, bg buoyColors.card, border buoyColors.border@40. The network row
/// overrides marginH to 8 and adds a 3px status-colored left border (RN puts
/// borderLeftWidth on the padded content box; here it's an inner container
/// clipped by the card radius, which renders identically).
class DevToolsCard extends StatelessWidget {
  const DevToolsCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.marginHorizontal = 12,
    this.borderLeftColor,
    this.activeOpacity = 0.8,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double marginHorizontal;
  final Color? borderLeftColor;
  final double activeOpacity;

  @override
  Widget build(BuildContext context) {
    Widget content = Container(
      constraints: const BoxConstraints(minHeight: 42),
      padding: const EdgeInsets.all(12),
      decoration: borderLeftColor == null
          ? null
          : BoxDecoration(
              border: Border(
                left: BorderSide(color: borderLeftColor!, width: 3),
              ),
            ),
      child: child,
    );

    final card = Container(
      decoration: BoxDecoration(
        color: BuoyColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: BuoyColors.border.hexAlpha(0x40)),
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(7), child: content),
    );

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: marginHorizontal, vertical: 4),
      child: onTap == null && onLongPress == null
          ? card
          : TouchableOpacity(
              activeOpacity: activeOpacity,
              onTap: onTap,
              onLongPress: onLongPress,
              child: card,
            ),
    );
  }
}
