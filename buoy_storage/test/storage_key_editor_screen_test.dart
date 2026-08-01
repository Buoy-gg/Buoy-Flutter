/// Drives the real editor widget tree — the half the unit tests can't reach.
///
/// The interesting failures here are structural rather than logical: the tree
/// reports its selection back up to the controller that owns it, so a careless
/// notification lands in the middle of an ancestor's build. Pumping the actual
/// widgets is the only thing that catches that.
library;

import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:buoy_storage/src/storage_tool/storage_key_editor_screen.dart';
import 'package:buoy_storage/src/storage_tool/storage_models.dart';

Widget host(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(width: 400, height: 800, child: child)),
);

StorageKeyInfo key(Object? value) =>
    StorageKeyInfo(key: '@app/profile', value: value, rawValue: value);

void main() {
  group('tree editor', () {
    testWidgets('selecting a row arms the dock', (tester) async {
      await tester.pumpWidget(
        host(
          StorageKeyEditorScreen(
            storageKey: key({
              'name': 'ash',
              'badges': [1, 2],
            }),
            onSave: (_) async {},
            onClose: () {},
          ),
        ),
      );

      // Nothing selected yet: the dock says so and every tile is inert.
      expect(find.text('Tap a row to select it'), findsOneWidget);

      // Tree rows are rich text, so match the span rather than a whole Text.
      await tester.tap(find.textContaining('name: ').first);
      await tester.pumpAndSettle();

      // The breadcrumb names the selection and the badge names its type.
      expect(find.text('name'), findsWidgets);
      expect(find.text('string'), findsWidgets);
    });

    testWidgets('a structural action edits the draft, not the device', (
      tester,
    ) async {
      final writes = <String>[];
      await tester.pumpWidget(
        host(
          StorageKeyEditorScreen(
            storageKey: key({
              'badges': [1, 2],
            }),
            onSave: (raw) async => writes.add(raw),
            onClose: () {},
          ),
        ),
      );

      await tester.tap(find.textContaining('badges: ').first);
      await tester.pumpAndSettle();

      // The add slot follows the container type.
      expect(find.text('Append'), findsOneWidget);
      await tester.tap(find.text('Append'));
      await tester.pumpAndSettle();

      // Buffered: the commit row appears, and nothing has been written.
      expect(find.text('Draft · unsaved'), findsOneWidget);
      expect(find.text('Save changes'), findsOneWidget);
      expect(writes, isEmpty);

      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      expect(writes, ['{"badges":[1,2,0]}']);
    });

    testWidgets('a boolean toggles in place instead of opening the modal', (
      tester,
    ) async {
      final writes = <String>[];
      await tester.pumpWidget(
        host(
          StorageKeyEditorScreen(
            storageKey: key({'onboarded': true}),
            onSave: (raw) async => writes.add(raw),
            onClose: () {},
          ),
        ),
      );

      await tester.tap(find.textContaining('onboarded: ').first);
      await tester.pumpAndSettle();

      expect(find.text('Toggle'), findsOneWidget);
      await tester.tap(find.text('Toggle'));
      await tester.pumpAndSettle();

      // No modal, and the flip is already in the draft.
      expect(find.text('Edit value'), findsNothing);
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(writes, ['{"onboarded":false}']);
    });

    testWidgets('editing a value goes through the modal into the draft', (
      tester,
    ) async {
      final writes = <String>[];
      await tester.pumpWidget(
        host(
          StorageKeyEditorScreen(
            storageKey: key({'name': 'ash'}),
            onSave: (raw) async => writes.add(raw),
            onClose: () {},
          ),
        ),
      );

      await tester.tap(find.textContaining('name: ').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit value'));
      await tester.pumpAndSettle();

      expect(find.text('Edit value'), findsWidgets);
      await tester.enterText(find.byType(TextField), 'misty');
      await tester.pumpAndSettle();

      // "Apply" — it reaches the draft here; the single write is still Save.
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(writes, isEmpty);

      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(writes, ['{"name":"misty"}']);
    });

    testWidgets('closing dirty asks before throwing the work away', (
      tester,
    ) async {
      var closed = false;
      await tester.pumpWidget(
        host(
          StorageKeyEditorScreen(
            storageKey: key({
              'badges': [1],
            }),
            onSave: (_) async {},
            onClose: () => closed = true,
          ),
        ),
      );

      await tester.tap(find.textContaining('badges: ').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Append'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(BuoyGlyph).first); // the close X
      await tester.pumpAndSettle();

      expect(find.text('Unsaved changes'), findsOneWidget);
      expect(closed, isFalse);

      // `.last` — the footer has its own Discard behind the alert.
      await tester.tap(find.text('Discard').last);
      await tester.pumpAndSettle();
      expect(closed, isTrue);
    });

    testWidgets('a refused write keeps the editor open and says why', (
      tester,
    ) async {
      var closed = false;
      await tester.pumpWidget(
        host(
          StorageKeyEditorScreen(
            storageKey: key({
              'badges': [1],
            }),
            onSave: (_) async => throw StateError('device said no'),
            onClose: () => closed = true,
          ),
        ),
      );

      await tester.tap(find.textContaining('badges: ').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Append'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      expect(closed, isFalse);
      expect(find.text('device said no'), findsOneWidget);
      expect(find.text('Save changes'), findsOneWidget, reason: 'still dirty');
    });
  });

  group('scalar editor', () {
    testWidgets('a scalar key skips the tree and writes on save', (
      tester,
    ) async {
      final writes = <String>[];
      await tester.pumpWidget(
        host(
          StorageKeyEditorScreen(
            storageKey: key('ash'),
            onSave: (raw) async => writes.add(raw),
            onClose: () {},
          ),
        ),
      );

      // No structural editor at all — just the value modal.
      expect(find.text('Append'), findsNothing);
      expect(find.text('Duplicate'), findsNothing);

      await tester.enterText(find.byType(TextField), 'misty');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(writes, ['"misty"']);
    });

    testWidgets('a number refuses text rather than changing type', (
      tester,
    ) async {
      final writes = <String>[];
      await tester.pumpWidget(
        host(
          StorageKeyEditorScreen(
            storageKey: key(7),
            onSave: (raw) async => writes.add(raw),
            onClose: () {},
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'not a number');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(writes, isEmpty, reason: 'the save is blocked while invalid');

      await tester.enterText(find.byType(TextField), '9');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(writes, ['9']);
    });

    testWidgets('a boolean commits straight from its choice', (tester) async {
      final writes = <String>[];
      await tester.pumpWidget(
        host(
          StorageKeyEditorScreen(
            storageKey: key(true),
            onSave: (raw) async => writes.add(raw),
            onClose: () {},
          ),
        ),
      );

      // Two tiles and no Save button — there is no decision left in one.
      expect(find.text('Save'), findsNothing);
      await tester.tap(find.text('false'));
      await tester.pumpAndSettle();
      expect(writes, ['false']);
    });
  });
}
