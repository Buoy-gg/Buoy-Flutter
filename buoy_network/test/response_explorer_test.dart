import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:buoy_network/src/network_tool/response_editor/explorer.dart';
import 'package:buoy_network/src/network_tool/response_editor/nested_data.dart';

/// The Explorer's whole premise is that there is no read mode and no edit
/// mode: the value you are looking at IS the control. These tests assert that
/// directly — type into what's rendered, and the document changes.

void main() {
  group('nested_data', () {
    test('update replaces a nested map value without touching siblings', () {
      final root = {
        'a': {'b': 1, 'c': 2},
      };
      final next = updateNestedDataByPath(root, ['a', 'b'], 9) as Map;
      expect((next['a'] as Map)['b'], 9);
      expect((next['a'] as Map)['c'], 2);
      // The input is never mutated — callers diff and undo against it.
      expect((root['a']! as Map)['b'], 1);
    });

    test('update addresses list items by their index string', () {
      final next = updateNestedDataByPath(
        {
          'xs': [1, 2, 3],
        },
        ['xs', '1'],
        99,
      ) as Map;
      expect(next['xs'], [1, 99, 3]);
    });

    test('an empty path replaces the whole document', () {
      expect(updateNestedDataByPath({'a': 1}, [], 'gone'), 'gone');
    });

    test('an out-of-range index is a no-op, not a crash', () {
      final root = {
        'xs': [1],
      };
      expect(updateNestedDataByPath(root, ['xs', '7'], 9), root);
    });

    test('delete removes a key and renumbers a list', () {
      expect(
        deleteNestedDataByPath({'a': 1, 'b': 2}, ['a']),
        {'b': 2},
      );
      expect(
        deleteNestedDataByPath(
          {
            'xs': [1, 2, 3],
          },
          ['xs', '1'],
        ),
        {
          'xs': [1, 3],
        },
      );
    });
  });

  group('BuoyExplorer', () {
    Object? current;

    Future<void> pump(WidgetTester tester, Object? root) async {
      current = root;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 402,
              height: 600,
              child: StatefulBuilder(
                builder: (context, setState) => SingleChildScrollView(
                  child: ResponseEditorScope(
                    root: current,
                    onChange: (next) => setState(() => current = next),
                    child: BuoyExplorer(
                      label: 'root',
                      value: current,
                      editable: true,
                      defaultExpanded: const ['root'],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('a string leaf renders AS its input — typing is the edit', (
      tester,
    ) async {
      await pump(tester, {'name': 'eevee'});

      // Not a label with an edit button beside it: the value is in the field.
      final field = find.byType(TextField);
      expect(field, findsOneWidget);
      expect(find.text('NAME'), findsOneWidget);

      await tester.enterText(field, 'pikachu');
      await tester.pump();

      expect((current! as Map)['name'], 'pikachu');
    });

    testWidgets('a number leaf keeps its type through an edit', (tester) async {
      await pump(tester, {'id': 133});

      await tester.enterText(find.byType(TextField), '25');
      await tester.pump();

      final value = (current! as Map)['id'];
      expect(value, 25);
      expect(value, isA<num>(), reason: 'must not become the string "25"');
    });

    testWidgets('a half-typed number is left alone rather than written', (
      tester,
    ) async {
      await pump(tester, {'id': 1});
      await tester.enterText(find.byType(TextField), '-');
      await tester.pump();
      // RN drops the edit until it parses; writing "-" would corrupt the body.
      expect((current! as Map)['id'], 1);
    });

    testWidgets('the number stepper increments the document', (tester) async {
      await pump(tester, {'id': 7});
      await tester.tap(find.byIcon0rStep(up: true));
      await tester.pump();
      expect((current! as Map)['id'], 8);
    });

    testWidgets('a boolean leaf renders AS its toggle', (tester) async {
      await pump(tester, {'ok': false});

      expect(find.text('FALSE'), findsOneWidget);
      await tester.tap(find.text('FALSE'));
      await tester.pump();

      expect((current! as Map)['ok'], isTrue);
      expect(find.text('TRUE'), findsOneWidget);
    });

    testWidgets('delete removes the entry from the document', (tester) async {
      await pump(tester, {'name': 'eevee'});

      await tester.tap(find.bySemanticsLabel('Delete item').first);
      await tester.pump();

      expect((current! as Map).containsKey('name'), isFalse);
    });

    testWidgets('a nested object expands and edits through its path', (
      tester,
    ) async {
      await pump(tester, {
        'sprites': {'front': 'a.png'},
      });

      // The child container starts collapsed; open it.
      await tester.tap(find.text('sprites'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'b.png');
      await tester.pump();

      expect(((current! as Map)['sprites'] as Map)['front'], 'b.png');
    });

    testWidgets('a long list is paged rather than rendered whole', (
      tester,
    ) async {
      await pump(tester, {'xs': List<int>.generate(250, (i) => i)});
      await tester.tap(find.text('xs'));
      await tester.pumpAndSettle();

      // RN chunks at 100 with [0...99] page expanders.
      expect(find.text('[0...99]'), findsOneWidget);
      expect(find.text('[100...199]'), findsOneWidget);
      expect(find.text('[200...299]'), findsOneWidget);
    });
  });
}

/// Finds the up/down stepper beside a number field by its glyph position.
extension on CommonFinders {
  Finder byIcon0rStep({required bool up}) {
    final steppers = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_StepButton',
    );
    return up ? steppers.first : steppers.last;
  }
}
