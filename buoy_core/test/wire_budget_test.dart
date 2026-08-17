/// Parity + cost tests for `src/sync/wire_budget.dart`.
///
/// Mirrors the RN guarantees asserted across the sync-adapter suites in
/// packages/*/src/**/__tests__. The cost tests are the important half: the
/// guard exists because the PREVIOUS guard measured by encoding, which made
/// the protection itself the freeze it was added to prevent. They assert the
/// mechanism (was `jsonEncode` reached at all?), never wall-clock — a timing
/// assertion would flake on CI and prove nothing about the ordering.
library;

import 'dart:convert';

import 'package:buoy_core/buoy_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// A value that counts how many times `jsonEncode` tried to serialize it.
/// Encodable, so it never changes an outcome — it only records whether the
/// expensive path was taken.
class _CountingValue {
  _CountingValue(this.payload);
  final Object? payload;
  int encodeAttempts = 0;

  Object? toJson() {
    encodeAttempts++;
    return payload;
  }
}

void main() {
  group('approxJsonSize', () {
    test('aborts early instead of walking the whole payload', () {
      // 50k distinct nested maps. Measured against a 100-byte limit, the walk
      // must stop at the top-level list; measured against an effectively
      // infinite one it descends into all 50k children.
      final huge = <Object?>[
        for (var i = 0; i < 50000; i++) {'k$i': 'v$i'},
      ];
      final aborted = approxJsonSize(huge, 100).bytes;
      final complete = approxJsonSize(huge, 1 << 40).bytes;

      expect(aborted, greaterThan(100));
      // A list charges 1 byte per element up front (RN parity: `2 + v.length`),
      // so the abort still reports ~50KB — but it never touched a child, which
      // is what O(limit) means here.
      expect(aborted, lessThan(complete ~/ 10));
    });

    test('a giant string costs a length read, not a scan', () {
      final walk = approxJsonSize('x' * 5000000, 16 * 1024);
      expect(walk.bytes, 5000002);
      expect(walk.sawRepeat, isFalse);
      expect(walk.sawUnencodable, isFalse);
    });

    test('byte weights match the RN walk', () {
      expect(approxJsonSize(null, 999).bytes, 4);
      expect(approxJsonSize('ab', 999).bytes, 4); // len + 2
      expect(approxJsonSize(1, 999).bytes, 8);
      expect(approxJsonSize(true, 999).bytes, 5);
      // list: 2 + length, plus each element
      expect(approxJsonSize([1, 2], 999).bytes, 2 + 2 + 8 + 8);
      // map: 2, plus key.length + 4 per key, plus each value
      expect(approxJsonSize({'a': 1}, 999).bytes, 2 + (1 + 4) + 8);
    });

    test('structural sharing sets sawRepeat but is NOT a cycle', () {
      final user = {'id': 1};
      final walk = approxJsonSize({'user': user, 'currentUser': user}, 99999);
      expect(walk.sawRepeat, isTrue);
      // The whole point of the RN fix: this is ordinary and encodes fine.
      expect(isJsonEncodable({'user': user, 'currentUser': user}), isTrue);
    });

    test('a cycle sets sawRepeat and terminates', () {
      final cyclic = <String, Object?>{'name': 'root'};
      cyclic['self'] = cyclic;
      final walk = approxJsonSize(cyclic, 99999);
      expect(walk.sawRepeat, isTrue);
      expect(isJsonEncodable(cyclic), isFalse);
    });

    test('equal-but-distinct siblings are counted separately', () {
      // The Dart-specific trap: a `Set` keyed by `==` would treat these as one
      // value, skip the second, and under-report a list of similar rows.
      final rows = [
        {'a': 'xxxxxxxxxx'},
        {'a': 'xxxxxxxxxx'},
      ];
      final one = approxJsonSize([rows[0]], 99999).bytes;
      final two = approxJsonSize(rows, 99999).bytes;
      expect(two, greaterThan(one));
      expect(approxJsonSize(rows, 99999).sawRepeat, isFalse);
    });

    test('flags what jsonEncode actually throws on', () {
      expect(approxJsonSize(double.nan, 999).sawUnencodable, isTrue);
      expect(approxJsonSize(double.infinity, 999).sawUnencodable, isTrue);
      expect(approxJsonSize({1: 'a'}, 999).sawUnencodable, isTrue);
      expect(approxJsonSize({'s'}, 999).sawUnencodable, isTrue);
      expect(approxJsonSize(DateTime(2026), 999).sawUnencodable, isTrue);
      // ...and not on values that encode fine.
      expect(approxJsonSize(1.5, 999).sawUnencodable, isFalse);
      expect(approxJsonSize({'a': null}, 999).sawUnencodable, isFalse);
    });
  });

  group('isOverWireBudget', () {
    test('over the limit by size alone', () {
      expect(isOverWireBudget('x' * 20000, 16 * 1024), isTrue);
    });

    test('under the limit and plainly encodable', () {
      expect(isOverWireBudget({'ok': true}, 16 * 1024), isFalse);
    });

    test('withholds a cyclic value that is under the size limit', () {
      final cyclic = <String, Object?>{};
      cyclic['self'] = cyclic;
      expect(isOverWireBudget(cyclic, 16 * 1024), isTrue);
    });

    test('ALLOWS structural sharing under the limit', () {
      // The events regression this fix was written for: a shared reference is
      // not a cycle, and discarding the payload threw away the whole event.
      final shared = {'id': 1};
      expect(
        isOverWireBudget({'a': shared, 'b': shared}, 16 * 1024),
        isFalse,
      );
    });

    test('withholds NaN, which would throw at the encoder', () {
      expect(isOverWireBudget({'n': double.nan}, 16 * 1024), isTrue);
    });

    group('cost ordering — the reason this helper exists', () {
      test('a plain tree is conclusive on the walk alone', () {
        // No probe is possible here — anything observable would itself be an
        // unknown object and force the confirmation step. What IS assertable
        // is that the walk reaches a verdict with neither flag set, which is
        // exactly the condition under which the encoder is skipped.
        final walk = approxJsonSize({'plain': 'value'}, 16 * 1024);
        expect(walk.sawRepeat, isFalse);
        expect(walk.sawUnencodable, isFalse);
        expect(isOverWireBudget({'plain': 'value'}, 16 * 1024), isFalse);
      });

      test('does NOT encode a huge value — it aborts on size first', () {
        final probe = _CountingValue('x' * 100);
        final huge = <Object?>['x' * 50000, probe];
        expect(isOverWireBudget(huge, 16 * 1024), isTrue);
        // Never reached the encoder: size alone was decisive.
        expect(probe.encodeAttempts, 0);
      });

      test('DOES encode only when the walk was inconclusive', () {
        final shared = {'id': 1};
        final probe = _CountingValue({'a': shared, 'b': shared});
        // sawUnencodable (unknown object) forces the confirmation step.
        isOverWireBudget(probe, 16 * 1024);
        expect(probe.encodeAttempts, 1);
      });

      test('reverting the ordering would be caught here', () {
        // If isOverWireBudget encoded FIRST (the bug this replaced), this
        // 5MB string would be fully serialized to enforce a 16KB cap.
        final probe = _CountingValue('x' * 5000000);
        final walk = approxJsonSize(probe.payload, 16 * 1024);
        expect(walk.bytes, greaterThan(16 * 1024));
        expect(probe.encodeAttempts, 0);
      });
    });
  });

  group('emit budgets', () {
    test('match the RN constants', () {
      expect(maxSnapshotEmitBytes, 2 * 1024 * 1024);
      expect(maxActionResultBytes, 8 * 1024 * 1024);
    });

    test('a realistic snapshot sits well under the snapshot budget', () {
      final snapshot = {
        'events': [
          for (var i = 0; i < 500; i++)
            {'id': '$i', 'key': 'user.profile.$i', 'action': 'setItem'},
        ],
      };
      final walk = approxJsonSize(snapshot, maxSnapshotEmitBytes);
      expect(walk.bytes, lessThan(maxSnapshotEmitBytes));
      expect(jsonEncode(snapshot), isNotEmpty);
    });
  });
}
