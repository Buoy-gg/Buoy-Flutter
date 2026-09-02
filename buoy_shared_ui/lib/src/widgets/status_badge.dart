import 'package:flutter/material.dart';
import 'package:buoy_core/buoy_core.dart';

import '../macos_colors.dart';

/// Ports packages/shared/src/ui/components/Badge.tsx — the StatusBadge and
/// CountBadge variants (the ones the assignment calls for; MethodBadge already
/// lives in badges.dart, TypeBadge/Badge deferred).
///
/// getBadgeStyles: bg `color15`, border `color40`, borderWidth 1, radius 4
/// (count = 12). Sizes — small: padH 6 / padV 2 / font 11; medium: 8 / 3 / 12;
/// large: 10 / 4 / 14. Colors from buoyColors.

enum BadgeSize { small, medium, large }

({double padH, double padV, double fontSize}) _sizeStyle(BadgeSize size) =>
    switch (size) {
      BadgeSize.small => (padH: 6, padV: 2, fontSize: 11),
      BadgeSize.medium => (padH: 8, padV: 3, fontSize: 12),
      BadgeSize.large => (padH: 10, padV: 4, fontSize: 14),
    };

const _statusColors = {
  'success': BuoyColors.success,
  'error': BuoyColors.error,
  'warning': BuoyColors.warning,
  'info': BuoyColors.primary,
  'pending': NightColor.textSecondary,
  'active': BuoyColors.success,
  'inactive': NightColor.textTertiary,
  'stale': BuoyColors.warning,
  'fetching': BuoyColors.primary,
};

/// StatusBadge — dot + capitalized status label, colored by status name.
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status, this.size = BadgeSize.medium});

  final String status;
  final BadgeSize size;

  @override
  Widget build(BuildContext context) {
    final color = _statusColors[status.toLowerCase()] ?? const Color(0xFF6B7280);
    final s = _sizeStyle(size);
    final label = status.isEmpty
        ? status
        : status[0].toUpperCase() + status.substring(1);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: s.padH, vertical: s.padV),
      decoration: BoxDecoration(
        color: color.hexAlpha(0x15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.hexAlpha(0x40)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(right: 4),
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
    this.color = BuoyColors.primary,
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
    final s = _sizeStyle(size);
    final display = count is int && (count as int) > maxCount
        ? '$maxCount+'
        : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      alignment: Alignment.center,
      padding: EdgeInsets.symmetric(horizontal: s.padH, vertical: s.padV),
      decoration: BoxDecoration(
        color: color.hexAlpha(0x15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.hexAlpha(0x40)),
      ),
      child: Text(
        display,
        style: TextStyle(
          fontSize: s.fontSize,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
