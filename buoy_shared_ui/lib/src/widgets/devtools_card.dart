import 'package:flutter/material.dart';

import 'package:buoy_core/buoy_core.dart';

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
    this.isSelected = false,
  });

  /// RN `isSelected`: the night selection language — soft accent fill and
  /// accent border with a faint accent glow.
  final bool isSelected;

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
        // Translucent night scrim (RN rgba(12,12,12,0.9)): same luminance
        // contract as buoyColors.cardScrim, re-based on the night surface so
        // the ToolBackground reads through every tool's card lists.
        color: isSelected
            ? NightColor.accentSoft
            : const Color.fromRGBO(12, 12, 12, 0.9),
        borderRadius: BorderRadius.circular(8),
        // RN: borderColor night.border with borderBottomColor night.separator
        // (only distinct on the desktop "chat" layout, where it is the ONLY
        // edge a row has). Flutter refuses per-side colours on a rounded
        // Border, and the separator composites to ≈#1F1F1F over this card —
        // within a hair of #1A1A1C — so the outline is uniform here.
        border: Border.all(
          color: isSelected ? NightColor.accentBorderStrong : NightColor.border,
        ),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: NightColor.accent.withValues(alpha: 0.1),
                  blurRadius: 8,
                ),
              ]
            : null,
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
