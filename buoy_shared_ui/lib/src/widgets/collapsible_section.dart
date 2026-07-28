import 'package:flutter/material.dart';

import 'package:buoy_core/buoy_core.dart';

import '../game_ui_colors.dart';

/// Ports packages/shared/src/ui/components/CollapsibleSection.tsx — a titled,
/// toggleable section with an animated chevron. gameUI-themed.
///
/// RN numerics: container marginBottom 8; bordered border `border30` radius 8;
/// card bg panel radius 8. Header row space-between, padding 12, gap 8; icon 16
/// (card → primary, else secondary); title 14/600. Badge (string/number) bg
/// `primary20` padH 8 / padV 2 radius 4, text 11/600 primary. Chevron rotates
/// 180° over 200ms. Content padH 12 / padBottom 12.
enum CollapsibleVariant { bordered, plain, card }

class CollapsibleSection extends StatefulWidget {
  const CollapsibleSection({
    super.key,
    required this.title,
    required this.child,
    this.icon,
    this.badge,
    this.defaultOpen = false,
    this.variant = CollapsibleVariant.bordered,
    this.onToggle,
  });

  final String title;
  final Widget child;
  final LucideIcon? icon;

  /// A String/number (rendered as a primary pill) or a custom [Widget].
  final Object? badge;
  final bool defaultOpen;
  final CollapsibleVariant variant;
  final ValueChanged<bool>? onToggle;

  @override
  State<CollapsibleSection> createState() => _CollapsibleSectionState();
}

class _CollapsibleSectionState extends State<CollapsibleSection> {
  late bool _isOpen = widget.defaultOpen;

  void _toggle() {
    setState(() => _isOpen = !_isOpen);
    widget.onToggle?.call(_isOpen);
  }

  @override
  Widget build(BuildContext context) {
    final isCard = widget.variant == CollapsibleVariant.card;
    final iconColor =
        isCard ? GameUIColors.primary : GameUIColors.secondary;

    final section = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TouchableOpacity(
          activeOpacity: 0.7,
          onTap: _toggle,
          child: Container(
            color: Colors.transparent,
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                if (widget.icon != null) ...[
                  BuoyGlyph(widget.icon, size: 16, color: iconColor),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: GameUIColors.text,
                    ),
                  ),
                ),
                if (widget.badge != null) ...[
                  _badge(widget.badge!),
                  const SizedBox(width: 8),
                ],
                AnimatedRotation(
                  turns: _isOpen ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const BuoyGlyph(BuoyIcons.chevronDown,
                      size: 16, color: GameUIColors.secondary),
                ),
              ],
            ),
          ),
        ),
        if (_isOpen)
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 12, bottom: 12),
            child: widget.child,
          ),
      ],
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: widget.variant == CollapsibleVariant.plain
          ? Clip.none
          : Clip.antiAlias,
      decoration: switch (widget.variant) {
        CollapsibleVariant.bordered => BoxDecoration(
            border: Border.all(color: GameUIColors.border.withValues(alpha: 0x30 / 255)),
            borderRadius: BorderRadius.circular(8),
          ),
        CollapsibleVariant.card => BoxDecoration(
            color: GameUIColors.panel,
            borderRadius: BorderRadius.circular(8),
          ),
        CollapsibleVariant.plain => const BoxDecoration(),
      },
      child: section,
    );
  }

  Widget _badge(Object badge) {
    if (badge is Widget) return badge;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: GameUIColors.primary.withValues(alpha: 0x20 / 255),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$badge',
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: GameUIColors.primary,
        ),
      ),
    );
  }
}
