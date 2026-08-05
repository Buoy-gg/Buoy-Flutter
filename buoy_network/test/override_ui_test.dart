import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:buoy_core/buoy_core.dart';
import 'package:buoy_network/buoy_network.dart';
import 'package:buoy_network/src/network_tool/network_header_menu.dart';
import 'package:buoy_network/src/network_tool/overrides/network_override_editor.dart';
import 'package:buoy_network/src/network_tool/overrides/network_overrides_button.dart';
import 'package:buoy_network/src/network_tool/overrides/network_overrides_screen.dart';

/// Widget-level coverage for the pieces a device pass would otherwise be the
/// first to exercise: does the editor actually produce the rule its chips
/// describe, and does the flask show the count it promises.

/// A phone-width surface. Deliberately NOT oversized: the test view is 800×600
/// regardless, so a taller box just overflows it and everything past 600px
/// stops being hit-testable — which looks exactly like a broken tap handler.
/// [tapText] scrolls instead, the way a person would.
Widget host(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(width: 402, height: 600, child: child)),
);

/// Scroll the target into view, then tap it.
///
/// The editor is a ListView, which only MOUNTS the children near the viewport —
/// so a chip below the fold doesn't merely fail to hit-test, it isn't in the
/// element tree at all and `find` returns nothing. Scroll first, then tap.
Future<void> tapText(WidgetTester tester, String text) async {
  final finder = find.text(text);
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(finder, 120, maxScrolls: 30);
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump();
}

