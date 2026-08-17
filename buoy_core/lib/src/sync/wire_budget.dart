/// Ports packages/shared/src/sync/wireBudget.ts and
/// packages/external-sync/src/emitBudget.ts.
///
/// Size guards for anything a tool puts on the sync wire.
///
/// Every adapter faces the same problem: a snapshot is rebuilt and encoded on
/// the UI isolate ~5x/sec while a dashboard watches, and one fat or
/// unencodable field can either jank that isolate or blow the emit layer's
/// budget — which drops the WHOLE snapshot and leaves the panel stale.
///
/// Two rules make that safe, and both are easy to get subtly wrong, which is
/// why they live here instead of being copied per adapter:
///
///  1. NEVER measure by encoding. `jsonEncode(value).length` is O(payload) and
///     allocates the whole string — an unbounded cost to enforce a 16KB cap,
///     i.e. the protection becomes the jank. Walk with an early abort instead:
///     the cost is O(limit) no matter how big the value, and a string costs a
///     length read rather than a scan.
///
///  2. Only reach for `jsonEncode` when the walk saw something that could
///     actually make it throw. A value straight out of `jsonDecode` — which is
///     what a network body or a stored string is — is a finite tree of plain
///     values and can never throw, so the check is pure waste on the common
///     path.
///
/// Lives in buoy_core rather than buoy_shared_ui because the emit layer
/// ([BuoySyncClient]) is the last backstop and nothing below core may depend on
/// shared_ui. `buoy_shared_ui` re-exports it so tool adapters import it from
/// their usual barrel — the same arrangement as the Buoy icon set.
library;

import 'dart:convert';

/// RN deviation, deliberate: the RN walk reports `sawBigInt`, because a bigint
/// is the one primitive `JSON.stringify` THROWS on (functions and symbols are
/// silently dropped). Dart's `jsonEncode` is far stricter — it throws on
/// anything outside null/num/bool/String/List/Map, on non-finite doubles, and
/// on non-String Map keys — so the flag covers that whole set instead. Same
/// role in [isOverWireBudget]: a hint that the cheap walk is not proof.
class SizeWalk {
  const SizeWalk({
    required this.bytes,
    required this.sawRepeat,
    required this.sawUnencodable,
  });

  /// Bytes counted before the walk finished or passed `limit`.
  final int bytes;

  /// An object/list/map was reached by more than one path. A cycle always
  /// causes this, so `false` PROVES the value is a tree and therefore
  /// cycle-free. (`true` does not prove a cycle — plain structural sharing
  /// sets it too.)
  final bool sawRepeat;

  /// A value `jsonEncode` cannot represent was reached: a non-finite double,
  /// a non-String Map key, or any object that is not a plain collection.
  final bool sawUnencodable;
}

/// Approximate JSON size, aborting as soon as `limit` is passed — O(limit),
/// never O(payload). Returns the bytes counted so far, so one walk can both
/// threshold ("over the per-field cap?") and accumulate ("how much of the
/// snapshot budget is left?").
///
/// Byte weights are copied from the RN walk verbatim so a value measured on
/// Flutter and the same value measured on React Native land on the same side
/// of the same limit.
SizeWalk approxJsonSize(Object? value, int limit) {
  var bytes = 0;
  var sawRepeat = false;
  var sawUnencodable = false;
  final stack = <Object?>[value];

  /// IDENTITY, not equality. A plain `Set<Object>` hashes by `==`, and two
  /// equal-but-distinct maps in a list would collide: the second would be
  /// reported as a repeat and — worse — skipped entirely, so a snapshot full
  /// of similar rows would measure as one row and sail past any budget. The
  /// RN original gets identity semantics for free from `new Set()`.
  final seen = Set<Object>.identity();

  while (stack.isNotEmpty) {
    if (bytes > limit) {
      return SizeWalk(
        bytes: bytes,
        sawRepeat: sawRepeat,
        sawUnencodable: sawUnencodable,
      );
    }
    final v = stack.removeLast();
    if (v == null) {
      bytes += 4;
    } else if (v is String) {
      bytes += v.length + 2; // O(1): length read, no scan
    } else if (v is num) {
      // A non-finite double is a JSON dead end — `jsonEncode` throws on NaN
      // and infinity rather than emitting `null` the way JS does.
      if (v is double && !v.isFinite) sawUnencodable = true;
      bytes += 8;
    } else if (v is bool) {
      bytes += 5;
    } else if (v is List) {
      if (seen.contains(v)) {
        sawRepeat = true;
        continue;
      }
      seen.add(v);
      bytes += 2 + v.length;
      for (var i = 0; i < v.length; i++) {
        stack.add(v[i]);
      }
    } else if (v is Map) {
      if (seen.contains(v)) {
        sawRepeat = true;
        continue;
      }
      seen.add(v);
      bytes += 2;
      v.forEach((key, element) {
        if (key is String) {
          bytes += key.length + 4;
        } else {
          // `jsonEncode` refuses non-String keys outright.
          sawUnencodable = true;
          bytes += 8;
        }
        stack.add(element);
      });
    } else {
      // Sets, lazy Iterables, DateTime, enums, arbitrary instances — every one
      // of them throws without a `toEncodable`, so count nominally and let the
      // confirmation step reject the value.
      sawUnencodable = true;
      bytes += 4;
    }
  }
  return SizeWalk(
    bytes: bytes,
    sawRepeat: sawRepeat,
    sawUnencodable: sawUnencodable,
  );
}

/// Can `jsonEncode` represent this value at all? The expensive, authoritative
/// answer — only call it when [approxJsonSize] says the cheap walk was not
/// conclusive.
bool isJsonEncodable(Object? value) {
  try {
    jsonEncode(value);
    return true;
  } catch (_) {
    return false;
  }
}

/// Should this value be withheld from the wire — too big, or unencodable?
///
/// The ordering is the point: measure with the early-abort walk, and only pay
/// for `jsonEncode` when the walk found a reason it might throw.
bool isOverWireBudget(Object? value, int limit) {
  final walk = approxJsonSize(value, limit);
  if (walk.bytes > limit) return true;
  // A finished walk with no repeated reference and nothing unencodable cannot
  // throw.
  //
  // Not exhaustive even then: a `toJson` that throws is invisible to the walk,
  // so callers handling hostile payloads should still guard their own
  // conversion. The emit-layer guard is the last backstop.
  if (!walk.sawRepeat && !walk.sawUnencodable) return false;
  return !isJsonEncodable(value);
}

/// Max approx bytes for one tool snapshot emit.
const int maxSnapshotEmitBytes = 2 * 1024 * 1024;

/// Max approx bytes for one action-result emit (explicit requests get more).
const int maxActionResultBytes = 8 * 1024 * 1024;
