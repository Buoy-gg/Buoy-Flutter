import 'package:flutter/material.dart';

import 'package:buoy_core/buoy_core.dart';

import '../game_ui_colors.dart';

/// Ports packages/shared/src/ui/components/StatsCard.tsx — a panel container and
/// its stat-tile / grid / row / divider / section sub-parts. gameUI-themed.
///
/// RN numerics: container bg panel radius 12 padding 16 marginV 8; cardTitle
/// 14/600. Grid: row wrap gap 12 space-between. Item (statCard): flex 1 minWidth
/// 70, bg `background40`, radius 8, padding 12, border `border20`; header row
/// gap 4 marginBottom 6; label uppercase 0.5 secondary w500; value w700.
class StatsCard extends StatelessWidget {
  const StatsCard({super.key, required this.children, this.title});

  final List<Widget> children;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: GameUIColors.panel,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                title!,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: GameUIColors.text,
                ),
              ),
            ),
          ...children,
        ],
      ),
    );
  }
}

enum StatItemSize { small, medium, large }

/// StatsCard.Item — a single stat tile (icon + label + value).
class StatsCardItem extends StatelessWidget {
  const StatsCardItem({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.color,
    this.size = StatItemSize.medium,
  });

  final String label;
  final String value;
  final LucideIcon? icon;

  /// One of the named palette colors, or an explicit [Color].
  final Object? color;
  final StatItemSize size;

  static const _named = {
    'success': GameUIColors.success,
    'error': GameUIColors.error,
    'warning': GameUIColors.warning,
    'info': GameUIColors.primary,
    'primary': GameUIColors.primary,
  };

  @override
  Widget build(BuildContext context) {
    final resolved = color is Color
        ? color as Color
        : (color is String ? _named[color] : null) ?? GameUIColors.primary;
    final (iconSize, valueSize, labelSize) = switch (size) {
      StatItemSize.small => (12.0, 16.0, 10.0),
      StatItemSize.medium => (14.0, 20.0, 11.0),
      StatItemSize.large => (16.0, 24.0, 12.0),
    };

    return Container(
      constraints: const BoxConstraints(minWidth: 70),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: GameUIColors.background.withValues(alpha: 0x40 / 255),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: GameUIColors.border.withValues(alpha: 0x20 / 255)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                if (icon != null) ...[
                  BuoyGlyph(icon, size: iconSize, color: resolved),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: labelSize,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.5,
                      color: GameUIColors.secondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: valueSize,
              fontWeight: FontWeight.w700,
              color: resolved,
            ),
          ),
        ],
      ),
    );
  }
}

/// StatsCard.Grid — a wrapping, evenly-spaced row of tiles.
class StatsCardGrid extends StatelessWidget {
  const StatsCardGrid({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 12,
        runSpacing: 12,
        children: children,
      );
}

/// StatsCard.Row — a space-between label/value row.
class StatsCardRow extends StatelessWidget {
  const StatsCardRow({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: children,
        ),
      );
}

/// StatsCard.Divider — a 1px hairline.
class StatsCardDivider extends StatelessWidget {
  const StatsCardDivider({super.key});
  @override
  Widget build(BuildContext context) => Container(
        height: 1,
        margin: const EdgeInsets.symmetric(vertical: 8),
        color: GameUIColors.border.withValues(alpha: 0x20 / 255),
      );
}

/// StatsCard.Section — a titled sub-section.
class StatsCardSection extends StatelessWidget {
  const StatsCardSection({
    super.key,
    required this.title,
    required this.children,
  });
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                title.toUpperCase(),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  color: GameUIColors.secondary,
                ),
              ),
            ),
            ...children,
          ],
        ),
      );
}
