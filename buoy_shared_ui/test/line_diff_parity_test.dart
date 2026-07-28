// Parity tests for computeLineDiff against the RN `lineDiff.ts` algorithm's
// expected output. These hard-code the results the RN implementation produces
// for the same inputs (2-space JSON lines, Myers O(ND) line matcher over keys
// that ignore the trailing comma, word-level LCS).
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// Concatenate a line's word-diff content back into its raw string.
String _joinWords(Object? content) {
  if (content is String) return content;
  if (content is List<WordDiff>) return content.map((w) => w.value).join();
  return '';
}

/// Render each row as `type|leftLine|rightLine|leftRaw|rightRaw` so a whole
/// diff can be compared against the RN output verbatim.
List<String> _signature(Object? oldValue, Object? newValue) {
  return computeLineDiff(oldValue, newValue).map((d) {
    final left = d.leftLineNumber?.toString() ?? '-';
    final right = d.rightLineNumber?.toString() ?? '-';
    return '${d.type.name}|$left|$right|${d.leftRaw ?? ''}|${d.rightRaw ?? ''}';
  }).toList();
}

void main() {
  group('computeLineDiff parity', () {
    test('identical objects produce no changes', () {
      final diffs = computeLineDiff({'a': 1}, {'a': 1});
      // {, "a": 1, } → all three lines unchanged.
      expect(diffs.length, 3);
      expect(diffs.every((d) => d.type == DiffType.unchanged), isTrue);
      expect(diffs.where((d) => d.type == DiffType.added), isEmpty);
      expect(diffs.where((d) => d.type == DiffType.removed), isEmpty);
      expect(diffs.where((d) => d.type == DiffType.modified), isEmpty);
    });

    test('a changed primitive value → one modified line with word diff', () {
      final diffs = computeLineDiff({'a': 1}, {'a': 2});
      expect(diffs.map((d) => d.type).toList(), [
        DiffType.unchanged, // {
        DiffType.modified, // "a": 1 → "a": 2
        DiffType.unchanged, // }
      ]);

      final modified = diffs[1];
      // Word-level: the "1" run is removed on the left, "2" added on the right.
      final left = modified.leftContent as List<WordDiff>;
      final right = modified.rightContent as List<WordDiff>;
      expect(left.last.value, '1');
      expect(left.last.type, DiffType.removed);
      expect(right.last.value, '2');
      expect(right.last.type, DiffType.added);
      // Reassembling word runs yields the raw lines.
      expect(_joinWords(modified.leftContent), modified.leftRaw);
      expect(_joinWords(modified.rightContent), modified.rightRaw);
    });

    test('word-level string diff isolates the changed word', () {
      final diffs = computeLineDiff(
        {'msg': 'hello world'},
        {'msg': 'hello mars'},
      );
      final modified = diffs.firstWhere((d) => d.type == DiffType.modified);
      final left = modified.leftContent as List<WordDiff>;
      final right = modified.rightContent as List<WordDiff>;
      // "hello" survives as unchanged on both sides.
      expect(left.any((w) => w.value == '"hello' && w.type == DiffType.unchanged),
          isTrue);
      // The final word run differs.
      expect(left.last.type, DiffType.removed);
      expect(left.last.value, contains('world'));
      expect(right.last.type, DiffType.added);
      expect(right.last.value, contains('mars'));
    });

    test('disableWordDiff keeps whole modified lines as strings', () {
      final diffs = computeLineDiff(
        {'a': 1},
        {'a': 2},
        const DiffComputeOptions(disableWordDiff: true),
      );
      final modified = diffs.firstWhere((d) => d.type == DiffType.modified);
      expect(modified.leftContent, isA<String>());
      expect(modified.rightContent, isA<String>());
    });

    test('showDiffOnly drops unchanged lines outside the context window', () {
      final oldValue = {
        for (var i = 0; i < 20; i++) 'k$i': i,
      };
      final newValue = {
        for (var i = 0; i < 20; i++) 'k$i': i == 10 ? 999 : i,
      };
      final full = computeLineDiff(oldValue, newValue);
      final diffOnly = computeLineDiff(
        oldValue,
        newValue,
        const DiffComputeOptions(showDiffOnly: true, contextLines: 2),
      );
      // Only the changed line ± 2 context lines survive — far fewer than full.
      expect(diffOnly.length, lessThan(full.length));
      expect(diffOnly.any((d) => d.type == DiffType.modified), isTrue);
    });

    test('added lines when a key appears only in the new value', () {
      final diffs = computeLineDiff({'a': 1}, {'a': 1, 'b': 2});
      expect(diffs.any((d) => d.type == DiffType.added), isTrue);
    });

    test('null vs value is handled without throwing', () {
      final diffs = computeLineDiff(null, {'a': 1});
      expect(diffs, isNotEmpty);
    });
  });

  // Array edits used to light up every line after the edit point: the greedy
  // matcher walked both sides in lockstep, so one push reported the previous
  // last item as modified (trailing comma) plus the closing bracket as
  // removed+added, and a prepend reported the entire array. Every signature
  // below is the verbatim output of the RN implementation.
  group('computeLineDiff array parity', () {
    test('appending one item reports only that item', () {
      expect(
        _signature(
          ['pikachu', 'charizard', 'blastoise', 'gengar'],
          ['pikachu', 'charizard', 'blastoise', 'gengar', 'dragonite'],
        ),
        [
          'unchanged|1|1|[|[',
          'unchanged|2|2|  "pikachu",|  "pikachu",',
          'unchanged|3|3|  "charizard",|  "charizard",',
          'unchanged|4|4|  "blastoise",|  "blastoise",',
          // The trailing comma the push added is not a change.
          'unchanged|5|5|  "gengar"|  "gengar",',
          'added|-|6||  "dragonite"',
          'unchanged|6|7|]|]',
        ],
      );
    });

    test('prepending one item reports only that item', () {
      expect(
        _signature(['a', 'b', 'c'], ['z', 'a', 'b', 'c']),
        [
          'unchanged|1|1|[|[',
          'added|-|2||  "z",',
          'unchanged|2|3|  "a",|  "a",',
          'unchanged|3|4|  "b",|  "b",',
          'unchanged|4|5|  "c"|  "c"',
          'unchanged|5|6|]|]',
        ],
      );
    });

    test('inserting in the middle reports only that item', () {
      expect(
        _signature(['a', 'b', 'c'], ['a', 'z', 'b', 'c']),
        [
          'unchanged|1|1|[|[',
          'unchanged|2|2|  "a",|  "a",',
          'added|-|3||  "z",',
          'unchanged|3|4|  "b",|  "b",',
          'unchanged|4|5|  "c"|  "c"',
          'unchanged|5|6|]|]',
        ],
      );
    });

    test('removing from the middle reports only that item', () {
      expect(
        _signature(['a', 'b', 'c'], ['a', 'c']),
        [
          'unchanged|1|1|[|[',
          'unchanged|2|2|  "a",|  "a",',
          'removed|3|-|  "b",|',
          'unchanged|4|3|  "c"|  "c"',
          'unchanged|5|4|]|]',
        ],
      );
    });

    test('prepending an object keeps the existing objects unchanged', () {
      expect(
        _signature(
          [
            {'id': 1, 'name': 'alpha'},
            {'id': 2, 'name': 'beta'},
          ],
          [
            {'id': 9, 'name': 'zulu'},
            {'id': 1, 'name': 'alpha'},
            {'id': 2, 'name': 'beta'},
          ],
        ),
        [
          'unchanged|1|1|[|[',
          'unchanged|2|2|  {|  {',
          'added|-|3||    "id": 9,',
          'added|-|4||    "name": "zulu"',
          'added|-|5||  },',
          'added|-|6||  {',
          'unchanged|3|7|    "id": 1,|    "id": 1,',
          'unchanged|4|8|    "name": "alpha"|    "name": "alpha"',
          'unchanged|5|9|  },|  },',
          'unchanged|6|10|  {|  {',
          'unchanged|7|11|    "id": 2,|    "id": 2,',
          'unchanged|8|12|    "name": "beta"|    "name": "beta"',
          'unchanged|9|13|  }|  }',
          'unchanged|10|14|]|]',
        ],
      );
    });

    test('appending to a nested array leaves the wrapper unchanged', () {
      expect(
        _signature(
          {
            'team': {
              'roster': ['a', 'b'],
            },
            'v': 1,
          },
          {
            'team': {
              'roster': ['a', 'b', 'c'],
            },
            'v': 1,
          },
        ),
        [
          'unchanged|1|1|{|{',
          'unchanged|2|2|  "team": {|  "team": {',
          'unchanged|3|3|    "roster": [|    "roster": [',
          'unchanged|4|4|      "a",|      "a",',
          'unchanged|5|5|      "b"|      "b",',
          'added|-|6||      "c"',
          'unchanged|6|7|    ]|    ]',
          'unchanged|7|8|  },|  },',
          'unchanged|8|9|  "v": 1|  "v": 1',
          'unchanged|9|10|}|}',
        ],
      );
    });

    test('wholly replaced items stay removed + added, not modified', () {
      expect(
        _signature(['a', 'b'], ['x', 'y']),
        [
          'unchanged|1|1|[|[',
          'removed|2|-|  "a",|',
          'added|-|2||  "x",',
          'removed|3|-|  "b"|',
          'added|-|3||  "y"',
          'unchanged|4|4|]|]',
        ],
      );
    });

    test('ignoreTrailingComma: false isolates the punctuation suppression', () {
      final diffs = computeLineDiff(
        ['a', 'b'],
        ['a', 'b', 'c'],
        const DiffComputeOptions(ignoreTrailingComma: false),
      );
      // The line matcher still finds the insert, but the item that gained a
      // comma now reads as modified.
      expect(diffs.where((d) => d.type == DiffType.modified).length, 1);
      expect(diffs.where((d) => d.type == DiffType.added).length, 1);
    });

    test('a large array with one push stays a single added row', () {
      final base = List<String>.generate(2000, (i) => 'item-$i');
      final pushed = [...base, 'item-new'];
      final diffs = computeLineDiff(base, pushed);
      final changed =
          diffs.where((d) => d.type != DiffType.unchanged).toList();
      expect(changed.length, 1);
      expect(changed.first.type, DiffType.added);
      expect(changed.first.rightRaw?.trim(), '"item-new"');
    });

    test('wildly dissimilar large input falls back without throwing', () {
      final a = List<String>.generate(3000, (i) => 'a$i');
      final b = List<String>.generate(3000, (i) => 'b$i');
      expect(computeLineDiff(a, b), isNotEmpty);
    });
  });

  // [absentValue] means "this value did not exist" — the state a key's first
  // event is diffed against. It must stay distinct from the real values that
  // merely look empty (`null`, `[]`, `''`), which diff normally.
  group('computeLineDiff absent-value parity', () {
    test('absent → value is purely added, with no left-hand lines', () {
      expect(
        _signature(absentValue, ['pikachu']),
        [
          'added|-|1||[',
          'added|-|2||  "pikachu"',
          'added|-|3||]',
        ],
      );
    });

    test('value → absent is purely removed', () {
      expect(
        _signature(['pikachu'], absentValue),
        [
          'removed|1|-|[|',
          'removed|2|-|  "pikachu"|',
          'removed|3|-|]|',
        ],
      );
    });

    test('absent on both sides produces no rows', () {
      expect(_signature(absentValue, absentValue), isEmpty);
    });

    test('an empty array is a real prior value, not absent', () {
      expect(
        _signature(<String>[], ['pikachu']),
        [
          'modified|1|1|[]|[',
          'added|-|2||  "pikachu"',
          'added|-|3||]',
        ],
      );
    });

    test('null is a real prior value, not absent', () {
      expect(
        _signature(null, ['pikachu']),
        [
          'removed|1|-|null|',
          'added|-|1||[',
          'added|-|2||  "pikachu"',
          'added|-|3||]',
        ],
      );
    });

    test('an empty string is a real prior value, not absent', () {
      expect(
        _signature('', 'pikachu'),
        [
          'removed|1|-|""|',
          'added|-|1||"pikachu"',
        ],
      );
    });

    test('isAbsent only matches the marker', () {
      expect(isAbsent(absentValue), isTrue);
      expect(isAbsent(null), isFalse);
      expect(isAbsent(<String>[]), isFalse);
      expect(isAbsent(''), isFalse);
      expect(isAbsent(0), isFalse);
    });
  });
}
