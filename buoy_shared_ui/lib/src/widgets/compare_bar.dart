/// Ports packages/shared/src/ui/components/EventHistoryViewer/CompareBar.tsx
/// (+ its `EventDisplayInfo` type). The PREV | CUR metadata strip above a diff:
/// two sides, each an event label + timestamp + relative time + optional badge,
/// with optional nav chevrons for any-to-any compare (unused by the state tools
/// — they pass no navigation/picker callbacks).
///
/// RN numerics: card bg, radius 6, padH 8 / padV 6, PREV label debug-purple /
/// CUR label success-green, monospace throughout.
library;

import 'package:flutter/material.dart';

import 'package:buoy_core/buoy_core.dart';

import '../macos_colors.dart';

/// RN `EventDisplayInfo` — one side's display metadata.
class EventDisplayInfo {
  const EventDisplayInfo({
    required this.index,
    required this.label,
    required this.timestamp,
    required this.relativeTime,
    this.badge,
  });

  final int index;
  final String label;
  final String timestamp;
  final String relativeTime;
  final Widget? badge;
}

class CompareBar extends StatelessWidget {
  const CompareBar({
    super.key,
    required this.leftEvent,
    required this.rightEvent,
    this.showNavigation = false,
    this.onLeftPrevious,
    this.onLeftNext,
    this.onRightPrevious,
    this.onRightNext,
    this.canLeftPrevious = false,
    this.canLeftNext = false,
    this.canRightPrevious = false,
    this.canRightNext = false,
    this.onLeftPress,
    this.onRightPress,
  });

  final EventDisplayInfo leftEvent;
  final EventDisplayInfo rightEvent;
  final bool showNavigation;
  final VoidCallback? onLeftPrevious;
  final VoidCallback? onLeftNext;
  final VoidCallback? onRightPrevious;
  final VoidCallback? onRightNext;
  final bool canLeftPrevious;
  final bool canLeftNext;
  final bool canRightPrevious;
  final bool canRightNext;
  final VoidCallback? onLeftPress;
  final VoidCallback? onRightPress;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: MacOSColors.backgroundCard,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: MacOSColors.borderDefault),
      ),
      child: Row(
        children: [
          Expanded(
            child: _side(
              label: 'PREV',
              labelColor: MacOSColors.debug,
              event: leftEvent,
              onPrevious: onLeftPrevious,
              onNext: onLeftNext,
              canPrevious: canLeftPrevious,
              canNext: canLeftNext,
              onPress: onLeftPress,
            ),
          ),
          const SizedBox(width: 8),
          Container(width: 1, height: 34, color: MacOSColors.backgroundInput),
          const SizedBox(width: 8),
          Expanded(
            child: _side(
              label: 'CUR',
              labelColor: MacOSColors.success,
              event: rightEvent,
              onPrevious: onRightPrevious,
              onNext: onRightNext,
              canPrevious: canRightPrevious,
              canNext: canRightNext,
              onPress: onRightPress,
            ),
          ),
        ],
      ),
    );
  }

  Widget _side({
    required String label,
    required Color labelColor,
    required EventDisplayInfo event,
    required VoidCallback? onPrevious,
    required VoidCallback? onNext,
    required bool canPrevious,
    required bool canNext,
    required VoidCallback? onPress,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Row(
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 10,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: labelColor)),
              if (event.badge != null) ...[
                const SizedBox(width: 6),
                event.badge!,
              ],
            ],
          ),
        ),
        Row(
          children: [
            if (showNavigation) _navBtn(BuoyIcons.chevronLeft, canPrevious, onPrevious),
            Expanded(
              child: TouchableOpacity(
                activeOpacity: onPress != null ? 0.8 : 1,
                onTap: onPress,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(event.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 10,
                            color: MacOSColors.textSecondary,
                            fontFamily: 'monospace')),
                    Text(event.timestamp,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11,
                            color: MacOSColors.textPrimary,
                            fontFamily: 'monospace')),
                    Text('(${event.relativeTime})',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 10,
                            color: MacOSColors.textSecondary,
                            fontFamily: 'monospace')),
                  ],
                ),
              ),
            ),
            if (showNavigation) _navBtn(BuoyIcons.chevronRight, canNext, onNext),
          ],
        ),
      ],
    );
  }

  Widget _navBtn(LucideIcon icon, bool enabled, VoidCallback? onTap) {
    final btn = Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: MacOSColors.backgroundCard,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: MacOSColors.borderDefault),
      ),
      child: BuoyGlyph(icon,
          size: 14,
          color:
              enabled ? MacOSColors.textSecondary : MacOSColors.textMuted),
    );
    if (!enabled) return Opacity(opacity: 0.4, child: btn);
    return TouchableOpacity(activeOpacity: 0.7, onTap: onTap, child: btn);
  }
}
