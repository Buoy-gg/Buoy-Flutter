// Pins the live editor's write contract (RN LiveExplorer): typed edits
// debounce to ONE write and flush on blur; discrete gestures write at once;
// the writer's canRemove veto hides delete; an absent writer is read-only.
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Log extends LiveEditWriter {
  /// Recorded as `'a/b=value'` — a record holding a List compares by identity.
  final updates = <String>[];
  final removes = <List<String>>[];
  bool Function(List<String>)? veto;

  @override
  void update(List<String> path, Object? value) => updates.add('${path.join('/')}=$value');
  @override
  void Function(List<String> path)? get remove => removes.add;
  @override
  bool canRemove(List<String> path) => veto?.call(path) ?? true;
}

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  testWidgets('typed edits debounce to one write, flushed on blur', (tester) async {
    final log = _Log();
    await tester.pumpWidget(_host(LiveExplorer(
      label: 'Value',
      value: const {'name': 'gra'},
      editable: true,
      writer: log,
      defaultExpanded: const ['Value'],
      debounceMs: 300,
    )));
    final field = find.byType(TextField);
    expect(field, findsOneWidget);
    await tester.enterText(field, 'gran');
    await tester.enterText(field, 'grano');
    await tester.enterText(field, 'granola');
    expect(log.updates, isEmpty, reason: 'nothing lands while typing');
    await tester.pump(const Duration(milliseconds: 350));
    expect(log.updates, ['name=granola'], reason: '"granola" is ONE write');

    await tester.enterText(field, 'granola bar');
    // Blur before the timer: the pending edit rides along with focus leaving.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(log.updates.last, 'name=granola bar');
  });

  testWidgets('toggle and stepper write immediately; delete respects the veto', (tester) async {
    final log = _Log()..veto = (path) => path.length != 1 || path.first != 'locked';
    await tester.pumpWidget(_host(LiveExplorer(
      label: 'Value',
      value: const {'on': false, 'n': 5, 'locked': 'x'},
      editable: true,
      writer: log,
      defaultExpanded: const ['Value'],
      debounceMs: 300,
    )));
    await tester.tap(find.text('FALSE'));
    await tester.pump();
    expect(log.updates.last, 'on=true');

    // Delete buttons: 'on' and 'n' are removable, 'locked' is vetoed.
    expect(find.bySemanticsLabel('Delete item'), findsNWidgets(2));

    // The number stepper commits without waiting for the debounce.
    final steppers = find.byWidgetPredicate(
      (w) => w is BuoyGlyph && w.glyph == BuoyIcons.chevronUp,
    );
    await tester.tap(steppers.first);
    await tester.pump();
    expect(log.updates.last, 'n=6');
  });

  testWidgets('no writer → read-only tree with no inputs or actions', (tester) async {
    await tester.pumpWidget(_host(const LiveExplorer(
      label: 'Value',
      value: {'a': 1, 'b': true, 'c': 'str'},
      editable: true,
      defaultExpanded: ['Value'],
    )));
    expect(find.byType(TextField), findsNothing);
    expect(find.text('TRUE'), findsNothing);
    expect(find.text('true'), findsOneWidget);
    expect(find.bySemanticsLabel('Delete item'), findsNothing);
  });

  test('RootWriter applies path writes to the root', () {
    Object? root = {'a': {'b': 1}, 'xs': [1, 2, 3]};
    final w = RootWriter(getRoot: () => root, setRoot: (n) => root = n);
    w.update(['a', 'b'], 2);
    expect((root as Map)['a'], {'b': 2});
    w.remove!(['xs', '1']);
    expect((root as Map)['xs'], [1, 3]);
    w.update([], 'whole');
    expect(root, 'whole');
  });
}
