/// Ports packages/network/src/network/overrides/overrideRulesStore.ts — the
/// persisted rule list and the master switch.
///
/// Same singleton-plus-listeners shape as [NetworkEventStore] next door, and
/// the same storage contract as RN: the blob lives under
/// `@react_buoy_network_overrides` with identical field names, so a rule
/// written by either runtime reads on the other and the desktop needs no
/// per-platform branch.
///
/// The Flutter store is deliberately SIMPLER than RN's in two places, both
/// because Flutter's surroundings differ rather than by preference:
///
/// - **No remote-mirror mode.** RN's store doubles as the desktop dashboard's
///   local mirror (the dashboard renders the RN tool directly). Flutter's tool
///   never runs on the desktop, so this store is only ever the device's own.
/// - **No listener keep-alive.** RN reference-counts its fetch/XHR swizzle and
///   has to hold a no-op listener so rules fire with the tool closed.
///   `registerBuoyNetwork` installs [BuoyHttpOverrides] once at startup and
///   never removes it, so a Flutter rule already fires from app boot.
library;

import 'dart:async';
import 'dart:convert';

import 'package:buoy_core/buoy_core.dart';
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'override_rule.dart';
import 'resolve_override.dart';

/// Launches-with-rules-on before overrides pause themselves.
///
/// Persisting rules is the point ("force a 500, restart, watch the boot path"),
/// but a body the app can't render turns that into a brick: the rule reinstates
/// itself on every launch and the controls to remove it live inside an app that
/// no longer draws. Verified on RN in testing — the only exit was deleting the
/// file off the simulator.
///
/// Three is chosen so the intended workflow survives (force, relaunch, look,
/// relaunch, look) while a wedge cannot outlive the second relaunch. The streak
/// resets whenever a rule is created or edited, so an actively-used rule set
/// never pauses.
const int maxUntouchedLaunches = 3;

/// Hit counts change per request; the UI shouldn't rebuild per request.
const Duration _hitEmitCoalesce = Duration(milliseconds: 250);

/// Writes are debounced to the port briefing's 500ms.
const Duration _persistDebounce = Duration(milliseconds: 500);

class OverrideRulesStore {
  OverrideRulesStore._();
  static final OverrideRulesStore instance = OverrideRulesStore._();

  final BuoyStorage _storage = BuoyStorage();
  final List<void Function()> _listeners = [];

  List<OverrideRule> _rules = [];
  bool _enabled = true;
  bool _autoPaused = false;
  int _launchStreak = 0;
  int _idCounter = 0;

  bool _loaded = false;
  bool _dirty = false;
  Future<void>? _loadFuture;
  Timer? _hitEmitTimer;
  Timer? _persistTimer;

  /// Master switch. Off disables every rule without losing any of them.
  bool get enabled => _enabled;

  /// Set when the launch-safety guard turned overrides off by itself. Cleared
  /// the moment the developer turns them back on or touches a rule, so the UI
  /// can explain the state rather than leave it looking like a bug.
  bool get autoPaused => _autoPaused;

  List<OverrideRule> get rules => List.unmodifiable(_rules);

  /// What the engine is allowed to see. Returns nothing while the master switch
  /// is off, so the request path needs no second check.
  List<OverrideRule> get activeRules => _enabled ? _rules : const [];

  /// Rules that would actually fire — drives the "overrides active" badge.
  int get activeCount => _enabled
      ? _rules.where((rule) => rule.enabled && !isSpent(rule)).length
      : 0;

  Map<String, Object?> get state => {
    'enabled': _enabled,
    'rules': [for (final rule in _rules) rule.toJson()],
    'autoPaused': _autoPaused,
  };

  /// The snapshot shape: oversized bodies dropped and flagged.
  ///
  /// A rule seeded from a real request holds that request's whole response, and
  /// the snapshot goes out several times a second while traffic flows —
  /// streaming half a megabyte forever is the freeze that
  /// [snapshotBodyInlineLimit] already exists to prevent for events.
  Map<String, Object?> snapshotState(int inlineLimit) => {
    'enabled': _enabled,
    'rules': [
      for (final rule in _rules)
        rule.toJson(
          omitBody: (rule.body?.length ?? 0) > inlineLimit,
        ),
    ],
    'autoPaused': _autoPaused,
  };

  void Function() subscribe(void Function() onChange) {
    _listeners.add(onChange);
    unawaited(ensureLoaded());
    return () => _listeners.remove(onChange);
  }

  void _emit() {
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }

  // ── Mutations ──────────────────────────────────────────────────────────────

  void setEnabled(bool enabled) {
    if (_enabled == enabled && !_autoPaused) return;
    _enabled = enabled;
    // Turning them back on is an explicit answer to the auto-pause notice.
    _autoPaused = false;
    _launchStreak = 0;
    _dirty = true;
    _emit();
    _persist();
  }

  /// Create a rule, or replace one by id. The only write path the UI uses.
  OverrideRule? upsertRule(OverrideRule draft) {
    final index = _rules.indexWhere((rule) => rule.id == draft.id);
    if (index == -1 && _rules.length >= maxOverrideRules) return null;

    final next = List.of(_rules);
    if (index == -1) {
      next.add(draft);
    } else {
      // Editing a rule RESETS its budget (RN `updateRule` does the same).
      // Carrying the counters over looks tidier and is a trap: change a rule
      // that has already fired 20 times to "Once" and `hits >= times` is true
      // before it ever runs, so it sits enabled and permanently dead. Caught
      // exactly that way on device.
      next[index] = draft.copyWith(hits: 0, seen: 0);
    }
    _markTouched();
    _commit(next);
    return index == -1 ? draft : next[index];
  }

