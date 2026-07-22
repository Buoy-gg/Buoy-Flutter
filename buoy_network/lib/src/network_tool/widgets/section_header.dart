import 'package:flutter/material.dart';

import '../macos_colors.dart';

/// Port of shared-ui's SectionHeader (icon + title + count badge + actions)
/// used by DynamicFilterView's section cards.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    this.icon,
    this.iconColor = BuoyColors.primary,
    required this.title,
    this.badgeCount,
    this.badgeColor = BuoyColors.primary,
    this.actions,
  });

  final IconData? icon;
  final Color iconColor;
  final String title;
  final int? badgeCount;
  final Color badgeColor;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 40),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: BuoyColors.base,
      child: Row(
        children: [
          if (icon != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(icon, size: 12, color: iconColor),
            ),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: BuoyColors.text,
              ),
            ),
          ),
          if (badgeCount != null)
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: badgeColor.hexAlpha(0x15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: badgeColor.hexAlpha(0x33)),
              ),
              child: Text(
                '$badgeCount',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: badgeColor,
                ),
              ),
            ),
          if (actions != null)
            Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: actions!),
        ],
      ),
    );
  }
}
