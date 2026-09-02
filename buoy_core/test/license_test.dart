// Ports the tier-decision cases of packages/license/src/__tests__ and pins
// the FLUTTER_TIER_PORT.md acceptance list: free announces free, paid
// announces pro, invalid is anonymous without crashing, offline keeps the
// last tier, and a cleared key STAYS cleared under an in-flight validation.
import 'dart:async';
import 'dart:convert';

import 'package:buoy_core/buoy_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

KeygenValidation _verdict({
  String code = 'VALID',
  bool valid = true,
  bool hasLicense = true,
  String? policyId,
  String? plan,
  String? detail,
}) =>
    KeygenValidation(
      valid: valid,
      code: code,
      detail: detail,
      hasLicense: hasLicense,
      policyId: policyId,
      metadataPlan: plan,
    );

Future<String?> _rawCache() async =>
    (await SharedPreferences.getInstance()).getString(licenseCacheStorageKey);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('resolveTier (tier.ts)', () {
    test('free policy → free', () {
      expect(resolveTier(policyId: KeygenConfig.policyFree), BuoyTier.free);
    });
    test('solo and business policies → pro', () {
      expect(resolveTier(policyId: KeygenConfig.policySolo), BuoyTier.pro);
      expect(resolveTier(policyId: KeygenConfig.policyBusiness), BuoyTier.pro);
    });
    test('unknown policy falls back to metadata.plan, then pro on purpose', () {
      expect(resolveTier(policyId: 'not-a-policy', metadataPlan: 'free'), BuoyTier.free);
      expect(resolveTier(policyId: 'not-a-policy'), BuoyTier.pro);
      expect(resolveTier(), BuoyTier.pro);
    });
  });

  group('tierAfterFatalError', () {
    test('EXPIRED is free, every other fatal code is anonymous', () {
      expect(tierAfterFatalError('EXPIRED'), BuoyTier.free);
      for (final code in ['NOT_FOUND', 'SUSPENDED', 'BANNED', 'PRODUCT_SCOPE_MISMATCH']) {
        expect(tierAfterFatalError(code), BuoyTier.anonymous, reason: code);
        expect(isFatalLicenseCode(code), isTrue, reason: code);
      }
      expect(isFatalLicenseCode('TOO_MANY_MACHINES'), isFalse);
    });
  });

  group('KeygenValidation.fromJson', () {
    test('reads the policy id and metadata plan; tolerates null data', () {
      final parsed = KeygenValidation.fromJson(jsonDecode('''
        {"meta":{"valid":true,"code":"VALID","detail":"is valid"},
         "data":{"attributes":{"metadata":{"plan":"free"}},
                 "relationships":{"policy":{"data":{"type":"policies","id":"${KeygenConfig.policyFree}"}}}}}
      ''') as Map<String, Object?>);
      expect(parsed.valid, isTrue);
      expect(parsed.policyId, KeygenConfig.policyFree);
      expect(parsed.metadataPlan, 'free');
      expect(parsed.hasLicense, isTrue);

      final notFound = KeygenValidation.fromJson(
        {'meta': {'valid': false, 'code': 'NOT_FOUND', 'detail': 'does not exist'}, 'data': null},
      );
      expect(notFound.hasLicense, isFalse);
      expect(notFound.code, 'NOT_FOUND');
    });
  });

  group('BuoyLicenseManager', () {
    test('a free key announces free and isPro false (acceptance 1)', () async {
      final m = BuoyLicenseManager(
        validator: (_) async => _verdict(policyId: KeygenConfig.policyFree),
      );
      await m.setLicenseKey('free-key');
      expect(m.state.value.tier, BuoyTier.free);
      expect(m.state.value.isPro, isFalse);
      expect(m.state.value.licenseKey, 'FREE-KEY');
      expect(await _rawCache(), contains('"tier":"free"'));
    });

    test('a paid key announces pro (acceptance 2)', () async {
      final m = BuoyLicenseManager(
        validator: (_) async => _verdict(policyId: KeygenConfig.policySolo),
      );
      await m.setLicenseKey('paid');
      expect(m.state.value.tier, BuoyTier.pro);
      expect(m.state.value.error, isNull);
    });

    test('an invalid key is anonymous, does not throw, clears the cache (acceptance 3)', () async {
      SharedPreferences.setMockInitialValues({
        licenseCacheStorageKey: jsonEncode({
          'v': 1, 'licenseKey': 'BAD', 'tier': 'pro',
          'validatedAt': DateTime.now().subtract(const Duration(days: 2)).millisecondsSinceEpoch,
        }),
      });
      final m = BuoyLicenseManager(
        validator: (_) async =>
            _verdict(valid: false, code: 'NOT_FOUND', hasLicense: false, detail: 'nope'),
      );
      await m.setLicenseKey('bad');
      expect(m.state.value.tier, BuoyTier.anonymous);
      expect(m.state.value.error, 'nope');
      expect(await _rawCache(), isNull);
    });

    test('EXPIRED drops to free, not anonymous', () async {
      final m = BuoyLicenseManager(
        validator: (_) async => _verdict(valid: false, code: 'EXPIRED', detail: 'expired'),
      );
      await m.setLicenseKey('lapsed');
      expect(m.state.value.tier, BuoyTier.free);
    });

    test('offline keeps the cached tier and never downgrades (acceptance 4)', () async {
      SharedPreferences.setMockInitialValues({
        licenseCacheStorageKey: jsonEncode({
          'v': 1, 'licenseKey': 'PAID', 'tier': 'pro',
          'validatedAt': DateTime.now().subtract(const Duration(days: 2)).millisecondsSinceEpoch,
        }),
      });
      var calls = 0;
      final m = BuoyLicenseManager(
        validator: (_) async {
          calls++;
          throw const LicenseTransportError('offline', null);
        },
        retryDelays: const [],
      );
      await m.setLicenseKey('paid');
      expect(calls, 1, reason: 'a 2-day-old cache is valid but not fresh → revalidates');
      expect(m.state.value.tier, BuoyTier.pro);
      expect(m.state.value.error, isNull, reason: 'a transport failure with a cache is silent');
      expect(await _rawCache(), isNotNull);
    });

    test('offline with NO cache leaves anonymous with a transport error, then retries', () async {
      var calls = 0;
      final m = BuoyLicenseManager(
        validator: (_) async {
          calls++;
          if (calls == 1) throw const LicenseTransportError('HTTP 429', 429);
          return _verdict(policyId: KeygenConfig.policySolo);
        },
        retryDelays: const [Duration(milliseconds: 10)],
      );
      await m.setLicenseKey('paid');
      expect(m.state.value.tier, BuoyTier.anonymous);
      expect(m.state.value.error, 'HTTP 429');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(calls, 2);
      expect(m.state.value.tier, BuoyTier.pro);
      expect(m.state.value.error, isNull);
    });

    test('a fresh cache skips the network entirely (quota guard)', () async {
      SharedPreferences.setMockInitialValues({
        licenseCacheStorageKey: jsonEncode({
          'v': 1, 'licenseKey': 'PAID', 'tier': 'pro',
          'validatedAt': DateTime.now().millisecondsSinceEpoch,
        }),
      });
      var calls = 0;
      final m = BuoyLicenseManager(validator: (_) async {
        calls++;
        return _verdict(policyId: KeygenConfig.policySolo);
      });
      await m.setLicenseKey('paid');
      expect(calls, 0);
      expect(m.state.value.tier, BuoyTier.pro);
      await m.setLicenseKey('paid', force: true);
      expect(calls, 1, reason: 'force always hits the network');
    });

    test('the cache cannot stand in for a DIFFERENT key', () async {
      SharedPreferences.setMockInitialValues({
        licenseCacheStorageKey: jsonEncode({
          'v': 1, 'licenseKey': 'PAID', 'tier': 'pro',
          'validatedAt': DateTime.now().millisecondsSinceEpoch,
        }),
      });
      final m = BuoyLicenseManager(
        validator: (_) async => throw const LicenseTransportError('offline', null),
        retryDelays: const [],
      );
      await m.setLicenseKey('typo');
      expect(m.state.value.tier, BuoyTier.anonymous);
      expect(m.state.value.error, 'offline');
    });

    test('clearing while a validation is in flight wins (acceptance 5, the race guard)', () async {
      final gate = Completer<KeygenValidation>();
      final m = BuoyLicenseManager(validator: (_) => gate.future);
      final pending = m.setLicenseKey('paid');
      // Let setLicenseKey get past its cache read and into the request.
      await Future<void>.delayed(Duration.zero);
      expect(m.state.value.isValidating, isTrue);

      await m.clearLicense();
      gate.complete(_verdict(policyId: KeygenConfig.policySolo));
      await pending;

      expect(m.state.value.tier, BuoyTier.anonymous);
      expect(m.state.value.licenseKey, isNull);
      expect(m.state.value.isValidating, isFalse);
      expect(await _rawCache(), isNull, reason: 'the stale answer must not re-persist the cache');
    });

    test('a newer key supersedes an older in-flight one', () async {
      final first = Completer<KeygenValidation>();
      final m = BuoyLicenseManager(validator: (key) {
        if (key == 'OLD') return first.future;
        return Future.value(_verdict(policyId: KeygenConfig.policyFree));
      });
      final old = m.setLicenseKey('old');
      await Future<void>.delayed(Duration.zero);
      await m.setLicenseKey('new');
      first.complete(_verdict(policyId: KeygenConfig.policySolo));
      await old;
      expect(m.state.value.tier, BuoyTier.free);
      expect(m.state.value.licenseKey, 'NEW');
    });

    test('empty / null key clears', () async {
      final m = BuoyLicenseManager(
        validator: (_) async => _verdict(policyId: KeygenConfig.policySolo),
      );
      await m.setLicenseKey('paid');
      expect(m.state.value.isPro, isTrue);
      await m.setLicenseKey('   ');
      expect(m.state.value.tier, BuoyTier.anonymous);
      expect(await _rawCache(), isNull);
    });
  });
}
