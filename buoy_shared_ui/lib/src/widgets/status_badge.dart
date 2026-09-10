import 'package:flutter/material.dart';
import '../generated/badge_styles.g.dart';
import '../macos_colors.dart';

/// Ports packages/shared/src/ui/components/Badge.tsx — the StatusBadge and
/// CountBadge variants (MethodBadge / TypeBadge / Badge live in badges.dart).
///
/// getBadgeStyles: bg `color15`, border `color40`, borderWidth 1, radius 4
/// (count = 12). Every number and colour comes from [BadgeStyles], generated
/// from the RN style table — see CONTRIBUTING.md "Porting a component".

enum BadgeSize { small, medium, large }

/// getBadgeStyles.sizeStyles — shared by every badge variant.
({double padH, double padV, double fontSize}) badgeSizeStyle(BadgeSize size) =>
    switch (size) {
      BadgeSize.small => (
        padH: BadgeStyles.getBadgeStylesSizeStyles_small_paddingHorizontal,
        padV: BadgeStyles.getBadgeStylesSizeStyles_small_paddingVertical,
        fontSize: BadgeStyles.getBadgeStylesSizeStyles_small_fontSize,
      ),
      BadgeSize.medium => (
        padH: BadgeStyles.getBadgeStylesSizeStyles_medium_paddingHorizontal,
        padV: BadgeStyles.getBadgeStylesSizeStyles_medium_paddingVertical,
        fontSize: BadgeStyles.getBadgeStylesSizeStyles_medium_fontSize,
      ),
      BadgeSize.large => (
        padH: BadgeStyles.getBadgeStylesSizeStyles_large_paddingHorizontal,
        padV: BadgeStyles.getBadgeStylesSizeStyles_large_paddingVertical,
        fontSize: BadgeStyles.getBadgeStylesSizeStyles_large_fontSize,
      ),
    };

const _statusColors = {
  'success': BadgeStyles.STATUS_COLORS_success,
  'error': BadgeStyles.STATUS_COLORS_error,
  'warning': BadgeStyles.STATUS_COLORS_warning,
  'info': BadgeStyles.STATUS_COLORS_info,
  'pending': BadgeStyles.STATUS_COLORS_pending,
  'active': BadgeStyles.STATUS_COLORS_active,
  'inactive': BadgeStyles.STATUS_COLORS_inactive,
  'stale': BadgeStyles.STATUS_COLORS_stale,
  'fetching': BadgeStyles.STATUS_COLORS_fetching,
};

/// StatusBadge — dot + capitalized status label, colored by status name.
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status, this.size = BadgeSize.medium});

  final String status;
  final BadgeSize size;

  @override
  Widget build(BuildContext context) {
    final color = _statusColors[status.toLowerCase()] ?? const Color(0xFF6B7280);
    final s = badgeSizeStyle(size);
    final label = status.isEmpty
        ? status
        : status[0].toUpperCase() + status.substring(1);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: s.padH, vertical: s.padV),
      decoration: BoxDecoration(
        color: color.hexAlpha(0x15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: color.hexAlpha(0x40),
          width: BadgeStyles.getBadgeStylesStyles_container_borderWidth,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: BadgeStyles.styles_statusDot_width,
            height: BadgeStyles.styles_statusDot_height,
            margin: const EdgeInsets.only(
              right: BadgeStyles.styles_statusDot_marginRight,
            ),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: s.fontSize,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// CountBadge — a pill (radius 12) showing a number, `maxCount+` when over.
class CountBadge extends StatelessWidget {
  const CountBadge({
    super.key,
    required this.count,
    this.color = BadgeStyles.STATUS_COLORS_info,
    this.size = BadgeSize.small,
    this.maxCount = 99,
  });

  /// Either an int (clamped to `maxCount+`) or a String (shown as-is).
  final Object count;
  final Color color;
  final BadgeSize size;
  final int maxCount;

  @override
  Widget build(BuildContext context) {
    final s = badgeSizeStyle(size);
    final display = count is int && (count as int) > maxCount
        ? '$maxCount+'
        : '$count';
    return Container(
      // No `alignment:` — see the note on MethodBadge: it would expand the
      // badge to the full available width instead of hugging its number.
      constraints: const BoxConstraints(
        minWidth: BadgeStyles.styles_countBadge_minWidth,
      ),
      padding: EdgeInsets.symmetric(horizontal: s.padH, vertical: s.padV),
      decoration: BoxDecoration(
        color: color.hexAlpha(0x15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.hexAlpha(0x40),
          width: BadgeStyles.getBadgeStylesStyles_container_borderWidth,
        ),
      ),
      child: Text(
        display,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: s.fontSize,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
