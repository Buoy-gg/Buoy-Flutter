/// Ports the tier-resolving core of packages/license/src/LicenseManager.ts:
/// validate once, cache the verdict, fail OPEN on transport errors, and never
/// let an in-flight validation resurrect a key the user just removed.
/// Scope A of FLUTTER_TIER_PORT.md — no device registration, no fingerprint,
/// no weekend pass; those are RN-only until Scope B.
///
/// PROPRIETARY — Buoy Pro license enforcement. NOT open source.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show ValueNotifier, debugPrint, visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

import 'keygen.dart';

/// What the rest of the SDK reads: the resolved tier plus enough context for
/// the settings modal to explain it.
class BuoyLicenseState {
  const BuoyLicenseState({
    this.tier = BuoyTier.anonymous,
    this.licenseKey,
    this.isValidating = false,
    this.error,
  });

  final BuoyTier tier;
  final String? licenseKey;
  final bool isValidating;

  /// The last verdict or transport failure, for display. Null when healthy.
  final String? error;

  bool get isPro => tier == BuoyTier.pro;

  BuoyLicenseState copyWith({
    BuoyTier? tier,
    String? licenseKey,
    bool clearKey = false,
    bool? isValidating,
    String? error,
    bool clearError = false,
  }) {
    return BuoyLicenseState(
      tier: tier ?? this.tier,
      licenseKey: clearKey ? null : (licenseKey ?? this.licenseKey),
      isValidating: isValidating ?? this.isValidating,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

typedef LicenseValidator = Future<KeygenValidation> Function(String licenseKey);

/// Storage key for the cached verdict. Deliberately OUTSIDE the `@react_buoy`
/// prefix (same as RN's `buoy-gg-license`), so the settings modal's CLEAR ALL
/// SETTINGS never wipes a paying customer's licence.
const String licenseCacheStorageKey = 'buoy-gg-license';

/// Cache duration: 30 days (RN `LICENSE_CACHE_DURATION`).
const Duration licenseCacheDuration = Duration(days: 30);

/// Skip launch-time revalidation when the cache was validated this recently
/// (RN `LICENSE_LAUNCH_VALIDATION_TTL`). Every launch AND every hot restart
/// lands in [BuoyLicenseManager.setLicenseKey]; without this, each one costs a
/// Keygen request against the account's daily quota.
const Duration licenseLaunchValidationTtl = Duration(hours: 1);

/// Backoff for a validation that failed in transit with no cache to fall back
/// on (RN `LICENSE_TRANSIENT_RETRY_DELAYS`). Short and finite on purpose: it
/// is there to survive a blip, not to hammer a server already refusing us.
const List<Duration> licenseTransientRetryDelays = [
  Duration(seconds: 5),
  Duration(seconds: 20),
  Duration(minutes: 1),
  Duration(minutes: 5),
  Duration(minutes: 15),
];

/// The cached verdict. Flutter's cache is its own (v1) — it does NOT share
/// RN's signed blob format; see the "Known Dart-vs-JS traps" note in
/// FLUTTER_TIER_PORT.md.
class _CachedLicense {
  const _CachedLicense({
    required this.licenseKey,
    required this.tier,
    required this.validatedAt,
  });

  final String licenseKey;
  final BuoyTier tier;
  final DateTime validatedAt;

  Map<String, Object?> toJson() => {
        'v': 1,
        'licenseKey': licenseKey,
        'tier': tier.name,
        'validatedAt': validatedAt.millisecondsSinceEpoch,
      };

  static _CachedLicense? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final key = raw['licenseKey'];
    final tierName = raw['tier'];
    final validatedAt = raw['validatedAt'];
    if (key is! String || key.isEmpty || tierName is! String || validatedAt is! int) {
      return null;
    }
    final tier = BuoyTier.values.cast<BuoyTier?>().firstWhere(
          (t) => t!.name == tierName,
          orElse: () => null,
        );
    if (tier == null) return null;
    return _CachedLicense(
      licenseKey: key,
      tier: tier,
      validatedAt: DateTime.fromMillisecondsSinceEpoch(validatedAt),
    );
  }
}

class BuoyLicenseManager {
  BuoyLicenseManager({
    LicenseValidator? validator,
    DateTime Function()? now,
    List<Duration> retryDelays = licenseTransientRetryDelays,
  })  : _validate = validator ?? validateLicenseKey,
        _now = now ?? DateTime.now,
        _retryDelays = retryDelays;

  final LicenseValidator _validate;
  final DateTime Function() _now;
  final List<Duration> _retryDelays;

  final ValueNotifier<BuoyLicenseState> state = ValueNotifier(const BuoyLicenseState());

  /// The race guard. `setLicenseKey` validates asynchronously, so a
  /// [clearLicense] (or a different key) landing while a request is in flight
  /// must win: the answer is about a key the app no longer has, and applying
  /// it would resurrect a licence the user just removed — and re-persist the
  /// cache that was just deleted. Bumped on every deliberate set/clear,
  /// captured when async work starts, checked before any result is applied.
  int _generation = 0;

  Timer? _retryTimer;
  int _retryAttempt = 0;

  /// Sequences storage reads/writes so a clear cannot be overtaken by a
  /// slower save that started earlier.
  Future<void> _storageChain = Future.value();

  @visibleForTesting
  int get generation => _generation;

  /// Set (or replace) the key. Empty/null clears. Applies a still-valid cached
  /// verdict for this key immediately — so a reconnect announces the right
  /// tier before the network answers — then revalidates unless the cache is
  /// within [licenseLaunchValidationTtl]. `force` (a key typed into the UI)
  /// always hits the network.
  Future<void> setLicenseKey(String? licenseKey, {bool force = false}) async {
    final normalized = licenseKey?.trim().toUpperCase() ?? '';
    if (normalized.isEmpty) return clearLicense();

    _generation += 1;
    final startedAt = _generation;
    _cancelRetry();
    if (force) _retryAttempt = 0;

    final cached = await _loadCache();
    if (startedAt != _generation) return;

    final cacheForKey =
        cached != null && cached.licenseKey == normalized && _isCacheValid(cached) ? cached : null;

    if (cacheForKey != null) {
      state.value = state.value.copyWith(
        tier: cacheForKey.tier,
        licenseKey: normalized,
        clearError: true,
      );
      if (!force && _isCacheFresh(cacheForKey)) {
        state.value = state.value.copyWith(isValidating: false);
        return;
      }
    } else {
      // A different key than the cache was written for: the cache cannot
      // stand in for it. Keep the current tier until the server answers.
      state.value = state.value.copyWith(licenseKey: normalized, clearError: true);
    }

    state.value = state.value.copyWith(isValidating: true);
    await _runValidation(normalized, startedAt, cacheForKey);
  }

  Future<void> _runValidation(
    String key,
    int startedAt,
    _CachedLicense? cacheForKey,
  ) async {
    final KeygenValidation verdict;
    try {
      verdict = await _validate(key);
    } on LicenseTransportError catch (error) {
      // Superseded while failing — say nothing, do nothing.
      if (startedAt != _generation) return;
      // We failed to ASK. Not a verdict, so nothing here may downgrade
      // anyone: the cached tier (if any) was already applied above; with no
      // cache, leave the tier where it is and retry on a backoff.
      if (cacheForKey != null) {
        state.value = state.value.copyWith(isValidating: false, clearError: true);
        return;
      }
      state.value = state.value.copyWith(isValidating: false, error: error.message);
      _scheduleRetry(key);
      return;
    } catch (error) {
      if (startedAt != _generation) return;
      state.value = state.value.copyWith(isValidating: false, error: error.toString());
      return;
    }

    // The key was cleared or replaced while this request was in flight.
    if (startedAt != _generation) return;

    if (isFatalLicenseCode(verdict.code)) {
      // Set the tier explicitly: without this a cached Pro user who pastes a
      // revoked key would stay Pro.
      state.value = state.value.copyWith(
        tier: tierAfterFatalError(verdict.code),
        isValidating: false,
        error: verdict.detail ?? verdict.code,
      );
      await _clearCache();
      return;
    }

    if (!verdict.hasLicense) {
      state.value = state.value.copyWith(
        tier: BuoyTier.anonymous,
        isValidating: false,
        error: verdict.detail ?? 'License not found',
      );
      await _clearCache();
      return;
    }

    // Non-fatal, non-valid codes (TOO_MANY_MACHINES, OVERDUE, ...) still carry
    // the licence — RN treats them as valid, and so do we: never break a dev
    // environment for a licensing round-trip.
    final tier = resolveTier(
      policyId: verdict.policyId,
      metadataPlan: verdict.metadataPlan,
    );
    state.value = state.value.copyWith(tier: tier, isValidating: false, clearError: true);
    _retryAttempt = 0;
    await _saveCache(_CachedLicense(licenseKey: key, tier: tier, validatedAt: _now()));
  }

  /// Remove the key: anonymous, cache gone, and any in-flight validation for
  /// the old key is orphaned by the generation bump.
  Future<void> clearLicense() async {
    _generation += 1;
    _cancelRetry();
    state.value = const BuoyLicenseState();
    await _clearCache();
  }

  void dispose() {
    _generation += 1;
    _cancelRetry();
    state.dispose();
  }

  // ── retry ────────────────────────────────────────────────────────────────

  void _scheduleRetry(String key) {
    if (_retryAttempt >= _retryDelays.length) return;
    final delay = _retryDelays[_retryAttempt];
    _retryAttempt += 1;
    final startedAt = _generation;
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      if (startedAt != _generation) return;
      // Bypass the freshness cache (there is none — that is why we are here)
      // without refilling the backoff budget.
      unawaited(_retryValidation(key));
    });
  }

