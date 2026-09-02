/// Ports packages/shared/src/ui/components/EventStepperFooter.tsx — a
/// Previous / "Item N of M" / Next footer for stepping through events. Dumb
/// component. Renders nothing for ≤1 item.
///
/// RN numerics: padH 16 / padTop 12, nav buttons minWidth 100 radius 6, counter
/// 14/700 uppercase monospace, subtitle 11 secondary. RN's `useSafeAreaInsets`
/// bottom inset → `MediaQuery.paddingOf(context).bottom`.
///
/// `variant` (RN, default night): the night bar is near-black glass
/// (rgba(5,5,5,0.92)) with a hairline top border; buttons are the
/// `night.button` plate at radius 15 with accent-ink labels/chevrons, and the
/// counter uses the night text hierarchy. `classic` is the macOS look.
library;

import 'package:flutter/material.dart';

import 'package:buoy_core/buoy_core.dart';

import '../macos_colors.dart';

class EventStepperFooter extends StatelessWidget {
  const EventStepperFooter({
    super.key,
    required this.currentIndex,
    required this.totalItems,
    required this.onPrevious,
    required this.onNext,
    this.itemLabel = 'Event',
    this.subtitle,
    this.absolute = false,
    this.applySafeAreaInset = true,
    this.variant = JsModalVariant.night,
  });

  /// Host tool's chrome variant — night restyles the bar to the night theme.
  final JsModalVariant variant;

  final int currentIndex;
  final int totalItems;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final String itemLabel;
  final String? subtitle;
  final bool absolute;
  final bool applySafeAreaInset;

  @override
  Widget build(BuildContext context) {
    if (totalItems <= 1) return const SizedBox.shrink();

    final night = variant == JsModalVariant.night;
    final isFirst = currentIndex == 0;
    final isLast = currentIndex == totalItems - 1;
    final insetBottom =
        applySafeAreaInset ? MediaQuery.paddingOf(context).bottom : 0.0;

    final footer = Container(
      padding: EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 12 + insetBottom),
      decoration: BoxDecoration(
        color: night
            ? const Color.fromRGBO(5, 5, 5, 0.92)
            : MacOSColors.backgroundBase,
        border: Border(
          top: BorderSide(
            color: night ? NightColor.border : MacOSColors.borderDefault,
          ),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            offset: Offset(0, -2),
            blurRadius: 4,
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _navButton(
            icon: BuoyIcons.chevronLeft,
            label: 'Previous',
            iconLeading: true,
            enabled: !isFirst,
            onTap: onPrevious,
            night: night,
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${itemLabel.toUpperCase()} ${currentIndex + 1} OF $totalItems',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: night ? NightColor.text : MacOSColors.textPrimary,
                    fontFamily: 'monospace'),
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(subtitle!,
                      style: TextStyle(
                          fontSize: 11,
                          color: night
                              ? NightColor.textSecondary
                              : MacOSColors.textSecondary,
                          fontFamily: 'monospace')),
                ),
            ],
          ),
          _navButton(
            icon: BuoyIcons.chevronRight,
            label: 'Next',
            iconLeading: false,
            enabled: !isLast,
            onTap: onNext,
            night: night,
          ),
        ],
      ),
    );

    if (!absolute) return footer;
    return Positioned(left: 0, right: 0, bottom: 0, child: footer);
  }

  Widget _navButton({
    required LucideIcon icon,
    required String label,
    required bool iconLeading,
    required bool enabled,
    required VoidCallback onTap,
    required bool night,
  }) {
    // Night buttons are the plate-with-accent-label style — chevrons match.
    final color = night
        ? (enabled ? NightColor.accent : NightColor.textTertiary)
        : (enabled ? MacOSColors.textPrimary : MacOSColors.textMuted);
    final iconWidget = BuoyGlyph(icon, size: 20, color: color);
    final text = Text(label.toUpperCase(),
        style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
            fontFamily: 'monospace'));
    final button = Container(
      constraints: const BoxConstraints(minWidth: 100),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: night ? NightColor.button : MacOSColors.backgroundCard,
        borderRadius: BorderRadius.circular(night ? 15 : 6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: iconLeading
            ? [iconWidget, const SizedBox(width: 6), text]
            : [text, const SizedBox(width: 6), iconWidget],
      ),
    );
    if (!enabled) return Opacity(opacity: 0.3, child: button);
    return TouchableOpacity(activeOpacity: 0.7, onTap: onTap, child: button);
  }
}
