/// Ports packages/jotai/src/jotai/components/JotaiAtomChangeItem.tsx — the
/// compact Events-tab row for one provider change. Status dot in the provider's
/// color, prev→next sublabel, category badge (+ Zap when the value changed),
/// live RelativeTime.
library;

import 'package:flutter/material.dart';

import 'package:buoy_shared_ui/buoy_shared_ui.dart';

import '../riverpod_state_store.dart';
import '../riverpod_types.dart';

String _formatCompact(Object? value, [int maxLen = 20]) {
  if (value == null) return 'null';
  if (value is bool) return value.toString();
  if (value is num) return value.toString();
  if (value is String) {
    final truncated =
        value.length > maxLen ? '${value.substring(0, maxLen - 1)}…' : value;
    return '"$truncated"';
  }
  if (value is List) {
    return value.isEmpty
        ? '[]'
        : '[${value.length} item${value.length == 1 ? "" : "s"}]';
  }
  if (value is Map) {
    if (value.isEmpty) return '{}';
    final keys = value.keys.map((k) => '$k').toList();
    return '{${keys.take(2).join(", ")}${keys.length > 2 ? "…" : ""}}';
  }
  final s = value.toString();
  return s.length > maxLen ? s.substring(0, maxLen) : s;
}

class ProviderChangeItem extends StatelessWidget {
  const ProviderChangeItem({
    super.key,
    required this.change,
    required this.onPress,
  });

  final ProviderChange change;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final statusColor = change.category == ProviderChangeCategory.initial
        ? BuoyColors.textMuted
        : Color(riverpodStateStore.providerColor(change.providerLabel));
    final statusLabel = change.category == ProviderChangeCategory.initial
        ? 'Initial'
        : (change.providerLabel.isEmpty
            ? change.providerLabel
            : change.providerLabel[0].toUpperCase() +
                change.providerLabel.substring(1));
    final sublabel = change.hasValueChange
        ? '${_formatCompact(change.prevValue)} → ${_formatCompact(change.nextValue)}'
        : 'no change';
    final primaryText = _primaryText();
    final badgeText = providerCategoryBadge(change.category);

    final Widget? customBadge = change.hasValueChange
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(badgeText,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                      color: statusColor)),
              const SizedBox(width: 4),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: BuoyGlyph(BuoyIcons.zap, size: 12, color: BuoyColors.warning),
              ),
            ],
          )
        : null;

    return CompactRow(
      statusDotColor: statusColor,
      statusLabel: statusLabel,
      statusSublabel: sublabel,
      primaryText: primaryText,
      bottomRightText: RelativeTime(
        timestamp: change.timestamp,
        style: const TextStyle(
            fontSize: 9, color: BuoyColors.textMuted, fontFamily: 'monospace'),
      ),
      customBadge: customBadge,
      badgeText: customBadge != null ? null : badgeText,
      badgeColor: statusColor,
      showChevron: true,
      onPress: onPress,
    );
  }

  String _primaryText() {
    if (change.changedKeys.isNotEmpty && change.changedKeys.length <= 3) {
      return change.changedKeys.join(', ');
    }
    if (change.changedKeys.length > 3) {
      return '${change.changedKeys.take(2).join(", ")} +${change.changedKeys.length - 2}';
    }
    return change.valuePreview.isEmpty ? 'provider()' : change.valuePreview;
  }
}
