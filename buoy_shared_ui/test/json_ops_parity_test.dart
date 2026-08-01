/// Ports packages/shared/src/dataViewer/__tests__/jsonOps.test.ts case-for-case,
/// plus the `treeActionsFor` rules the RN suite covers only through the UI.
///
/// These are worth testing away from the UI because every one of them is a way
/// to silently corrupt a user's stored document: an off-by-one in `insert`, a
/// rename that reshuffles key order, or a duplicate that aliases instead of
/// copying all look fine on screen and only bite later.
library;

import 'dart:convert';

import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// Compare by JSON, matching the RN harness — key ORDER is part of what these
/// ops promise, and a Map equality check would happily ignore it.
Matcher jsonEquals(Object? expected) => predicate<Object?>(
  (actual) => jsonEncode(actual) == jsonEncode(expected),
  'JSON-equal to ${jsonEncode(expected)}',
);

Map<String, Object?> makeDoc() => {
  'list': ['a', 'b', 'c'],
  'nested': {
    'keep': 1,
    'drop': 2,
    'deep': {
      'n': [1, 2],
    },
  },
  'flag': true,
};

void main() {
  final doc = makeDoc();

  group('arrays', () {
    test('append', () {
      expect(
        applyJsonOp(doc, const JsonAppendOp(['list'], 'd')),
        jsonEquals(makeDoc()..['list'] = ['a', 'b', 'c', 'd']),
      );
    });

    test('insert in the middle', () {
      expect(
        applyJsonOp(doc, const JsonInsertOp(['list'], 1, 'x')),
        jsonEquals(makeDoc()..['list'] = ['a', 'x', 'b', 'c']),
      );
    });

    test('insert past the end clamps to append', () {
      expect(
        applyJsonOp(doc, const JsonInsertOp(['list'], 99, 'z')),
        jsonEquals(makeDoc()..['list'] = ['a', 'b', 'c', 'z']),
      );
    });

    test('remove an item', () {
      expect(
        applyJsonOp(doc, const JsonRemoveOp(['list', '1'])),
        jsonEquals(makeDoc()..['list'] = ['a', 'c']),
      );
    });

    test('duplicate lands next to the original', () {
      expect(
        applyJsonOp(doc, const JsonDuplicateOp(['list', '0'])),
        jsonEquals(makeDoc()..['list'] = ['a', 'a', 'b', 'c']),
      );
    });

    test('move down', () {
      expect(
        applyJsonOp(doc, const JsonMoveOp(['list', '0'], 2)),
        jsonEquals(makeDoc()..['list'] = ['b', 'c', 'a']),
      );
    });

    test('move past the end clamps', () {
      expect(
        applyJsonOp(doc, const JsonMoveOp(['list', '0'], 99)),
        jsonEquals(makeDoc()..['list'] = ['b', 'c', 'a']),
      );
    });

    test('clear keeps the container', () {
      expect(
        applyJsonOp(doc, const JsonClearOp(['list'])),
        jsonEquals(makeDoc()..['list'] = <Object?>[]),
      );
    });
  });

  group('objects', () {
    test('addKey', () {
      expect(
        applyJsonOp(doc, const JsonAddKeyOp(['nested'], 'added', 3)),
        jsonEquals(
          makeDoc()
            ..['nested'] = {
              'keep': 1,
              'drop': 2,
              'deep': {
                'n': [1, 2],
              },
              'added': 3,
            },
        ),
      );
    });

    test('remove a key', () {
      expect(
        applyJsonOp(doc, const JsonRemoveOp(['nested', 'drop'])),
        jsonEquals(
          makeDoc()
            ..['nested'] = {
              'keep': 1,
              'deep': {
                'n': [1, 2],
              },
            },
        ),
      );
    });

    test('renameKey keeps its position', () {
      final next =
          applyJsonOp(doc, const JsonRenameKeyOp(['nested', 'keep'], 'kept'))
              as Map;
      expect((next['nested'] as Map).keys.toList(), ['kept', 'drop', 'deep']);
    });

    test('duplicating a key mints a non-colliding name in place', () {
      final next =
          applyJsonOp(doc, const JsonDuplicateOp(['nested', 'keep'])) as Map;
      expect((next['nested'] as Map).keys.toList(), [
        'keep',
        'keep copy',
        'drop',
        'deep',
      ]);
    });
  });

  group("refusals — an op that can't apply cleanly changes nothing", () {
    test('addKey refuses to clobber an existing key', () {
      expect(
        applyJsonOp(doc, const JsonAddKeyOp(['nested'], 'keep', 99)),
        jsonEquals(doc),
      );
    });

    test('renameKey refuses to clobber a sibling', () {
      expect(
        applyJsonOp(doc, const JsonRenameKeyOp(['nested', 'keep'], 'drop')),
        jsonEquals(doc),
      );
    });

    test('remove out of range', () {
      expect(
        applyJsonOp(doc, const JsonRemoveOp(['list', '9'])),
        jsonEquals(doc),
      );
    });

    test("path that doesn't resolve", () {
      expect(
        applyJsonOp(doc, const JsonAppendOp(['nope'], 1)),
        jsonEquals(doc),
      );
    });

    test('append to a non-array', () {
      expect(
        applyJsonOp(doc, const JsonAppendOp(['flag'], 1)),
        jsonEquals(doc),
      );
    });
  });

  group('nesting and the root', () {
    test('append deep in the tree', () {
      expect(
        applyJsonOp(doc, const JsonAppendOp(['nested', 'deep', 'n'], 3)),
        jsonEquals(
          makeDoc()
            ..['nested'] = {
              'keep': 1,
              'drop': 2,
              'deep': {
                'n': [1, 2, 3],
              },
            },
        ),
      );
    });

    test('replace a scalar', () {
      expect(
        applyJsonOp(doc, const JsonReplaceOp(['flag'], false)),
        jsonEquals(makeDoc()..['flag'] = false),
      );
    });

    test('replace the root', () {
      expect(
        applyJsonOp(doc, const JsonReplaceOp([], [1])),
        jsonEquals([1]),
      );
    });

    test('op against a root array', () {
      expect(
        applyJsonOp([1, 2], const JsonAppendOp([], 3)),
        jsonEquals([1, 2, 3]),
      );
    });
  });

  group('immutability', () {
    test('the input is never mutated', () {
      final subject = makeDoc();
      final before = jsonEncode(subject);
      applyJsonOp(subject, const JsonAppendOp(['list'], 'mutated?'));
      applyJsonOp(subject, const JsonRemoveOp(['nested', 'drop']));
      applyJsonOp(subject, const JsonDuplicateOp(['nested', 'deep']));
      expect(jsonEncode(subject), before);
    });

    test('duplicate deep-copies rather than aliasing', () {
      final duplicated =
          applyJsonOp({
                'items': [
                  {'n': 1},
                ],
              }, const JsonDuplicateOp(['items', '0']))
              as Map;
      ((duplicated['items'] as List)[1] as Map)['n'] = 999;
      expect(((duplicated['items'] as List)[0] as Map)['n'], 1);
    });
  });

  group('helpers', () {
    test('getAtPath walks arrays and objects', () {
      expect(getAtPath(doc, ['nested', 'deep', 'n', '1']), 2);
    });

    test('a new entry matches the neighbours type', () {
      expect(suggestedNewValue([1, 2]), 0);
      expect(suggestedNewValue(['a']), '');
      expect(suggestedNewValue(<Object?>[]), '');
      expect(suggestedNewValue([true]), false);
    });
  });

  group('where the highlight lands after an edit', () {
    // An op reshapes the list, so a selection left on its old path silently
    // names a DIFFERENT node — move item 2 up and path `2` is whatever got
    // displaced.
    test('move follows the node to its new slot', () {
      expect(
        selectionPathAfterOp(const JsonMoveOp(['list', '2'], 1)).path,
        ['list', '1'],
      );
      expect(selectionPathAfterOp(const JsonMoveOp(['0'], 3)).path, ['3']);
    });

    test('duplicate selects the copy, which lands after the original', () {
      expect(
        selectionPathAfterOp(const JsonDuplicateOp(['items', '1'])).path,
        ['items', '2'],
      );
    });

    test('duplicating an object key leaves the selection alone', () {
      expect(
        selectionPathAfterOp(const JsonDuplicateOp(['cfg', 'name'])),
        isA<SelectionUnchanged>(),
      );
    });

    test('remove clears the selection', () {
      final after = selectionPathAfterOp(const JsonRemoveOp(['list', '1']));
      expect(after, isNot(isA<SelectionUnchanged>()));
      expect(after.path, isNull);
    });

    test('append and replace leave the selection alone', () {
      expect(
        selectionPathAfterOp(const JsonAppendOp(['list'], 1)),
        isA<SelectionUnchanged>(),
      );
      expect(
        selectionPathAfterOp(const JsonReplaceOp(['a'], 1)),
        isA<SelectionUnchanged>(),
      );
    });
  });

  group('treeActionsFor', () {
    List<TreeAction> actionsAt(List<String> path) => treeActionsFor(
      doc,
      DataTreeSelection(
        path: path,
        value: getAtPath(doc, path),
        label: path.isEmpty ? 'root' : path.last,
      ),
      containersEditable: true,
    );

    test('always returns the same six, in the same order', () {
      for (final path in [
        <String>[],
        ['list'],
        ['list', '1'],
        ['nested', 'keep'],
        ['flag'],
      ]) {
        expect(actionsAt(path).map((a) => a.id).toList(), [
          TreeActionId.editValue,
          TreeActionId.add,
          TreeActionId.duplicate,
          TreeActionId.moveUp,
          TreeActionId.moveDown,
          TreeActionId.remove,
        ], reason: 'at $path');
      }
    });

    test('no selection disables everything', () {
      final actions = treeActionsFor(doc, null);
      expect(actions.every((a) => !a.enabled), isTrue);
    });

    test('a boolean toggles in place rather than opening an editor', () {
      final edit = treeActionMap(actionsAt(['flag']))[TreeActionId.editValue]!;
      expect(edit.label, 'Toggle');
      expect(edit.op, isA<JsonReplaceOp>());
      expect((edit.op! as JsonReplaceOp).value, false);
    });

    test('the add slot follows the container type', () {
      expect(
        treeActionMap(actionsAt(['list']))[TreeActionId.add]!.label,
        'Append',
      );
      expect(
        treeActionMap(actionsAt(['nested']))[TreeActionId.add]!.label,
        'Add key',
      );
      // A scalar can't take an add at all, but the slot stays put.
      final onScalar = treeActionMap(actionsAt(['flag']))[TreeActionId.add]!;
      expect(onScalar.enabled, isFalse);
      expect(onScalar.op, isNull);
    });

    test('add on a map picks a non-colliding key and selects it', () {
      final add = treeActionMap(actionsAt(['nested']))[TreeActionId.add]!;
      expect((add.op! as JsonAddKeyOp).key, 'newKey');
      expect(add.selectAfter, ['nested', 'newKey']);
    });

    test('move is bounded by the parent list', () {
      final first = treeActionMap(actionsAt(['list', '0']));
      expect(first[TreeActionId.moveUp]!.enabled, isFalse);
      expect(first[TreeActionId.moveDown]!.enabled, isTrue);

      final last = treeActionMap(actionsAt(['list', '2']));
      expect(last[TreeActionId.moveUp]!.enabled, isTrue);
      expect(last[TreeActionId.moveDown]!.enabled, isFalse);

      // A map entry has no order to move within.
      final inMap = treeActionMap(actionsAt(['nested', 'keep']));
      expect(inMap[TreeActionId.moveUp]!.enabled, isFalse);
      expect(inMap[TreeActionId.moveDown]!.enabled, isFalse);
    });

    test('the root can be neither duplicated nor removed', () {
      final root = treeActionMap(actionsAt([]));
      expect(root[TreeActionId.duplicate]!.enabled, isFalse);
      expect(root[TreeActionId.remove]!.enabled, isFalse);
      expect(root[TreeActionId.remove]!.danger, isTrue);
    });

    test('containersEditable gates editing a container as raw JSON', () {
      final selection = DataTreeSelection(
        path: const ['list'],
        value: getAtPath(doc, ['list']),
        label: 'list',
      );
      expect(
        treeActionMap(
          treeActionsFor(doc, selection, containersEditable: true),
        )[TreeActionId.editValue]!.enabled,
        isTrue,
      );
      expect(
        treeActionMap(
          treeActionsFor(doc, selection),
        )[TreeActionId.editValue]!.enabled,
        isFalse,
      );
    });
  });

  group('typeLabel / breadcrumb', () {
    test('typeLabel names what a badge shows', () {
      expect(typeLabel(null), 'null');
      expect(typeLabel(<Object?>[]), 'array');
      expect(typeLabel(<String, Object?>{}), 'object');
      expect(typeLabel('s'), 'string');
      expect(typeLabel(1), 'number');
      expect(typeLabel(true), 'boolean');
    });

    test('breadcrumb reads as a location', () {
      expect(breadcrumb(const []), 'root');
      expect(breadcrumb(const ['a', 'b', '2']), 'a › b › 2');
    });
  });
}
