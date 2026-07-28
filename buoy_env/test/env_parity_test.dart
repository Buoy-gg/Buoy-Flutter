// Parity tests for the buoy_env validation model, asserted against
// RN-derived expected values (packages/env-tools/src/env/utils).
import 'package:buoy_env/buoy_env.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('getEnvVarType (envTypeDetector.ts parity)', () {
    test('native Dart types', () {
      expect(getEnvVarType(true), EnvVarType.boolean);
      expect(getEnvVarType(false), EnvVarType.boolean);
      expect(getEnvVarType(42), EnvVarType.number);
      expect(getEnvVarType(3.14), EnvVarType.number);
      expect(getEnvVarType([1, 2]), EnvVarType.array);
      expect(getEnvVarType({'a': 1}), EnvVarType.object);
      expect(getEnvVarType(null), EnvVarType.unknown);
    });

    test('JSON-looking strings', () {
      expect(getEnvVarType('{"a":1}'), EnvVarType.object);
      expect(getEnvVarType('[1,2,3]'), EnvVarType.array);
      // Malformed JSON falls back to string.
      expect(getEnvVarType('{not json}'), EnvVarType.string);
    });

    test('boolean-word strings', () {
      for (final w in [
        'true',
        'false',
        'enabled',
        'disabled',
        'yes',
        'no',
        'on',
        'off',
        'TRUE',
        'Off',
      ]) {
        expect(getEnvVarType(w), EnvVarType.boolean, reason: w);
      }
    });

    test('numeric strings (incl. 0 and 1 as numbers, not booleans)', () {
      expect(getEnvVarType('42'), EnvVarType.number);
      expect(getEnvVarType('0'), EnvVarType.number);
      expect(getEnvVarType('1'), EnvVarType.number);
      expect(getEnvVarType('3.14'), EnvVarType.number);
      expect(getEnvVarType('-5'), EnvVarType.number);
    });

    test('url / comma-array / plain string / empty', () {
      expect(getEnvVarType('https://api.example.com'), EnvVarType.url);
      expect(getEnvVarType('http://x'), EnvVarType.url);
      expect(getEnvVarType('a,b,c'), EnvVarType.array);
      expect(getEnvVarType('hello'), EnvVarType.string);
      expect(getEnvVarType(''), EnvVarType.string);
    });

    test('wire strings are lowercase RN names', () {
      expect(EnvVarType.url.wire, 'url');
      expect(EnvVarType.boolean.wire, 'boolean');
    });
  });

  group('processEnvVars (utils.ts parity)', () {
    test('classifies missing / wrong-value / wrong-type / present / optional',
        () {
      final collected = {
        'API_URL': 'https://x.com',
        'ENVIRONMENT': 'development',
        'MAX': '10',
        'DEBUG': 'not_a_number',
        'EXTRA': 'hi',
      };
      final required = [
        envVar('API_URL').withType('url').build(), // present
        const RequiredEnvVar.value('ENVIRONMENT', 'production'), // wrong value
        envVar('MAX').withType('number').build(), // present
        envVar('DEBUG').withType('number').build(), // wrong type
        const RequiredEnvVar.exists('SECRET'), // missing
      ];
      final res = processEnvVars(collected, required);

      final byKey = {for (final v in res.requiredVars) v.key: v.status};
      expect(byKey['API_URL'], EnvVarStatus.requiredPresent);
      expect(byKey['ENVIRONMENT'], EnvVarStatus.requiredWrongValue);
      expect(byKey['MAX'], EnvVarStatus.requiredPresent);
      expect(byKey['DEBUG'], EnvVarStatus.requiredWrongType);
      expect(byKey['SECRET'], EnvVarStatus.requiredMissing);

      // EXTRA is optional (present, not required).
      expect(res.optionalVars.map((v) => v.key), ['EXTRA']);
      expect(res.optionalVars.single.status, EnvVarStatus.optionalPresent);
    });

    test('required sort order: missing, wrong_value, wrong_type, present', () {
      final res = processEnvVars(
        {'B': 'x', 'C': 'y', 'D': 'https://z.com'},
        [
          envVar('D').withType('url').build(), // present
          const RequiredEnvVar.value('B', 'other'), // wrong value
          const RequiredEnvVar.exists('A'), // missing
          envVar('C').withType('number').build(), // wrong type
        ],
      );
      expect(res.requiredVars.map((v) => v.key), ['A', 'B', 'C', 'D']);
    });

    test('expectedValue special cases sk_* and "production or development"', () {
      final res = processEnvVars(
        {'KEY': 'sk_live_123', 'ENV': 'staging', 'ENV2': 'production'},
        const [
          RequiredEnvVar.value('KEY', 'sk_*'),
          RequiredEnvVar.value('ENV', 'production or development'),
          RequiredEnvVar.value('ENV2', 'production or development'),
        ],
      );
      final byKey = {for (final v in res.requiredVars) v.key: v.status};
      expect(byKey['KEY'], EnvVarStatus.requiredPresent); // startsWith sk_
      expect(byKey['ENV'], EnvVarStatus.requiredWrongValue); // staging
      expect(byKey['ENV2'], EnvVarStatus.requiredPresent);
    });
  });

  group('calculateStats + health math (utils.ts + EnvVarsModal parity)', () {
    test('counts + health percentage + status label', () {
      final collected = {
        'API_URL': 'https://x.com', // present
        'ENVIRONMENT': 'development', // wrong value
        'MAX': '10', // present
        'DEBUG': 'not_a_number', // wrong type
        'EXTRA': 'hi', // optional
      };
      final required = [
        envVar('API_URL').withType('url').build(),
        const RequiredEnvVar.value('ENVIRONMENT', 'production'),
        envVar('MAX').withType('number').build(),
        envVar('DEBUG').withType('number').build(),
        const RequiredEnvVar.exists('SECRET'), // missing
      ];
      final res = processEnvVars(collected, required);
      final stats = calculateStats(res.requiredVars, res.optionalVars, collected);

      expect(stats.totalCount, 5);
      expect(stats.requiredCount, 5);
      expect(stats.missingCount, 1);
      expect(stats.wrongValueCount, 1);
      expect(stats.wrongTypeCount, 1);
      expect(stats.presentRequiredCount, 2);
      expect(stats.optionalCount, 1);

      // 2/5 = 40% → CRITICAL.
      expect(healthPercentage(stats), 40);
      expect(healthStatusLabel(40), 'CRITICAL');
    });

    test('health status thresholds', () {
      expect(healthStatusLabel(100), 'HEALTHY');
      expect(healthStatusLabel(80), 'WARNING');
      expect(healthStatusLabel(75), 'WARNING');
      expect(healthStatusLabel(60), 'ERROR');
      expect(healthStatusLabel(50), 'ERROR');
      expect(healthStatusLabel(49), 'CRITICAL');
    });

    test('no required vars → 100% healthy', () {
      final res = processEnvVars({'A': 'x'}, const []);
      final stats = calculateStats(res.requiredVars, res.optionalVars, {'A': 'x'});
      expect(healthPercentage(stats), 100);
      expect(healthStatusLabel(100), 'HEALTHY');
    });
  });

  group('RequiredEnvVar wire shape (envSyncAdapter.ts parity)', () {
    test('exists → bare String', () {
      expect(const RequiredEnvVar.exists('FOO').toJson(), 'FOO');
    });

    test('value → {key, expectedValue, description?}', () {
      expect(
        const RequiredEnvVar.value('ENV', 'prod').toJson(),
        {'key': 'ENV', 'expectedValue': 'prod'},
      );
      expect(
        const RequiredEnvVar.value('ENV', 'prod', description: 'd').toJson(),
        {'key': 'ENV', 'expectedValue': 'prod', 'description': 'd'},
      );
    });

    test('type → {key, expectedType(wire), description?}', () {
      expect(
        RequiredEnvVar.type('N', EnvVarType.number).toJson(),
        {'key': 'N', 'expectedType': 'number'},
      );
      expect(
        envVar('U').withType('url').withDescription('link').build().toJson(),
        {'key': 'U', 'expectedType': 'url', 'description': 'link'},
      );
    });

    test('fromJson round-trips String and Map forms', () {
      expect(RequiredEnvVar.fromJson('FOO').expectedValue, isNull);
      expect(RequiredEnvVar.fromJson('FOO').key, 'FOO');
      final v = RequiredEnvVar.fromJson(
          {'key': 'ENV', 'expectedValue': 'prod', 'description': 'd'});
      expect(v.key, 'ENV');
      expect(v.expectedValue, 'prod');
      expect(v.description, 'd');
      final t = RequiredEnvVar.fromJson({'key': 'N', 'expectedType': 'boolean'});
      expect(t.expectedType, EnvVarType.boolean);
    });
  });

  group('envVar builder + createEnvVarConfig (helpers.ts parity)', () {
    test('withType then withValue clears type (mutually exclusive)', () {
      final built = envVar('X').withType('number').withValue('5').build();
      expect(built.expectedType, isNull);
      expect(built.expectedValue, '5');
    });

    test('withValue then withType clears value', () {
      final built = envVar('X').withValue('5').withType('number').build();
      expect(built.expectedValue, isNull);
      expect(built.expectedType, EnvVarType.number);
    });

    test('neither → existence check', () {
      final built = envVar('X').build();
      expect(built.expectedType, isNull);
      expect(built.expectedValue, isNull);
      expect(built.toJson(), 'X');
    });

    test('createEnvVarConfig coerces bare String keys to existence checks', () {
      final cfg = createEnvVarConfig([
        'PLAIN',
        const RequiredEnvVar.value('V', 'x'),
      ]);
      expect(cfg[0].toJson(), 'PLAIN');
      expect(cfg[1].expectedValue, 'x');
    });
  });

  group('BuoyEnv store', () {
    tearDown(() => BuoyEnv.instance.resetForTest());

    test('configure merges vars and sets required, notifies subscribers', () {
      var notified = 0;
      final unsub = BuoyEnv.instance.subscribe(() => notified++);
      BuoyEnv.instance.configure(vars: {'A': '1'});
      BuoyEnv.instance.configure(
        vars: {'B': '2'},
        requiredEnvVars: const [RequiredEnvVar.exists('A')],
      );
      expect(BuoyEnv.instance.vars, {'A': '1', 'B': '2'});
      expect(BuoyEnv.instance.requiredEnvVars.single.key, 'A');
      expect(notified, 2);
      unsub();
    });
  });
}
