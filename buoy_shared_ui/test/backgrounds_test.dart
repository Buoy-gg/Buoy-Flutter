// Pins the tool-background subsystem's pure logic against the RN source:
// mulberry32 must be BIT-EXACT (a different stream is a different sky), and
// the registry / store must round-trip the full RN catalogue.
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:buoy_shared_ui/src/backgrounds/painting.dart';
import 'package:buoy_shared_ui/src/backgrounds/rng.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('mulberry32 (rng.ts)', () {
    // Captured from node with the RN implementation.
    const expected = {
      1: [0.627073940588, 0.002735721180, 0.527447039960, 0.981050967472, 0.968377898214, 0.281103502959],
      0x5747 ^ 260: [0.290747377789, 0.755926552229, 0.279497788986, 0.607347688405, 0.561873808736, 0.154607729055],
      0x61f3: [0.221191293560, 0.763019677252, 0.708977777977, 0.701153528178, 0.274343731347, 0.936012253631],
    };
    for (final entry in expected.entries) {
      test('seed ${entry.key} matches JS', () {
        final rnd = mulberry32(entry.key);
        for (final want in entry.value) {
          expect(rnd(), closeTo(want, 1e-11));
        }
      });
    }
    test('scatter is deterministic and in [0,1)', () {
      final a = scatter(0xd7a3, 42);
      final b = scatter(0xd7a3, 42);
      expect(a, b);
      expect(a.every((v) => v >= 0 && v < 1), isTrue);
    });
  });

  group('clock helpers', () {
    test('loopPhase and pulsePhase', () {
      expect(loopPhase(0, 10), 0);
      expect(loopPhase(15, 10), closeTo(0.5, 1e-9));
      expect(pulsePhase(0, 10), 0);
      expect(pulsePhase(5, 10), closeTo(1, 1e-9));
      expect(pulsePhase(10, 10), closeTo(0, 1e-9));
    });
    test('interpolate clamps and is piecewise linear', () {
      expect(interpolate(-1, [0, 1], [0, 10]), 0);
      expect(interpolate(2, [0, 1], [0, 10]), 10);
      expect(interpolate(0.25, [0, 0.25, 0.5, 0.75, 1], [0, 4, 0, -4, 0]), 4);
      expect(interpolate(0.375, [0, 0.25, 0.5, 0.75, 1], [0, 4, 0, -4, 0]), closeTo(2, 1e-9));
    });
    test('flattenOver is pixel-identical to compositing', () {
      final c = flattenOver(const Color(0xFFFFFFFF), 0.5, const Color(0xFF000000));
      expect(c.toARGB32(), 0xFF808080);
    });
  });

  group('registry + store', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('default is off; unrenderable ids map to Off', () {
      expect(defaultBackground, BackgroundId.off);
      expect(getPreset(BackgroundId.livesky).id, BackgroundId.off);
      expect(getPreset(BackgroundId.deepfield).builder, isNull);
      expect(getPreset(BackgroundId.hyperspace).builder, isNotNull);
    });
    test('presetAt wraps both ways', () {
      expect(presetAt(-1).id, backgroundPresets.last.id);
      expect(presetAt(backgroundPresets.length).id, BackgroundId.off);
    });
    test('the persisted key matches RN', () {
      expect(backgroundStorageKey, '@react_buoy_tool_background_v3');
    });
    test('step persists and re-homes the folded Meteors preset on load', () async {
      SharedPreferences.setMockInitialValues({
        backgroundStorageKey: '{"id":"meteors"}',
      });
      final store = BackgroundStore.instance;
      var notified = 0;
      store.addListener(() => notified++);
      await Future<void>.delayed(Duration.zero);
      expect(store.id, BackgroundId.deepfield, reason: 'meteors → deepfield');
      expect(notified, 1);
      store.setId(BackgroundId.hyperspace);
      expect(store.index, presetIndex(BackgroundId.hyperspace));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(backgroundStorageKey), contains('"hyperspace"'));
    });
  });
}
