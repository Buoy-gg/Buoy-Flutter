/// Ports packages/impersonate/src/impersonate/utils/impersonateStore.ts and
/// impersonateListener.ts (merged).
///
/// [BuoyImpersonate] is the singleton impersonation store — a [ChangeNotifier]
/// mirror of the RN `impersonateStore`, persisted to `shared_preferences` under
/// the EXACT RN key `@buoy/impersonate/state`. Because Flutter has no global
/// `fetch`/`XHR` to monkey-patch, the RN `impersonateListener`'s header
/// injection becomes exposed derived state ([isImpersonating],
/// [impersonatedUserId], [headerKey], [impersonationHeaders]) that the app
/// applies itself (e.g. a Dio interceptor). Public API mirrors the RN listener's
/// `isImpersonating` / `getImpersonatedUserId` / headerKey.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'impersonate_types.dart';

/// RN `STORAGE_KEY`. `@buoy`-prefixed → filtered by `isDevToolsStorageKey`, so
/// it never leaks into the Storage tool as app data.
const String impersonateStorageKey = '@buoy/impersonate/state';

/// RN `MAX_HISTORY`.
const int _maxHistory = 10;

/// A data-nuke callback: fired on impersonation change when its store is enabled
/// AND a callback was registered.
typedef NukeCallback = FutureOr<void> Function();

/// Singleton store for impersonation state. RN `ImpersonateStore`.
class BuoyImpersonate extends ChangeNotifier {
  BuoyImpersonate._();

  /// The process-wide impersonation store.
  static final BuoyImpersonate instance = BuoyImpersonate._();

  ImpersonationState _state = const ImpersonationState();

  /// The current impersonation state (immutable snapshot). RN `getState`.
  ImpersonationState get state => _state;

  ImpersonateDefaults? _developerDefaults;
  bool _initialized = false;

  final Map<String, NukeCallback?> _nukeCallbacks = {};

  // Re-entrancy guard mirroring RN's module-level `isNuking`.
  bool _isNuking = false;

  // ── Listener parity (impersonateListener.ts public surface) ──────────────

  /// True while a header should be injected (active, not paused, has a user).
  /// RN listener `isImpersonating`.
  bool get isImpersonating =>
      _state.isActive && !_state.isPaused && _state.currentUser != null;

  /// The user id sent in the impersonation header, or null when not injecting.
  /// RN `getImpersonatedUserId`.
  String? get impersonatedUserId =>
      isImpersonating ? _state.currentUser!.id : null;

  /// The header key that carries the impersonation user id.
  String get headerKey => _state.headerKey;

  /// `{headerKey: userId}` when impersonating, else `{}` — apply these to your
  /// HTTP client (the Flutter analog of the RN fetch/XHR header injection).
  Map<String, String> get impersonationHeaders {
    final id = impersonatedUserId;
    return id == null ? const {} : {_state.headerKey: id};
  }

  // ── Configuration ────────────────────────────────────────────────────────

  /// Set developer-provided defaults (override hardcoded, overridden by
  /// persisted). RN `setDeveloperDefaults`. Applied only before [initialize].
  void setDeveloperDefaults(ImpersonateDefaults defaults) {
    _developerDefaults = defaults;
    if (!_initialized) {
      final eff = _effectiveDefaults();
      _state = _state.copyWith(
        headerKey: eff.headerKey,
        dataNukeSettings: eff.dataNukeSettings,
        showBanner: eff.showBanner,
      );
    }
  }

  /// Register data-nuke callbacks (null clears one). RN `registerNukeCallbacks`.
  void registerNukeCallbacks({
    NukeCallback? reactQuery,
    NukeCallback? redux,
    NukeCallback? asyncStorage,
    NukeCallback? mmkv,
  }) {
    _nukeCallbacks
      ..['reactQuery'] = reactQuery
      ..['redux'] = redux
      ..['asyncStorage'] = asyncStorage
      ..['mmkv'] = mmkv;
  }

  ({String headerKey, DataNukeSettings dataNukeSettings, bool showBanner})
  _effectiveDefaults() {
    final d = _developerDefaults;
    return (
      headerKey: d?.headerKey ?? ImpersonationState.defaultHeaderKey,
      dataNukeSettings: DataNukeSettings.defaults.mergeJson(d?.dataNukeSettings),
      showBanner: d?.showBanner ?? true,
    );
  }

  // ── Initialization / persistence ─────────────────────────────────────────

  /// Load persisted state (RN `initializeAsync`). Precedence: persisted >
  /// developer defaults > hardcoded. Restores an active session across relaunch.
  /// Idempotent.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    final eff = _effectiveDefaults();
    // Start from effective defaults (no persisted state yet).
    _state = _state.copyWith(
      headerKey: eff.headerKey,
      dataNukeSettings: eff.dataNukeSettings,
      showBanner: eff.showBanner,
    );

    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(impersonateStorageKey);
      if (stored == null || stored.isEmpty) return;
      final parsed = (jsonDecode(stored) as Map).cast<String, Object?>();

