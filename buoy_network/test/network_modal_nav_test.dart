import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:buoy_core/buoy_core.dart';
import 'package:buoy_network/buoy_network.dart';

/// The modal's screen order is a STACK, and getting it wrong is invisible in
/// analysis: every branch compiles, the app just renders the wrong one.
///
/// Found on device — tapping a row in the Saved screen set the selection and
/// nothing happened, because `_showSavedView` was checked before it.

/// Find by the label a screen reader would read.
///
/// NOT `find.bySemanticsLabel`: that reads each element's cached
/// `debugSemantics`, which is populated lazily and comes back empty for a
/// widget that is plainly in the tree. This matches the `Semantics` widget
/// itself, which is what the code actually declares.
Finder bySemLabel(String label) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == label,
);

NetworkCaptureEvent event({String id = 'flt-1'}) => NetworkCaptureEvent(
  id: id,
  method: 'GET',
  url: 'https://api.dev/users/$id',
  timestamp: 1785952554511,
  requestClient: 'dio',
)..status = 200;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    NetworkSavedStore.instance.resetForTest();
    OverrideRulesStore.instance.resetForTest();
    NetworkEventStore.instance.capturing = true;
    NetworkEventStore.instance.clear();
  });

  /// Semantics is enabled BEFORE the first pump on purpose: `bySemanticsLabel`
  /// reads each element's cached `debugSemantics`, which is only populated for
  /// trees built while semantics was on. Turning it on afterwards finds
  /// nothing, which reads exactly like a missing widget.
  Future<SemanticsHandle> pumpModal(WidgetTester tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          // Wider than a real phone on purpose: flutter_test substitutes a
          // fixed-width test font, so strings measure far wider here than they
          // do on device. At 402 the stepper footer "overflows" purely as a
          // font artifact and fails every test in this file.
          //
          // JsModal roots itself in a `Positioned`, so it also needs the
          // overlay host's Stack above it — same as in the app.
          body: SizedBox(
            width: 700,
            height: 780,
            child: Stack(
              children: [
                NetworkModal(storage: BuoyStorage(), onClose: () {}),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return handle;
  }

  testWidgets('a saved request opens its detail view', (tester) async {
    final e = event();
    NetworkEventStore.instance.add(e);
    NetworkSavedStore.instance.toggleSave(e);

    final handle = await pumpModal(tester);

    // Into the Saved screen via the overflow menu.
    await tester.tap(bySemLabel('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Saved requests'));
    await tester.pumpAndSettle();
    expect(find.text('Saved Requests'), findsOneWidget);

    // Tap the row. THIS is the bug: the selection was set and the Saved
    // screen kept rendering, so the detail never appeared.
    await tester.tap(find.textContaining('/users/flt-1').first);
    await tester.pumpAndSettle();

    expect(find.text('Request Details'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('backing out of that detail returns to Saved, not the list', (
    tester,
  ) async {
    final e = event();
    NetworkEventStore.instance.add(e);
    NetworkSavedStore.instance.toggleSave(e);

    final handle = await pumpModal(tester);
    await tester.tap(bySemLabel('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Saved requests'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('/users/flt-1').first);
    await tester.pumpAndSettle();

    await tester.tap(bySemLabel('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Saved Requests'), findsOneWidget);
    expect(find.text('Request Details'), findsNothing);
    handle.dispose();
  });

  testWidgets('the stepper walks the SAVED list, not the live one', (
    tester,
  ) async {
    // Three live requests, one of them saved. Opened from the Saved screen the
    // footer must describe the saved set — otherwise "Next" walks out of the
    // list you were reading and the counter describes a different one.
    for (var i = 1; i <= 3; i++) {
      NetworkEventStore.instance.add(event(id: 'flt-$i'));
    }
    NetworkSavedStore.instance.toggleSave(event(id: 'flt-2'));
    NetworkSavedStore.instance.toggleSave(event(id: 'flt-3'));

    final handle = await pumpModal(tester);
    await tester.tap(bySemLabel('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Saved requests'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('/users/flt-2').first);
    await tester.pumpAndSettle();

    // Two saved of three live: the counter must describe the saved set.
    expect(find.textContaining('OF 2'), findsOneWidget);
    expect(find.textContaining('OF 3'), findsNothing);
    handle.dispose();
  });

  testWidgets('an active rule hoists requests it COVERS, not just marked ones', (
    tester,
  ) async {
    // Captured BEFORE the rule existed, so it carries no override mark — but
    // the next call to it will be forged, which is what the strip is for.
    NetworkEventStore.instance.add(event(id: 'flt-1'));
    OverrideRulesStore.instance.upsertRule(
      OverrideRule(
        id: 'r1',
        enabled: true,
        urlPattern: '*api.dev*',
        kind: OverrideRuleKind.respond,
        status: 500,
        createdAt: 0,
      ),
    );

    final handle = await pumpModal(tester);
    expect(find.textContaining('OVERRIDDEN'), findsOneWidget);
    handle.dispose();
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('Override opens over the detail view, not under it', (
    tester,
  ) async {
    final e = event();
    NetworkEventStore.instance.add(e);

    final handle = await pumpModal(tester);
    await tester.tap(find.textContaining('/users/flt-1').first);
    await tester.pumpAndSettle();
    expect(find.text('Request Details'), findsOneWidget);

    // Overrides is entered FROM detail, which keeps its selection — so it has
    // to win over detail or the button appears dead.
    await tester.tap(bySemLabel('Override this request'));
    await tester.pumpAndSettle();

    expect(find.text('Response Overrides'), findsOneWidget);
    handle.dispose();
  });
}