  Future<void> _retryValidation(String key) async {
    final startedAt = _generation;
    state.value = state.value.copyWith(isValidating: true);
    await _runValidation(key, startedAt, null);
  }

  void _cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  // ── cache ────────────────────────────────────────────────────────────────

  bool _isCacheValid(_CachedLicense cached) =>
      _now().difference(cached.validatedAt) < licenseCacheDuration;

  bool _isCacheFresh(_CachedLicense cached) =>
      _now().difference(cached.validatedAt) < licenseLaunchValidationTtl;

  Future<_CachedLicense?> _loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(licenseCacheStorageKey);
      if (raw == null) return null;
      return _CachedLicense.fromJson(jsonDecode(raw));
    } catch (error) {
      debugPrint('[Buoy] Failed to read the license cache: $error');
      return null;
    }
  }

  Future<void> _saveCache(_CachedLicense cached) {
    return _storageChain = _storageChain.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(licenseCacheStorageKey, jsonEncode(cached.toJson()));
      } catch (error) {
        debugPrint('[Buoy] Failed to write the license cache: $error');
      }
    });
  }

  Future<void> _clearCache() {
    return _storageChain = _storageChain.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(licenseCacheStorageKey);
      } catch (error) {
        debugPrint('[Buoy] Failed to clear the license cache: $error');
      }
    });
  }
}