      final currentUserJson = parsed['currentUser'];
      final historyJson = parsed['history'];
      _state = ImpersonationState(
        headerKey: parsed['headerKey'] as String? ?? eff.headerKey,
        ignorePatterns:
            (parsed['ignorePatterns'] as List?)?.cast<String>() ?? const [],
        dataNukeSettings: eff.dataNukeSettings.mergeJson(
          (parsed['dataNukeSettings'] as Map?)?.cast<String, Object?>(),
        ),
        showBanner: parsed['showBanner'] as bool? ?? eff.showBanner,
        history: [
          if (historyJson is List)
            for (final h in historyJson)
              HistoryEntry.fromJson((h as Map).cast<String, Object?>()),
        ],
        // Restore active session for continuity across reloads.
        isActive: parsed['isActive'] as bool? ?? false,
        isPaused: parsed['isPaused'] as bool? ?? false,
        currentUser: currentUserJson is Map
            ? ImpersonateUser.fromJson(currentUserJson.cast<String, Object?>())
            : null,
      );
      notifyListeners();
    } catch (_) {
      // Persisted blob unreadable — fall through with in-memory defaults.
    }
  }

  Future<void> _persist() async {
    // Mirror RN `persist`: store settings + active session.
    final toStore = _state.toJson();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(impersonateStorageKey, jsonEncode(toStore));
    } catch (_) {
      // Ignore storage errors (RN parity).
    }
  }

  // ── Impersonation actions ─────────────────────────────────────────────────

  /// Start impersonating [user]. Order (RN): update state + notify BEFORE
  /// clearing caches, so refetches triggered by the nuke carry the new header.
  Future<void> startImpersonation(ImpersonateUser user) async {
    final historyEntry = HistoryEntry(
      user: user,
      lastUsedAt: DateTime.now().toUtc().toIso8601String(),
    );
    final newHistory = <HistoryEntry>[
      historyEntry,
      ..._state.history.where((e) => e.user.id != user.id),
    ];
    if (newHistory.length > _maxHistory) {
      newHistory.removeRange(_maxHistory, newHistory.length);
    }

    _state = _state.copyWith(
      isActive: true,
      currentUser: user,
      history: newHistory,
    );

    // 1) Point the "listener" at the new user, 2) notify subscribers now.
    notifyListeners();
    // 3) Nuke caches — refetches now use the new identity.
    await _executeDataNuke();
    // 4) Persist for next launch.
    await _persist();
  }

  /// Stop impersonating. RN `stopImpersonation`.
  Future<void> stopImpersonation() async {
    _state = _state.copyWith(
      isActive: false,
      isPaused: false,
      clearCurrentUser: true,
    );
    notifyListeners();
    await _executeDataNuke();
    await _persist();
  }

  /// Pause header injection without ending the session. RN `pauseImpersonation`.
  Future<void> pauseImpersonation() async {
    if (!_state.isActive || _state.isPaused) return;
    _state = _state.copyWith(isPaused: true);
    await _persist();
    notifyListeners();
  }

  /// Resume header injection. RN `resumeImpersonation`.
  Future<void> resumeImpersonation() async {
    if (!_state.isActive || !_state.isPaused) return;
    _state = _state.copyWith(isPaused: false);
    await _persist();
    notifyListeners();
  }

  /// Quick-switch to a user from history. RN `quickSwitch`.
  Future<void> quickSwitch(ImpersonateUser user) => startImpersonation(user);

  // ── Settings ───────────────────────────────────────────────────────────────

  /// Update settings (any subset). RN `updateSettings`.
  Future<void> updateSettings({
    String? headerKey,
    List<String>? ignorePatterns,
    bool? showBanner,
    DataNukeSettings? dataNukeSettings,
  }) async {
    _state = _state.copyWith(
      headerKey: headerKey,
      ignorePatterns: ignorePatterns,
      showBanner: showBanner,
      dataNukeSettings: dataNukeSettings,
    );
    await _persist();
    notifyListeners();
  }

  // ── History ─────────────────────────────────────────────────────────────────

  /// Remove a user from history. RN `removeFromHistory`.
  Future<void> removeFromHistory(String userId) async {
    _state = _state.copyWith(
      history: _state.history.where((e) => e.user.id != userId).toList(),
    );
    await _persist();
    notifyListeners();
  }

  /// Clear all history. RN `clearHistory`.
  Future<void> clearHistory() async {
    _state = _state.copyWith(history: const []);
    await _persist();
    notifyListeners();
  }

  // ── Private ──────────────────────────────────────────────────────────────────

  /// Run enabled + registered nuke callbacks. RN `executeDataNuke`.
  Future<void> _executeDataNuke() async {
    if (_isNuking) return;
    _isNuking = true;
    try {
      final s = _state.dataNukeSettings;
      final futures = <Future<void>>[];
      void run(bool enabled, NukeCallback? cb) {
        if (enabled && cb != null) futures.add(Future<void>.value(cb()));
      }

      run(s.reactQuery, _nukeCallbacks['reactQuery']);
      run(s.redux, _nukeCallbacks['redux']);
      run(s.asyncStorage, _nukeCallbacks['asyncStorage']);
      run(s.mmkv, _nukeCallbacks['mmkv']);

      await Future.wait(
        futures.map((f) => f.catchError((_) {})),
      );
    } finally {
      // Reset after a short delay to allow the next legitimate call (RN 100ms).
      Future<void>.delayed(const Duration(milliseconds: 100), () {
        _isNuking = false;
      });
    }
  }

  /// Test-only reset.
  @visibleForTesting
  Future<void> resetForTest() async {
    _state = const ImpersonationState();
    _developerDefaults = null;
    _initialized = false;
    _isNuking = false;
    _nukeCallbacks.clear();
  }
}

// ── Top-level convenience (impersonateListener.ts parity) ────────────────────

/// True while impersonation is actively injecting a header. RN `isImpersonating`.
bool isImpersonating() => BuoyImpersonate.instance.isImpersonating;

/// The impersonated user id, or null. RN `getImpersonatedUserId`.
String? getImpersonatedUserId() => BuoyImpersonate.instance.impersonatedUserId;
