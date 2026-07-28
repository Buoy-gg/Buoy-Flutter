/// Ports packages/storage/src/storage/utils/valueType.ts and
/// storageQueryUtils.ts + StorageEventCard.getValueType (parseValue-based).
library;

import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/widgets.dart';

/// RN `getValueType` (StorageEventCard/StorageModalWithTabs): the type of a
/// value AFTER `parseValue` (so a stringified JSON object reports 'object').
String getValueType(Object? value) {
  final parsed = parseValue(value);
  if (parsed == null) return 'null';
  if (parsed is List) return 'array';
  if (parsed is bool) return 'boolean';
  if (parsed is num) return 'number';
  if (parsed is String) return 'string';
  if (parsed is Map) return 'object';
  return 'undefined';
}

/// RN `getValueTypeLabel` (valueType.ts): type of the RAW value (no parse).
String getValueTypeLabel(Object? value) {
  if (value == null) return 'null';
  if (value is List) return 'array';
  if (value is Map) return 'object';
  if (value is bool) return 'boolean';
  if (value is num) return 'number';
  if (value is String) return 'string';
  return 'unknown';
}

const int _maxInlinePreview = 40;

/// RN `getValuePreview`: short preview for inline display, or null when too
/// large/complex (long strings, objects, arrays).
String? getValuePreview(Object? value) {
  if (value is bool) return value ? 'true' : 'false';
  if (value is num) return value.isFinite ? '$value' : null;
  if (value is String) {
    if (value.isEmpty) return '""';
    if (value.length > _maxInlinePreview) return null;
    return '"${value.replaceAll(RegExp(r'\s+'), ' ')}"';
  }
  return null;
}

/// RN `getValueTypeWithPreview`: e.g. `boolean · true`, `string · "hi"`.
String getValueTypeWithPreview(Object? value) {
  final label = getValueTypeLabel(value);
  final preview = getValuePreview(value);
  return preview != null ? '$label · $preview' : label;
}

/// Storage type ('async'|'mmkv'|'secure') → label (RN `getStorageTypeLabel`).
String getStorageTypeLabel(String storageType) => switch (storageType) {
  'mmkv' => 'MMKV',
  'async' => 'Async',
  'secure' => 'Secure',
  _ => storageType,
};

/// Storage type → color (RN `getStorageTypeColor`: info/warning/success).
Color getStorageTypeColor(String storageType) => switch (storageType) {
  'mmkv' => MacOSColors.info,
  'async' => MacOSColors.warning,
  'secure' => MacOSColors.success,
  _ => MacOSColors.textSecondary,
};
