import 'package:buoy_core/buoy_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('BuoyOverlayHost registry', () {
    test('register appends a builder and returns a working unregister', () {
      final host = BuoyOverlayHost.instance;
      final startLen = host.listenable.value.length;

      builderA(BuildContext _) => const SizedBox();
      final remove = host.register(builderA);
      expect(host.listenable.value.length, startLen + 1);
      expect(host.listenable.value, contains(builderA));

      remove();
      expect(host.listenable.value.length, startLen);
      expect(host.listenable.value, isNot(contains(builderA)));

      // Unregister is idempotent.
      remove();
      expect(host.listenable.value.length, startLen);
    });
  });

  group('BuoyDevTools overlay layer', () {
    // BuoyDevTools starts the desktop-sync socket in initState, which leaves a
    // reconnection Timer pending. Dispose it before the test's invariant check.
    Future<void> stopSync(WidgetTester tester) async {
      Buoy.sync?.dispose();
      await tester.pump();
    }

    testWidgets('builds with no overlays registered', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: BuoyDevTools(child: Text('app-child')),
        ),
      );
      await tester.pump();
      expect(find.text('app-child'), findsOneWidget);
      await stopSync(tester);
    });

    testWidgets('renders a registered overlay builder, then removes it',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: BuoyDevTools(child: Text('app-child')),
        ),
      );
      await tester.pump();

      const overlayKey = Key('test-overlay');
      final remove = BuoyOverlayHost.instance.register(
        (_) => const Positioned(
          left: 0,
          top: 0,
          child: SizedBox(key: overlayKey, width: 10, height: 10),
        ),
      );
      await tester.pump();
      expect(find.byKey(overlayKey), findsOneWidget);

      remove();
      await tester.pump();
      expect(find.byKey(overlayKey), findsNothing);
      // App child is never disturbed by overlay changes.
      expect(find.text('app-child'), findsOneWidget);
      await stopSync(tester);
    });
  });
}
