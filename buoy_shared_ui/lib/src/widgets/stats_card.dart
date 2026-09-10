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
                  // RN's `statLabel` has no `numberOfLines`, so a long label
                  // WRAPS and the tile grows — ellipsizing it here made the
                  // grid 13 pt shorter than its RN twin ("REQUESTS" fits on
                  // two lines there, "REQUE…" on one here).
                  child: Text(
                    label.toUpperCase(),
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

/// StatsCard.Grid — one row of evenly-sized tiles, 12 pt apart.
///
/// RN's `grid` is `flexDirection: row, flexWrap: wrap, gap: 12` over items that
/// are `flex: 1, minWidth: 70`, so the tiles SHARE the row (four of them fit a
/// 370 pt stage: 4x70 + 3x12 = 316) and only wrap once the minimum no longer
/// fits. A Flutter `Wrap` cannot flex its children, so it sized each tile to
/// its own text and stacked them — the parity sheet measured the grid 206 pt
/// taller than its RN twin. `Expanded` is the flex:1 the layout is actually
/// built on; the deviation is that a very long row squashes instead of
/// wrapping. `columns` is a no-op in RN too (all three presets are
/// `justify-content: space-between`), so it is not a parameter here.
class StatsCardGrid extends StatelessWidget {
  const StatsCardGrid({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    // RN's row is `align-items: stretch`, so every tile is as tall as the
    // tallest. A Flutter Row cannot stretch into an unbounded height without
    // being told what that height is — IntrinsicHeight measures it first.
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: <Widget>[
        for (final Widget child in children) Expanded(child: child),
      ],
    ),
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
