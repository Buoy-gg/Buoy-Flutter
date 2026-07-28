/// Ports packages/storage/src/storage/components/StorageFilterCards.tsx.
///
/// The browser stats/filter header: a Valid/Missing/Issues status-filter row
/// and an All/Async/MMKV/Secure storage-type pill row. RN numerics preserved:
/// container padding 16 / radius 12 / gap 14; filterChip minHeight 44, value
/// 18/600 monospace, label 9 uppercase; typePill minHeight 32.
library;

import 'package:buoy_core/buoy_core.dart';
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';

enum StorageFilterType { all, missing, issues }

enum StorageTypeFilter { all, async, mmkv, secure }

class StorageFilterCards extends StatelessWidget {
  const StorageFilterCards({
    super.key,
    required this.validCount,
    required this.missingCount,
    required this.issuesCount,
    required this.totalCount,
    required this.asyncCount,
    required this.mmkvCount,
    required this.secureCount,
    required this.activeFilter,
    required this.onFilterChange,
    required this.activeStorageType,
    required this.onStorageTypeChange,
  });

  final int validCount;
  final int missingCount;
  final int issuesCount;
  final int totalCount;
  final int asyncCount;
  final int mmkvCount;
  final int secureCount;
  final StorageFilterType activeFilter;
  final ValueChanged<StorageFilterType> onFilterChange;
  final StorageTypeFilter activeStorageType;
  final ValueChanged<StorageTypeFilter> onStorageTypeChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MacOSColors.backgroundCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MacOSColors.borderDefault.hexAlpha(0x50)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _statusChip(
                'Valid',
                validCount,
                StorageFilterType.all,
                MacOSColors.textPrimary,
                MacOSColors.textPrimary,
              ),
              const SizedBox(width: 10),
              _statusChip(
                'Missing',
                missingCount,
                StorageFilterType.missing,
                MacOSColors.error,
                missingCount > 0 ? MacOSColors.error : MacOSColors.textMuted,
              ),
              const SizedBox(width: 10),
              _statusChip(
                'Issues',
                issuesCount,
                StorageFilterType.issues,
                MacOSColors.warning,
                issuesCount > 0 ? MacOSColors.warning : MacOSColors.textMuted,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _typePill('All Types', totalCount, StorageTypeFilter.all,
                  MacOSColors.textPrimary),
              const SizedBox(width: 8),
              _typePill('Async', asyncCount, StorageTypeFilter.async,
                  MacOSColors.warning),
              const SizedBox(width: 8),
              _typePill(
                  'MMKV', mmkvCount, StorageTypeFilter.mmkv, MacOSColors.info),
              const SizedBox(width: 8),
              _typePill('Secure', secureCount, StorageTypeFilter.secure,
                  MacOSColors.success),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusChip(
    String label,
    int count,
    StorageFilterType filter,
    Color activeColor,
    Color valueColor,
  ) {
    final active = activeFilter == filter;
    final activeBg = filter == StorageFilterType.all
        ? MacOSColors.backgroundHover
        : activeColor.hexAlpha(0x10);
    final activeBorder = filter == StorageFilterType.all
        ? MacOSColors.borderDefault
        : activeColor.hexAlpha(0x30);
    return Expanded(
      child: TouchableOpacity(
        activeOpacity: 0.8,
        onTap: () => onFilterChange(filter),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: active ? activeBg : MacOSColors.backgroundInput.hexAlpha(0x80),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color:
                  active ? activeBorder : MacOSColors.borderDefault.hexAlpha(0x30),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                  height: 20 / 18,
                  color: valueColor,
                ),
              ),
              const SizedBox(height: 3),
              _FilterLabel(text: label),
            ],
          ),
        ),
      ),
    );
  }

  Widget _typePill(
    String label,
    int count,
    StorageTypeFilter type,
    Color activeColor,
  ) {
    final active = activeStorageType == type;
    final activeBg = type == StorageTypeFilter.all
        ? MacOSColors.backgroundHover
        : activeColor.hexAlpha(0x15);
    final activeBorder = type == StorageTypeFilter.all
        ? MacOSColors.borderDefault
        : activeColor.hexAlpha(0x40);
    final color = active ? activeColor : MacOSColors.textMuted;
    return Expanded(
      child: TouchableOpacity(
        activeOpacity: 0.8,
        onTap: () => onStorageTypeChange(type),
        child: Container(
          constraints: const BoxConstraints(minHeight: 32),
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          decoration: BoxDecoration(
            color: active ? activeBg : MacOSColors.backgroundInput.hexAlpha(0x80),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color:
                  active ? activeBorder : MacOSColors.borderDefault.hexAlpha(0x30),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 9,
                  color: active ? activeColor : MacOSColors.textSecondary,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                  height: 14 / 12,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterLabel extends StatelessWidget {
  const _FilterLabel({this.text = ''});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 9,
        color: MacOSColors.textMuted,
        letterSpacing: 0.5,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}