/// Drain the store's 500ms persist debounce.
///
/// The test binding fails any test that ends with a Timer outstanding, and
/// every store mutation schedules one — so a test that merely CREATES a rule
/// fails on teardown with an error that says nothing about what it was testing.
Future<void> drainStore(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 600));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    OverrideRulesStore.instance.resetForTest();
  });

  group('NetworkOverridesButton', () {
    testWidgets('stays quiet with no rules, and counts the live ones', (
      tester,
    ) async {
      await tester.pumpWidget(host(NetworkOverridesButton(onTap: () {})));
      // `bySemanticsLabel` needs the semantics tree built, and these labels are
      // what a screen reader (and the MCP driver) actually sees.
      final handle = tester.ensureSemantics();
      await tester.pump();
      expect(find.bySemanticsLabel('Response overrides'), findsOneWidget);

      OverrideRulesStore.instance.upsertRule(
        OverrideRule(
          id: 'a',
          enabled: true,
          urlPattern: '*',
          kind: OverrideRuleKind.respond,
          createdAt: 0,
        ),
      );
      await tester.pump();

      // `getSemantics`, not `bySemanticsLabel`: the latter reads the
      // element's cached `debugSemantics`, which is still the pre-rebuild label
      // right after a setState. This reads the live node.
      expect(
        tester.getSemantics(find.byType(NetworkOverridesButton)).label,
        'Response overrides — 1 active',
      );
      expect(find.text('1'), findsOneWidget);
      handle.dispose();
      await drainStore(tester);
    });

    testWidgets('a spent rule stops counting', (tester) async {
      OverrideRulesStore.instance.upsertRule(
        OverrideRule(
          id: 'a',
          enabled: true,
          urlPattern: '*',
          kind: OverrideRuleKind.respond,
          times: 1,
          hits: 1,
          createdAt: 0,
        ),
      );
      await tester.pumpWidget(host(NetworkOverridesButton(onTap: () {})));
      final handle = tester.ensureSemantics();
      await tester.pump();
      expect(find.bySemanticsLabel('Response overrides'), findsOneWidget);
      handle.dispose();
      await drainStore(tester);
    });
  });

  group('NetworkHeaderMenu', () {
    // This group exists because the first version of the dropdown rendered
    // NOTHING on device: a `Positioned` with only top/right is laid out with
    // 0..infinity width, and the Column's `stretch` blew up inside it. The
    // widget had been written and wired but never actually rendered in a test.
    testWidgets('renders its items inside a Stack', (tester) async {
      var closed = false;
      await tester.pumpWidget(
        host(
          Stack(
            children: [
              const Positioned.fill(child: ColoredBox(color: Colors.black)),
              NetworkHeaderMenu(
                onClose: () => closed = true,
                children: [
                  NetworkHeaderMenuItem(
                    icon: BuoyIcons.filter,
                    label: 'Filters',
                    onTap: () {},
                  ),
                  NetworkHeaderMenuItem(
                    icon: BuoyIcons.copy,
                    label: 'Copy requests',
                    onTap: () {},
                  ),
                ],
              ),
            ],
          ),
        ),
      );

      expect(tester.takeException(), isNull, reason: 'must lay out');
      expect(find.text('Filters'), findsOneWidget);
      expect(find.text('Copy requests'), findsOneWidget);

      // The backdrop closes it — tapping well away from the panel.
      await tester.tapAt(const Offset(40, 500));
      expect(closed, isTrue);
    });

    testWidgets('the button reports open/closed to assistive tech', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(NetworkHeaderMenuButton(onTap: () {}, isOpen: false)),
      );
      final handle = tester.ensureSemantics();
      await tester.pump();
      expect(
        tester.getSemantics(find.byType(NetworkHeaderMenuButton)).label,
        'More actions',
      );

      await tester.pumpWidget(
        host(NetworkHeaderMenuButton(onTap: () {}, isOpen: true)),
      );
      await tester.pump();
      expect(
        tester.getSemantics(find.byType(NetworkHeaderMenuButton)).label,
        'Close menu',
      );
      handle.dispose();
    });
  });

  group('NetworkOverrideEditor', () {
    OverrideRule? saved;

    Future<void> pumpEditor(WidgetTester tester, OverrideRule draft) async {
      saved = null;
      await tester.pumpWidget(
        host(
          NetworkOverrideEditor(
            draft: draft,
            saveLabel: 'Add',
            onSave: (rule) => saved = rule,
            onCancel: () {},
          ),
        ),
      );
    }

    OverrideRule draft({String pattern = '*api*'}) => OverrideRule(
      id: 'r1',
      enabled: true,
      urlPattern: pattern,
      kind: OverrideRuleKind.respond,
      status: 500,
      body: '',
      createdAt: 0,
    );

    testWidgets('offers every outcome the RN grid does', (tester) async {
      await pumpEditor(tester, draft());
      for (final label in const [
        'Server error',
        'Unauthorized',
        'Not found',
        'Forbidden',
        'Rate limited',
        'Unavailable',
        'Bad request',
        'Success',
        'Offline',
        'Timeout',
        'Real response',
      ]) {
        expect(find.text(label), findsOneWidget, reason: 'missing $label');
      }
    });

    testWidgets('picking an outcome writes the right kind AND status', (
      tester,
    ) async {
      await pumpEditor(tester, draft());

      await tapText(tester, 'Not found');
      await tapText(tester, 'Add');
      expect(saved!.kind, OverrideRuleKind.respond);
      expect(saved!.status, 404);
    });

    testWidgets('Offline and Timeout produce fail rules, not statuses', (
      tester,
    ) async {
      await pumpEditor(tester, draft());

      await tapText(tester, 'Offline');
      await tapText(tester, 'Add');
      expect(saved!.kind, OverrideRuleKind.fail);
      expect(saved!.failKind, OverrideFailKind.network);

      await tapText(tester, 'Timeout');
      await tapText(tester, 'Add');
      expect(saved!.failKind, OverrideFailKind.timeout);
    });

    testWidgets('Real response is the delay kind — the request still runs', (
      tester,
    ) async {
      await pumpEditor(tester, draft());
      await tapText(tester, 'Real response');
      await tapText(tester, 'Add');
      expect(saved!.kind, OverrideRuleKind.delay);
    });

    testWidgets('the FIRES row maps to times/alternate', (tester) async {
      await pumpEditor(tester, draft());

      await tapText(tester, 'Once');
      await tapText(tester, 'Add');
      expect(saved!.times, 1);
      expect(saved!.alternate, isFalse);

      await tapText(tester, 'Every other');
      await tapText(tester, 'Add');
      expect(saved!.alternate, isTrue);
      expect(saved!.times, isNull);

      await tapText(tester, 'Always');
      await tapText(tester, 'Add');
      expect(saved!.times, isNull);
      expect(saved!.alternate, isFalse);
    });

    testWidgets('the DELAY row writes milliseconds', (tester) async {
      await pumpEditor(tester, draft());
      await tapText(tester, '3s');
      await tapText(tester, 'Add');
      expect(saved!.delayMs, 3000);
    });

    testWidgets('Save is disabled until the rule catches something', (
      tester,
    ) async {
      // A rule with no pattern would match nothing and silently do nothing —
      // the exact failure this feature must never ship.
      await pumpEditor(tester, draft(pattern: ''));
      await tapText(tester, 'Add');
      expect(saved, isNull);
    });

    testWidgets('the body section only exists for respond rules', (
      tester,
    ) async {
      await pumpEditor(tester, draft());
      expect(find.text('Response body'), findsOneWidget);

      await tapText(tester, 'Offline');
      // A failure has no body to serve, so offering the editor would be a lie.
      expect(find.text('Response body'), findsNothing);
    });

    testWidgets('a JSON body renders as a tree, not a text blob', (
      tester,
    ) async {
      await pumpEditor(
        tester,
        draft()..body = '{"name":"eevee","id":133}',
      );
      await tapText(tester, 'Response body');
      await tester.pumpAndSettle();

      expect(find.textContaining('eevee'), findsWidgets);
      expect(find.text('Edit all'), findsOneWidget);
    });
  });

  group('NetworkOverridesScreen', () {
    testWidgets('empty state names the control that actually exists', (
      tester,
    ) async {
      await tester.pumpWidget(host(const NetworkOverridesScreen()));
      await tester.pump();
      expect(find.text('Nothing overridden'), findsOneWidget);
      expect(
        find.textContaining('tap Override'),
        findsOneWidget,
        reason: 'the empty state must point at a real button',
      );
    });

    testWidgets('a live rule shows the master bar and its hit count', (
      tester,
    ) async {
      OverrideRulesStore.instance.upsertRule(
        OverrideRule(
          id: 'a',
          enabled: true,
          urlPattern: '*pokeapi*',
          kind: OverrideRuleKind.respond,
          status: 500,
          hits: 4,
          createdAt: 0,
        ),
      );
      await tester.pumpWidget(host(const NetworkOverridesScreen()));
      await tester.pump();

      expect(find.text('1 override is on'), findsOneWidget);
      expect(find.text('Turn all off'), findsOneWidget);
      expect(find.text('500'), findsOneWidget);
      expect(find.text('4'), findsOneWidget, reason: 'hit count');
      await drainStore(tester);
    });

    testWidgets('Turn all off kills every rule without losing them', (
      tester,
    ) async {
      OverrideRulesStore.instance.upsertRule(
        OverrideRule(
          id: 'a',
          enabled: true,
          urlPattern: '*',
          kind: OverrideRuleKind.respond,
          createdAt: 0,
        ),
      );
      await tester.pumpWidget(host(const NetworkOverridesScreen()));
      await tester.pump();

      await tapText(tester, 'Turn all off');

      expect(OverrideRulesStore.instance.enabled, isFalse);
      expect(OverrideRulesStore.instance.rules, hasLength(1));
      expect(find.text('Turn on'), findsOneWidget);
      await drainStore(tester);
    });

    testWidgets('+ opens the editor for a new rule', (tester) async {
      await tester.pumpWidget(host(const NetworkOverridesScreen()));
      await tester.pump();

      final handle = tester.ensureSemantics();
      await tester.tap(find.bySemanticsLabel('New override rule'));
      await tester.pumpAndSettle();

      expect(find.text('Add'), findsOneWidget);
      expect(find.text('Server error'), findsOneWidget);
      handle.dispose();
      await drainStore(tester);
    });

    testWidgets('tapping a rule opens it for editing, not creation', (
      tester,
    ) async {
      OverrideRulesStore.instance.upsertRule(
        OverrideRule(
          id: 'a',
          enabled: true,
          urlPattern: '*pokeapi*',
          kind: OverrideRuleKind.respond,
          status: 503,
          createdAt: 0,
        ),
      );
      await tester.pumpWidget(host(const NetworkOverridesScreen()));
      await tester.pump();

      await tapText(tester, '503');
      await tester.pumpAndSettle();

      expect(find.text('Save'), findsOneWidget, reason: 'editing, not adding');
      await drainStore(tester);
    });

    testWidgets('the toggle disables one rule and keeps it in the list', (
      tester,
    ) async {
      OverrideRulesStore.instance.upsertRule(
        OverrideRule(
          id: 'a',
          enabled: true,
          urlPattern: '*',
          kind: OverrideRuleKind.respond,
          createdAt: 0,
        ),
      );
      await tester.pumpWidget(host(const NetworkOverridesScreen()));
      await tester.pump();

      final handle = tester.ensureSemantics();
      await tester.tap(find.bySemanticsLabel('Turn rule off'));
      await tester.pump();

      expect(OverrideRulesStore.instance.rules.single.enabled, isFalse);
      expect(OverrideRulesStore.instance.rules, hasLength(1));
      handle.dispose();
      await drainStore(tester);
    });
  });
}
