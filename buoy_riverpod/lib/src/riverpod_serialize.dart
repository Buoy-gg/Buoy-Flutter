/// Safe value serialization for arbitrary Dart provider values.
///
/// The Jotai tool feeds `parseValue(value)` (a JSON round-trip that drops
/// functions) into its DataViewer/diff. Riverpod provider values are arbitrary
/// Dart objects, so this converts them into JSON-compatible structures
/// (Map/List/primitives) with depth/size caps mirroring RN's `displayValue`
/// limits — trying `.toJson()` first, then primitives, then `toString()`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart'
    show AsyncValue, AsyncError, AsyncLoading;

/// Max nesting depth before a collection is summarized (RN displayValue cap).
const int _maxDepth = 6;

/// Max items serialized per collection level.
const int _maxItems = 200;

/// Max characters for a single string leaf.
const int _maxStringLength = 5000;

/// Convert [value] to a JSON-safe structure for the data/diff viewers.
Object? serializeValue(Object? value, [int depth = 0]) {
  if (value == null) return null;
  if (value is String) {
    return value.length > _maxStringLength
        ? '${value.substring(0, _maxStringLength)}… (${value.length} chars)'
        : value;
  }
  if (value is num || value is bool) return value;

  // AsyncValue (FutureProvider / AsyncNotifier / StreamProvider — the bulk of
  // Riverpod state) has no toJson and stringifies opaquely, so unwrap it into a
  // {state, value?, error?} map. This makes async providers browsable in the
  // DataViewer and gives the diff a meaningful loading→data tree.
  if (value is AsyncValue) {
    final err = value.error;
    final val = value.value;
    final out = <String, Object?>{
      'state': value is AsyncLoading
          ? 'loading'
          : value is AsyncError
              ? 'error'
              : 'data',
    };
    if (val != null) out['value'] = serializeValue(val, depth + 1);
    if (err != null) out['error'] = err.toString();
    return out;
  }

  if (depth >= _maxDepth) return _summary(value);

  if (value is Map) {
    final out = <String, Object?>{};
    var count = 0;
    for (final entry in value.entries) {
      if (count >= _maxItems) {
        out['…'] = '${value.length - _maxItems} more';
        break;
      }
      out['${entry.key}'] = serializeValue(entry.value, depth + 1);
      count++;
    }
    return out;
  }

  if (value is Iterable) {
    final out = <Object?>[];
    var count = 0;
    for (final item in value) {
      if (count >= _maxItems) {
        out.add('… ${value.length - _maxItems} more');
        break;
      }
      out.add(serializeValue(item, depth + 1));
      count++;
    }
    return out;
  }

  // Try a toJson() convention (freezed/json_serializable models, etc.).
  try {
    final dynamic dyn = value;
    final json = dyn.toJson();
    if (json is Map || json is List) return serializeValue(json, depth + 1);
  } catch (_) {
    // Not a toJson-able object — fall through.
  }

  return value.toString();
}

String _summary(Object? value) {
  if (value is Map) return '{ ${value.length} keys }';
  if (value is Iterable) return '[ ${value.length} items ]';
  return value.toString();
}
