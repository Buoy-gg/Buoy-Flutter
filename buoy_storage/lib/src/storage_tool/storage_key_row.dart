/// Ports packages/storage/src/storage/components/StorageKeyRow.tsx.
///
/// Expandable browser row on [CompactRow]: status dot + value-type preview,
/// a storage-type pill badge, and an expanded body with Storage/Updates rows,
/// a [DataViewer] for JSON values, and pin/hide actions. Rows from a registered
/// MMKV / SecureStore backend also show their instance (MMKV instance id or
/// keychain service). Select-mode + per-instance row color are dropped (no
/// bulk-select in the Flutter port).
///
/// RN numerics preserved: expandedContainer gap 8; action chips padV 6 / padH
/// 10 / radius 6; viewHistory 10/600 monospace info.
library;

import 'dart:convert';

import 'package:buoy_core/buoy_core.dart';
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';

import 'storage_models.dart';
import 'storage_value_type.dart';

class StorageKeyRow extends StatelessWidget {
  const StorageKeyRow({
    super.key,
    required this.info,
    required this.isExpanded,
    required this.onToggle,
    this.eventCount,
    this.onViewHistory,
    this.onHideKey,
    this.isPinned = false,
    this.onTogglePin,
    this.onEditKey,
    this.onToggleKey,
    this.editBlockedReason,
  });

  final StorageKeyInfo info;
  final bool isExpanded;
  final VoidCallback onToggle;
  final int? eventCount;
  final VoidCallback? onViewHistory;
  final ValueChanged<StorageKeyInfo>? onHideKey;
  final bool isPinned;
  final ValueChanged<String>? onTogglePin;

  /// Open the full-screen editor for this key. Omit to keep the row read-only —
  /// the Edit affordance only appears when a host supplies this.
  ///
  /// The card deliberately doesn't edit anything itself: a tree, six structural
  /// actions and a value field do not fit under a row, which is what this
  /// replaced. See `StorageKeyEditorScreen`.
  final ValueChanged<StorageKeyInfo>? onEditKey;

  /// Flip a boolean straight from the card. A boolean has two states, so an
  /// editor to choose one is a screen whose only job is to offer the value you
  /// didn't pick.
  final ValueChanged<StorageKeyInfo>? onToggleKey;

  /// Why this key can't be edited (read-only instance, buffer, biometric).
  final String? editBlockedReason;

  static ({Color color, String label, String sublabel}) _statusConfig(
    String status,
  ) => switch (status) {
    'required_present' => (
      color: MacOSColors.success,
      label: 'Valid',
      sublabel: 'Required',
    ),
    'required_missing' => (
      color: MacOSColors.error,
      label: 'Missing',
      sublabel: 'Required',
    ),
    'required_wrong_value' => (
      color: MacOSColors.warning,
      label: 'Wrong',
      sublabel: 'Invalid value',
    ),
    'required_wrong_type' => (
      color: MacOSColors.info,
      label: 'Type Error',
      sublabel: 'Wrong type',
    ),
    _ => (color: MacOSColors.debug, label: 'Set', sublabel: 'Optional'),
  };

  static String _formatValue(Object? value) {
    if (value == null) return 'undefined';
    if (value is String) return value;
    try {
      return jsonEncode(value);
    } catch (_) {
      return '$value';
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = _statusConfig(info.status);
    final value = info.value;
    final hasValue = value != null;
    final isBoolean = hasValue && value is bool;
    final typeColor = getStorageTypeColor(info.storageType);
    final typeLabel = getStorageTypeLabel(info.storageType);

    final parsed = parseValue(value);
    final isJsonData = parsed is Map || parsed is List;

    return CompactRow(
      statusDotColor: config.color,
      statusLabel: config.label,
      statusSublabel: config.sublabel,
      primaryText: info.key,
      secondaryText: hasValue
          ? (isBoolean
                ? getValueTypeLabel(value)
                : getValueTypeWithPreview(value))
          : null,
      secondaryAccessory: isBoolean
          ? PillBadge(
              size: PillBadgeSize.sm,
              color: value ? MacOSColors.success : MacOSColors.error,
              child: Text(value ? 'true' : 'false'),
            )
          : null,
      customBadge: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isPinned)
            const Padding(
              padding: EdgeInsets.only(right: 6),
              child: BuoyGlyph(BuoyIcons.pin, size: 12, color: MacOSColors.info),
            ),
          PillBadge(color: typeColor, child: Text(typeLabel)),
        ],
      ),
      showChevron: true,
      isExpanded: isExpanded,
      expandedGlowColor: config.color,
      onPress: onToggle,
      expandedContent: _ExpandedBody(
        info: info,
        typeColor: typeColor,
        typeLabel: typeLabel,
        eventCount: eventCount,
        onViewHistory: onViewHistory,
        onHideKey: onHideKey,
        isPinned: isPinned,
        onTogglePin: onTogglePin,
        isJsonData: isJsonData,
        parsed: parsed,
        formattedValue: _formatValue(value),
        isBoolean: isBoolean,
        onEditKey: onEditKey,
        onToggleKey: onToggleKey,
        editBlockedReason: editBlockedReason,
      ),
    );
  }
}