  void setRuleEnabled(String id, bool enabled) {
    final index = _rules.indexWhere((rule) => rule.id == id);
    if (index == -1) return;
    final rule = _rules[index];
    if (rule.enabled == enabled) return;
    final next = List.of(_rules);
    // Re-enabling clears the budget too, or the toggle appears to do nothing on
    // a spent rule: `isSpent` would still be true the instant it came back on.
    next[index] = rule.copyWith(enabled: enabled, hits: enabled ? 0 : null);
    _markTouched();
    _commit(next);
  }

  void removeRule(String id) {
    final next = _rules.where((rule) => rule.id != id).toList();
    if (next.length == _rules.length) return;
    _markTouched();
    _commit(next);
  }

  void clearRules() {
    if (_rules.isEmpty) return;
    _markTouched();
    _commit([]);
  }

  /// One rule matched one request, applied or not.
  ///
  /// Deliberately silent — this fires on requests an alternating rule lets
  /// through, where nothing visible changed. [recordHit] owns the notification.
  void recordMatch(String ruleId) {
    final index = _rules.indexWhere((rule) => rule.id == ruleId);
    if (index == -1) return;
    _rules[index].seen += 1;
  }

  void recordHit(String ruleId) {
    final index = _rules.indexWhere((rule) => rule.id == ruleId);
    if (index == -1) return;
    final rule = _rules[index];
    rule.hits += 1;
    if (rule.times != null && rule.hits >= rule.times!) {
      // Auto-expiry is a real state change, so it commits immediately instead
      // of waiting on the coalesce window.
      rule.enabled = false;
      _dirty = true;
      _emit();
      _persist();
      return;
    }
    _scheduleHitEmit();
  }

  String nextId() =>
      'ovr_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}_${++_idCounter}';

  /// The developer reached the override UI, which is proof the app still runs —
  /// so the launch guard has nothing left to protect them from.
  void noteHealthyLaunch() {
    if (_launchStreak == 0) return;
    _launchStreak = 0;
    _dirty = true;
    _persist();
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Hydrate from storage. Safe to call repeatedly; only the first call reads.
  ///
  /// Called from `registerBuoyNetwork` rather than on first subscribe, because
  /// a rule has to fire from app boot — with the Network tool closed and
  /// nothing capturing.
  Future<void> ensureLoaded() {
    if (_loaded) return Future.value();
    return _loadFuture ??= _load();
  }

  Future<void> _load() async {
    try {
      final stored = await _storage.loadJson(
        devToolsStorageKeys.network.overrides(),
      );
      // A rule may have been created while this read was in flight — never
      // overwrite user intent with older disk state.
      if (stored != null && !_dirty) {
        _enabled = stored['enabled'] != false;
        final raw = stored['rules'];
        _rules = [
          if (raw is List)
            for (final entry in raw) ?OverrideRule.fromJson(entry),
        ];
        _launchStreak = stored['launchStreak'] is num
            ? (stored['launchStreak'] as num).toInt()
            : 0;
        _applyLaunchGuard();
      }
    } catch (_) {
      // Corrupt or unreadable — start empty rather than taking the tool down.
    } finally {
      _loaded = true;
      _emit();
    }
  }

  /// Count this launch, and pause overrides if they've been armed and untouched
  /// for too many in a row. See [maxUntouchedLaunches] for why.
  void _applyLaunchGuard() {
    if (!_enabled || activeCount == 0) {
      _launchStreak = 0;
      return;
    }
    _launchStreak += 1;
    if (_launchStreak >= maxUntouchedLaunches) {
      _enabled = false;
      _autoPaused = true;
      _launchStreak = 0;
    }
    _dirty = true;
    _persist();
  }

  /// The developer is actively working with the rules, so the launch guard has
  /// nothing to protect them from — reset it and clear any auto-pause notice.
  void _markTouched() {
    _launchStreak = 0;
    _autoPaused = false;
  }

  void _commit(List<OverrideRule> next) {
    _dirty = true;
    _rules = next.length > maxOverrideRules
        ? next.sublist(0, maxOverrideRules)
        : next;
    _emit();
    _persist();
  }

  void _scheduleHitEmit() {
    if (_hitEmitTimer != null) return;
    _hitEmitTimer = Timer(_hitEmitCoalesce, () {
      _hitEmitTimer = null;
      _emit();
    });
  }

  void _persist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(_persistDebounce, () {
      _persistTimer = null;
      unawaited(_writeNow());
    });
  }

  Future<void> _writeNow() async {
    try {
      await _storage.saveJson(devToolsStorageKeys.network.overrides(), {
        'enabled': _enabled,
        // Runtime counters are stripped on the way out — `hits`/`seen` describe
        // this run, and a rule that came back "already spent" after a restart
        // would silently never fire.
        'rules': [
          for (final rule in _rules)
            rule.toJson()
              ..remove('hits')
              ..remove('seen'),
        ],
        'launchStreak': _launchStreak,
      });
    } catch (_) {
      // Storage is best-effort; losing a rule beats crashing the app.
    }
  }

  /// Test seam: drop everything, including the loaded flag.
  @visibleForTesting
  void resetForTest() {
    _hitEmitTimer?.cancel();
    _persistTimer?.cancel();
    _hitEmitTimer = null;
    _persistTimer = null;
    _rules = [];
    _enabled = true;
    _autoPaused = false;
    _launchStreak = 0;
    _loaded = true;
    _dirty = false;
    _loadFuture = null;
    _listeners.clear();
  }
}

/// JSON encode/decode helper kept next to the store so the storage shape lives
/// in one place. [BuoyStorage.saveJson] takes a Map, so this only exists for
/// the sync actions that hand rules over the wire.
String encodeRules(List<OverrideRule> rules) =>
    jsonEncode([for (final rule in rules) rule.toJson()]);
