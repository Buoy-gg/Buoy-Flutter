import 'package:flutter/material.dart';

import 'package:buoy_core/buoy_core.dart';

import '../macos_colors.dart';

/// Ports packages/shared/src/ui/components/CompactFilterChips.tsx — horizontally
/// scrolling chip groups (each group a titled row of toggle chips with optional
/// icon + count). macOS-themed.
///
/// RN numerics: chip height 24, padH 8 / padV 4, radius 4, border default, bg
/// card; active bg infoBackground + border `info40`. Label 10/500 secondary;
/// active info 600. Count 9/600 muted (bg hover, padH 4 / padV 1, radius 3);
/// active bg `info20` color info. Group title 9/600 muted uppercase, padH 4.

class FilterChip {
  const FilterChip({
    required this.id,
    required this.label,
    this.count,
    this.icon,
    this.color,
    this.isActive = false,
    this.value,
  });

  final String id;
  final String label;
  final int? count;
  final LucideIcon? icon;
  final Color? color;
  final bool isActive;
  final Object? value;
}

class FilterChipGroup {
  const FilterChipGroup({
    required this.id,
    required this.title,
    required this.chips,
    this.multiSelect = false,
  });

  final String id;
  final String title;
  final List<FilterChip> chips;
  final bool multiSelect;
}

class CompactFilterChips extends StatelessWidget {
  const CompactFilterChips({
    super.key,
    required this.groups,
    required this.onChipPress,
  });

  final List<FilterChipGroup> groups;
  final void Function(String groupId, String chipId, Object? value) onChipPress;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < groups.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
            child: _group(groups[i]),
          ),
      ],
    );
  }

  Widget _group(FilterChipGroup group) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            group.title.toUpperCase(),
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: MacOSColors.textMuted,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                for (final chip in group.chips)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: _chip(group.id, chip),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _chip(String groupId, FilterChip chip) {
    final active = chip.isActive;
    final accent = chip.color;
    final bg = active
        ? (accent != null
            ? accent.hexAlpha(0x15)
            : MacOSColors.infoBackground)
        : MacOSColors.backgroundCard;
    final borderColor = active
        ? (accent ?? MacOSColors.info).hexAlpha(0x40)
        : MacOSColors.borderDefault;
    final labelColor = active
        ? (accent ?? MacOSColors.info)
        : MacOSColors.textSecondary;
    final iconColor = active
        ? (accent ?? MacOSColors.info)
        : MacOSColors.textMuted;

    return TouchableOpacity(
      activeOpacity: 0.2,
      onTap: () => onChipPress(groupId, chip.id, chip.value),
      child: Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (chip.icon != null) ...[
              BuoyGlyph(chip.icon, size: 10, color: iconColor),
              const SizedBox(width: 4),
            ],
            Text(
              chip.label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                color: labelColor,
              ),
            ),
            if (chip.count != null) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: active
                      ? (accent ?? MacOSColors.info).hexAlpha(0x20)
                      : MacOSColors.backgroundHover,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  '${chip.count}',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: active
                        ? (accent ?? MacOSColors.info)
                        : MacOSColors.textMuted,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
