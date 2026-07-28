/// Ports packages/env-tools/src/env/components/EnvStatsOverview.tsx — the health
/// header ([CompactRow] with a % badge) plus the ALL / MISSING / ISSUES filter
/// stat-cards.
library;

import 'package:buoy_core/buoy_core.dart';
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';

import '../env_types.dart';

/// EnvStatsOverview EnvFilterType.
enum EnvFilterType { all, missing, issues }

class EnvStatsOverview extends StatelessWidget {
  const EnvStatsOverview({
    super.key,
    required this.stats,
    required this.healthPercentage,
    required this.healthStatus,
    required this.healthColor,
    required this.activeFilter,
    required this.onFilterChange,
  });

  final EnvVarStats stats;
  final int healthPercentage;
  final String healthStatus;
  final Color healthColor;
  final EnvFilterType activeFilter;
  final ValueChanged<EnvFilterType> onFilterChange;

  @override
  Widget build(BuildContext context) {
    final issuesCount = stats.wrongValueCount + stats.wrongTypeCount;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // System status card.
        CompactRow(
          statusDotColor: healthColor,
          statusLabel: 'System',
          statusSublabel: healthStatus.toLowerCase(),
          primaryText: 'Environment Configuration',
          secondaryText: '$healthPercentage% healthy',
          customBadge: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: healthColor.hexAlpha(0x40)),
              color: healthColor.hexAlpha(0x10),
            ),
            child: Text(
              '$healthPercentage%',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
                color: healthColor,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Stats grid — filter cards.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              _statCard(
                value: stats.requiredCount + stats.optionalCount,
                label: 'ALL',
                filter: EnvFilterType.all,
              ),
              const SizedBox(width: 8),
              _statCard(
                value: stats.missingCount,
                label: 'MISSING',
                filter: EnvFilterType.missing,
              ),
              const SizedBox(width: 8),
              _statCard(
                value: issuesCount,
                label: 'ISSUES',
                filter: EnvFilterType.issues,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statCard({
    required int value,
    required String label,
    required EnvFilterType filter,
  }) {
    final active = activeFilter == filter;
    return Expanded(
      child: TouchableOpacity(
        activeOpacity: 0.8,
        onTap: () => onFilterChange(filter),
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.all(12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? BuoyColors.primary.hexAlpha(0x10) : BuoyColors.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active ? BuoyColors.primary : BuoyColors.border,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$value',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                  height: 26 / 22,
                  color: active ? BuoyColors.primary : BuoyColors.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 9,
                  color: active ? BuoyColors.primary : BuoyColors.textMuted,
                  letterSpacing: 0.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
