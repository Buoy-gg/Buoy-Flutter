/// Ports packages/shared/src/ui/components/EventHistoryViewer/ViewToggleCards.tsx
/// — two side-by-side cards for switching between the "current" and "diff"
/// detail views. Dumb component; all state is controlled externally.
///
/// RN numerics: container row gap 12 / padding 14 on backgroundBase; card
/// radius 14 / padding 14 / column gap 8; active border 1.5 info + infoBackground
/// tint; label 12/700 uppercase letterSpacing 0.5; description 11 lineHeight 16;
/// disabled card opacity 0.5. Active icon color: info (current) / success (diff).
library;

import 'package:flutter/material.dart';

import 'package:buoy_core/buoy_core.dart';

import '../macos_colors.dart';

class ViewToggleCards extends StatelessWidget {
  const ViewToggleCards({
    super.key,
    required this.activeView,
    required this.onViewChange,
    required this.currentLabel,
    required this.currentDescription,
    required this.currentIcon,
    required this.diffLabel,
    required this.diffDescription,
    required this.diffIcon,
    this.diffDisabled = false,
  });

  /// 'current' | 'diff'.
  final String activeView;
  final ValueChanged<String> onViewChange;
  final String currentLabel;
  final String currentDescription;
  final LucideIcon currentIcon;
  final String diffLabel;
  final String diffDescription;
  final LucideIcon diffIcon;
  final bool diffDisabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: MacOSColors.backgroundBase,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Expanded(
            child: _card(
              view: 'current',
              label: currentLabel,
              description: currentDescription,
              icon: currentIcon,
              activeColor: MacOSColors.info,
              disabled: false,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _card(
              view: 'diff',
              label: diffLabel,
              description: diffDescription,
              icon: diffIcon,
              activeColor: MacOSColors.success,
              disabled: diffDisabled,
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({
    required String view,
    required String label,
    required String description,
    required LucideIcon icon,
    required Color activeColor,
    required bool disabled,
  }) {
    final isActive = activeView == view;
    final iconColor = isActive
        ? activeColor
        : disabled
            ? MacOSColors.textMuted
            : MacOSColors.textSecondary;
    final labelColor = isActive
        ? MacOSColors.textPrimary
        : disabled
            ? MacOSColors.textMuted
            : MacOSColors.textSecondary;
    final descriptionColor =
        isActive ? MacOSColors.textPrimary : MacOSColors.textMuted;

    final card = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isActive
            ? MacOSColors.infoBackground.hexAlpha(0x30)
            : MacOSColors.backgroundCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          width: isActive ? 1.5 : 1,
          color: isActive ? MacOSColors.info : MacOSColors.borderDefault,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              BuoyGlyph(icon, size: 16, color: iconColor),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: labelColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: TextStyle(
              fontSize: 11,
              height: 16 / 11,
              color: descriptionColor,
            ),
          ),
        ],
      ),
    );

    if (disabled) return Opacity(opacity: 0.5, child: card);
    return TouchableOpacity(
      activeOpacity: 0.8,
      onTap: () => onViewChange(view),
      child: card,
    );
  }
}
