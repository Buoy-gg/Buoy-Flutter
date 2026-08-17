/// Ports packages/console/src/store/sanitize.ts.
///
/// Deep-convert captured console arguments into JSON-safe values. Captured args
/// can hold objects/lists/functions/circular references; both the external-sync
/// snapshot (device → desktop) and the preserve-log persistence need plain JSON,
/// so this produces a structural copy (Maps/Lists preserved so they stay
/// expandable on the dashboard) with cycles broken.
///
/// Strings are capped: a single `print` of a multi-MB payload (API dump,
/// base64, …) would otherwise ride every snapshot uncapped and drop the whole
/// console panel at the 2MB emit budget.
///
/// RN limits, mirrored exactly: MAX_DEPTH 6, MAX_ARRAY 100, MAX_KEYS 100.
library;

const int _maxDepth = 6;
const int _maxArray = 100;
const int _maxKeys = 100;

/// Max chars of one string on the wire / in the persisted buffer.
const int snapshotStringLimit = 2 * 1024;

/// RN `capString`.
String capString(String value, [int limit = snapshotStringLimit]) {
  if (value.length <= limit) return value;
  return '${value.substring(0, limit)}… [${value.length - limit} more]';
}

Object? _sanitizeValue(Object? value, int depth, Set<Object> seen) {
  if (value == null) return null;
  if (value is String) return capString(value);
  if (value is bool) return value;
  if (value is num) {
    // RN: non-finite numbers serialize to their String form.
    if (value is double && (value.isNaN || value.isInfinite)) {
      return value.toString();
    }
    return value;
  }

  if (value is Error || value is Exception) {
    // Best-effort structural copy of an error (RN keeps name/message/stack).
    final stack = value is Error ? value.stackTrace?.toString() : null;
    return {
      'name': value.runtimeType.toString(),
      'message': value.toString(),
      'stack': ?stack,
    };
  }

  if (depth >= _maxDepth) {
    return value is List ? '[Array]' : '{…}';
  }

  if (seen.contains(value)) return '[Circular]';

  if (value is List) {
    seen.add(value);
    try {
      final out = <Object?>[
        for (final v in value.take(_maxArray)) _sanitizeValue(v, depth + 1, seen),
      ];
      if (value.length > _maxArray) {
        out.add('… ${value.length - _maxArray} more');
      }
      return out;
    } finally {
      seen.remove(value);
    }
  }

  if (value is Map) {
    seen.add(value);
    try {
      final out = <String, Object?>{};
      var count = 0;
      for (final entry in value.entries) {
        if (count >= _maxKeys) break;
        count++;
        final key = entry.key.toString();
        try {
          out[key] = _sanitizeValue(entry.value, depth + 1, seen);
        } catch (_) {
          out[key] = '[Unserializable]';
        }
      }
      return out;
    } finally {
      seen.remove(value);
    }
  }

  // Functions, symbols, and anything else → stringify (RN's ƒ / toString path).
  if (value is Function) return 'ƒ (anonymous)';
  return value.toString();
}

/// Deep-sanitize a list of console arguments into JSON-safe values.
List<Object?> sanitizeArgs(List<Object?> args) {
  // IDENTITY, not equality — the cycle check asks "am I already inside THIS
  // object", and `WeakSet` gives RN that for free. A `==`-keyed Set would call
  // two equal-but-distinct maps in a list the same object and render the
  // second as `[Circular]`, which is wrong and looks like data loss.
  final seen = Set<Object>.identity();
  return [for (final arg in args) _sanitizeValue(arg, 0, seen)];
}
