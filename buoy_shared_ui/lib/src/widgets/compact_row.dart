import 'package:flutter/material.dart';

import 'package:buoy_core/buoy_core.dart';

import '../macos_colors.dart';

/// Ports packages/shared/src/ui/components/CompactRow.tsx — the unified
/// expandable list row (status dot + label · primary/secondary text · right
/// badge/timestamp + chevron). Only the header toggles; the expanded body is a
/// sibling so taps inside it don't collapse the card.
///
/// RN numerics: wrapper marginH 8 / marginV 3; card bg buoyColors.card, radius
/// 8, border `border40`, padding 12; statusSection width 90, dot 8×8; label
/// 11/600; querySection flex 2 padH 12, monospace 12; badge 12/600 tabular;
/// bottomRight 9 monospace muted; expandedContent marginTop 8 / borderTop
/// `border20` / marginLeft 24. Selected scale 1.01, expanded scale 1.02.
class CompactRow extends StatelessWidget {
  const CompactRow({
    super.key,
    required this.statusDotColor,
    required this.statusLabel,
    this.statusSublabel,
    required this.primaryText,
    this.secondaryText,
    this.secondaryAccessory,
    this.expandedContent,
    this.isExpanded = false,
    this.badgeText,
    this.badgeColor,
    this.customBadge,
    this.showChevron = false,
    this.bottomRightText,
    this.isSelected = false,
    this.onPress,
    this.disabled = false,
    this.expandedGlowColor,
  });

  final Color statusDotColor;
  final String statusLabel;
  final String? statusSublabel;
  final String primaryText;
  final String? secondaryText;
  final Widget? secondaryAccessory;
  final Widget? expandedContent;
  final bool isExpanded;

  /// Right-side text badge (String or number rendered as text).
  final String? badgeText;
  final Color? badgeColor;
  final Widget? customBadge;
  final bool showChevron;

  /// Bottom-right node — a String (rendered as muted monospace) or a Widget
  /// (e.g. a shared-ui RelativeTime).
  final Object? bottomRightText;

  final bool isSelected;
  final VoidCallback? onPress;
  final bool disabled;
  final Color? expandedGlowColor;

  @override
  Widget build(BuildContext context) {
    final glow = expandedGlowColor ?? BuoyColors.primary;

    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Status section (fixed width 90).
        SizedBox(
          width: 90,
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: statusDotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 70),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        statusLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          height: 14 / 11,
                          color: statusDotColor,
                        ),
                      ),
                      if (statusSublabel != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Text(
                            statusSublabel!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10,
                              color: BuoyColors.textMuted,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        // Content section (flex 2).
        Expanded(
          flex: 2,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  primaryText,
                  maxLines: isExpanded ? null : 2,
                  overflow: isExpanded ? null : TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 16 / 12,
                    color: BuoyColors.text,
                  ),
                ),
                if (!isExpanded &&
                    (secondaryText != null || secondaryAccessory != null))
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Row(
                      children: [
                        if (secondaryText != null)
                          Flexible(
                            child: Text(
                              secondaryText!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10,
                                color: BuoyColors.textMuted,
                              ),
                            ),
                          ),
                        if (secondaryAccessory != null) ...[
                          const SizedBox(width: 6),
                          secondaryAccessory!,
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        // Right section (badge + chevron).
        _rightSection(),
      ],
    );

    final touchable = TouchableOpacity(
      activeOpacity: 0.8,
      onTap: (disabled || onPress == null) ? null : onPress,
      child: header,
    );

    final card = AnimatedScale(
      scale: isExpanded ? 1.02 : (isSelected ? 1.01 : 1),
      duration: const Duration(milliseconds: 150),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? BuoyColors.primary.hexAlpha(0x15)
              : BuoyColors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            width: isExpanded ? 2 : 1,
            color: isExpanded
                ? glow
                : (isSelected
                    ? BuoyColors.primary.hexAlpha(0x50)
                    : BuoyColors.border.hexAlpha(0x40)),
          ),
          boxShadow: isExpanded
              ? [BoxShadow(color: glow.withValues(alpha: 0.8), blurRadius: 20)]
              : (isSelected
                  ? [
                      BoxShadow(
                        color: BuoyColors.primary.withValues(alpha: 0.1),
                        blurRadius: 8,
                      ),
                    ]
                  : null),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            touchable,
            if (isExpanded && expandedContent != null)
              Container(
                margin: const EdgeInsets.only(top: 8, left: 24),
                padding: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: BuoyColors.border.hexAlpha(0x20)),
                  ),
                ),
                child: expandedContent,
              ),
          ],
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: card,
    );
  }

  Widget _rightSection() {
    final showBadgeContainer = customBadge != null ||
        badgeText != null ||
        (!isExpanded && bottomRightText != null);
    final bottom = bottomRightText;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showBadgeContainer)
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (customBadge != null)
                customBadge!
              else if (badgeText != null)
                Text(
                  badgeText!,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: badgeColor ?? statusDotColor,
                  ),
                ),
              if (!isExpanded && bottom != null)
                if (bottom is Widget)
                  // RN wraps bottomRightText in <Text style={bottomRightText}>,
                  // so a nested node (e.g. RelativeTime, whose own Text has no
                  // style) INHERITS 9px / muted / monospace. Mirror that here so
                  // the timestamp isn't rendered at the ambient default size.
                  DefaultTextStyle.merge(
                    style: const TextStyle(
                      fontSize: 9,
                      color: BuoyColors.textMuted,
                      fontFamily: 'monospace',
                    ),
                    child: bottom,
                  )
                else
                  Text(
                    '$bottom',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 9,
                      color: BuoyColors.textMuted,
                      fontFamily: 'monospace',
                    ),
                  ),
            ],
          ),
        if (showChevron)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: BuoyGlyph(
              isExpanded ? BuoyIcons.chevronDown : BuoyIcons.chevronRight,
              size: 14,
              color: BuoyColors.textMuted,
            ),
          ),
      ],
    );
  }
}
