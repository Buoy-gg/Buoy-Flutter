import 'dart:convert';

import 'package:buoy_core/buoy_core.dart';
import 'package:buoy_core/src/core/dial_usage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('dial usage scoring', () {
    test('decayScore halves after one half-life and is 0 when absent', () {
      const entry = UsageEntry(score: 2, lastUsed: 0);
      expect(decayScore(null, 0), 0);
      expect(decayScore(entry, 0), 2);
      expect(decayScore(entry, usageHalfLifeMs), closeTo(1, 1e-9));
      // Clock skew (lastUsed in the future) never boosts the score.
      expect(decayScore(const UsageEntry(score: 2, lastUsed: 100), 0), 2);
    });

    test('recordUsage decays the old score before adding 1', () {
      var map = recordUsage(<String, UsageEntry>{}, 'network', 0);
      expect(map['network']!.score, 1);
      map = recordUsage(map, 'network', usageHalfLifeMs);
      expect(map['network']!.score, closeTo(1.5, 1e-9));
      expect(map['network']!.lastUsed, usageHalfLifeMs);
    });

    test('rankToolIds sorts by score with stable registration-order ties', () {
      final map = {
        'storage': const UsageEntry(score: 5, lastUsed: 0),
        'network': const UsageEntry(score: 1, lastUsed: 0),
      };
      expect(
        rankToolIds(['env', 'network', 'storage', 'redux'], map, 0),
        ['storage', 'network', 'env', 'redux'],
      );
    });

    test('pruneUsage drops entries decayed below the minimum score', () {
      final map = {
        'fresh': const UsageEntry(score: 1, lastUsed: 0),
        'stale': const UsageEntry(score: 0.010001, lastUsed: 0),
      };
      final pruned = pruneUsage(map, usageHalfLifeMs);
      expect(pruned.keys, ['fresh']);
    });
  });

  group('BuoyStorage dial usage', () {
    test('recordDialToolUsage persists and ranking reflects it', () async {
      final storage = BuoyStorage();
      await storage.loadDialUsage();
      await storage.recordDialToolUsage('storage');
      expect(
        storage.rankDialToolIds(['env', 'network', 'storage']),
        ['storage', 'env', 'network'],
      );

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('@react_buoy_dial_usage');
      final decoded = jsonDecode(raw!) as Map<String, Object?>;
      expect(decoded['storage'], containsPair('score', 1));
      storage.dispose();
    });

    test('a new BuoyStorage loads persisted usage (RN JSON shape)', () async {
      SharedPreferences.setMockInitialValues({
        '@react_buoy_dial_usage': jsonEncode({
          'network': {
            'score': 3,
            'lastUsed': DateTime.now().millisecondsSinceEpoch,
          },
        }),
      });
      final storage = BuoyStorage();
      await storage.loadDialUsage();
      expect(storage.isDialUsageLoaded, isTrue);
      expect(
        storage.rankDialToolIds(['env', 'network']),
        ['network', 'env'],
      );

      await storage.resetDialUsage();
      expect(storage.rankDialToolIds(['env', 'network']), ['env', 'network']);
      storage.dispose();
    });
  });
}
