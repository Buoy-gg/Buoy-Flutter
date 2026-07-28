/// Ports packages/events/src/components/UnifiedEventFilters.tsx.
///
/// Horizontal bar of toggleable per-source badges (enabled first). Layout:
/// [subscriber_count] • dot Label [event_count].
library;

import 'package:buoy_core/buoy_core.dart';
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';

import 'source_config.dart';

/// Ports `SourceInfo`.
class SourceInfo {
  const SourceInfo({
    required this.source,
    required this.label,
    required this.color,
    required this.count,
    required this.enabled,
    this.subscriberCount,
  });

  /// Display source (one of [kAllDisplaySources]).
  final String source;
  final String label;
  final Color color;
  final int count;
  final bool enabled;

  /// Null when the source has no subscriber tracking (no left count badge).
  final int? subscriberCount;
}

class UnifiedEventFilters extends StatelessWidget {
  const UnifiedEventFilters({
    super.key,
    required this.availableSources,
    required this.onToggleSource,
    required this.totalCount,
    required this.filteredCount,
  });

  final List<SourceInfo> availableSources;
  final ValueChanged<String> onToggleSource;
  final int totalCount;
  final int filteredCount;

  @override
  Widget build(BuildContext context) {
    if (availableSources.isEmpty) return const SizedBox.shrink();

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: BuoyColors.base,
        border: Border(bottom: BorderSide(color: BuoyColors.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  for (final source in availableSources) ...[
                    _badge(source),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            if (filteredCount < totalCount)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Showing $filteredCount of $totalCount',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11,
                    color: BuoyColors.textMuted,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _badge(SourceInfo source) {
    final enabled = source.enabled;
    final subCount = source.subscriberCount;
    final hasTracking = subCount != null;
    final eventCount = source.count;

    return TouchableOpacity(
      activeOpacity: 0.7,
      onTap: () => onToggleSource(source.source),
      child: Opacity(
        opacity: enabled ? 1.0 : 0.5,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          decoration: BoxDecoration(
            color: BuoyColors.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: enabled ? source.color.hexAlpha(0x50) : BuoyColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasTracking) ...[
                _countBadge(
                  '$subCount',
                  bg: enabled
                      ? (subCount > 0
                          ? source.color.hexAlpha(0x25)
                          : BuoyColors.textMuted.hexAlpha(0x20))
                      : BuoyColors.textMuted.hexAlpha(0x15),
                  fg: enabled
                      ? (subCount > 0 ? source.color : BuoyColors.textMuted)
                      : BuoyColors.textMuted.hexAlpha(0x60),
                ),
                const SizedBox(width: 6),
              ],
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: enabled
                      ? source.color
                      : BuoyColors.textMuted.hexAlpha(0x40),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                source.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'monospace',
                  color: enabled
                      ? BuoyColors.text
                      : BuoyColors.textMuted.hexAlpha(0x70),
                ),
              ),
              const SizedBox(width: 6),
              _countBadge(
                '$eventCount',
                bg: enabled
                    ? (eventCount > 0
                        ? source.color.hexAlpha(0x20)
                        : BuoyColors.textMuted.hexAlpha(0x15))
                    : BuoyColors.textMuted.hexAlpha(0x10),
                fg: enabled
                    ? (eventCount > 0
                        ? source.color
                        : BuoyColors.textMuted.hexAlpha(0x80))
                    : BuoyColors.textMuted.hexAlpha(0x50),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _countBadge(String text, {required Color bg, required Color fg}) {
    return Container(
      constraints: const BoxConstraints(minWidth: 18),
      height: 18,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          fontFamily: 'monospace',
          fontFeatures: const [FontFeature.tabularFigures()],
          color: fg,
        ),
      ),
    );
  }
}