class _ExpandedBody extends StatelessWidget {
  const _ExpandedBody({
    required this.info,
    required this.typeColor,
    required this.typeLabel,
    required this.eventCount,
    required this.onViewHistory,
    required this.onHideKey,
    required this.isPinned,
    required this.onTogglePin,
    required this.isJsonData,
    required this.parsed,
    required this.formattedValue,
    required this.isBoolean,
    required this.onEditKey,
    required this.onToggleKey,
    required this.editBlockedReason,
  });

  final StorageKeyInfo info;
  final Color typeColor;
  final String typeLabel;
  final int? eventCount;
  final VoidCallback? onViewHistory;
  final ValueChanged<StorageKeyInfo>? onHideKey;
  final bool isPinned;
  final ValueChanged<String>? onTogglePin;
  final bool isJsonData;
  final Object? parsed;
  final String formattedValue;
  final bool isBoolean;
  final ValueChanged<StorageKeyInfo>? onEditKey;
  final ValueChanged<StorageKeyInfo>? onToggleKey;
  final String? editBlockedReason;

  bool get _canEdit => onEditKey != null && editBlockedReason == null;

  @override
  Widget build(BuildContext context) {
    final count = eventCount ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ExpandedInfoRow(
          label: 'Storage',
          child: PillBadge(color: typeColor, child: Text(typeLabel)),
        ),
        // MMKV instance id / SecureStore keychain service, when the row came
        // from a registered backend.
        if (info.instanceId != null) ...[
          const SizedBox(height: 8),
          ExpandedInfoRow(
            label: 'Instance',
            child: PillBadge(color: typeColor, child: Text(info.instanceId!)),
          ),
        ],
        if (count > 0) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExpandedInfoRow(
                label: 'Updates',
                child: PillBadge(
                  color: MacOSColors.warning,
                  child: Text('$count'),
                ),
              ),
              if (count > 1 && onViewHistory != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: TouchableOpacity(
                    activeOpacity: 0.2,
                    onTap: onViewHistory,
                    child: const Text(
                      'view history →',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                        color: MacOSColors.info,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        if (isJsonData)
          Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: MacOSColors.backgroundBase,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: MacOSColors.borderDefault),
            ),
            child: DataViewer(
              data: parsed,
              showTypeFilter: true,
              initialExpanded: true,
            ),
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(
                width: 70,
                child: Text(
                  'Value:',
                  style: TextStyle(
                    fontSize: 10,
                    color: MacOSColors.textMuted,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  formattedValue,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: MacOSColors.textSecondary,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
        if (editBlockedReason case final reason?) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(
                width: 70,
                child: Text(
                  'Edit:',
                  style: TextStyle(
                    fontSize: 10,
                    color: MacOSColors.textMuted,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  reason,
                  style: const TextStyle(
                    fontSize: 11,
                    color: MacOSColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
        // Three actions, and only one of them edits. Edit is the primary and it
        // leads somewhere; pin and hide only change how this list reads.
        if (onTogglePin != null || onHideKey != null || _canEdit) ...[
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (_canEdit)
                _ActionChip(
                  icon: BuoyIcons.edit3,
                  label: isBoolean && onToggleKey != null ? 'Toggle' : 'Edit',
                  color: MacOSColors.success,
                  filled: true,
                  onTap: () => isBoolean && onToggleKey != null
                      ? onToggleKey!(info)
                      : onEditKey!(info),
                ),
              if (onTogglePin != null)
                _ActionChip(
                  icon: BuoyIcons.pin,
                  label: isPinned ? 'Unpin' : 'Pin to top',
                  color: MacOSColors.info,
                  active: isPinned,
                  onTap: () => onTogglePin!(info.key),
                ),
              if (onHideKey != null)
                _ActionChip(
                  icon: BuoyIcons.eyeOff,
                  label: 'Hide from list',
                  color: MacOSColors.warning,
                  onTap: () => onHideKey!(info),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.active = false,
    this.filled = false,
  });

  final LucideIcon icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool active;

  /// Filled, and first — the one action in this row that changes anything
  /// (RN `editButton`: padV 8 / padH 14 / radius 8, 12px bold on the base bg).
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final foreground = filled ? MacOSColors.backgroundBase : color;
    return TouchableOpacity(
      activeOpacity: 0.2,
      onTap: onTap,
      child: Container(
        padding: filled
            ? const EdgeInsets.symmetric(vertical: 8, horizontal: 14)
            : const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
        decoration: BoxDecoration(
          color: filled
              ? color
              : (active
                    ? MacOSColors.info.hexAlpha(0x15)
                    : MacOSColors.backgroundCard),
          borderRadius: BorderRadius.circular(filled ? 8 : 6),
          border: filled
              ? null
              : Border.all(
                  color: active
                      ? MacOSColors.info.hexAlpha(0x44)
                      : MacOSColors.borderDefault,
                ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            BuoyGlyph(icon, size: filled ? 13 : 12, color: foreground),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: filled ? 12 : 11,
                fontWeight: filled ? FontWeight.w700 : FontWeight.w600,
                fontFamily: filled ? null : 'monospace',
                color: foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
