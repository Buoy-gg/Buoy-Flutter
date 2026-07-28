/// Ports packages/perf-monitor/src/perf-monitor/utils/automationSettings.ts.
///
/// Persists the last [AutomationConfig] the user ran (or edited) under
/// `@react_buoy/perf-monitor/automation` so re-opening the modal pre-fills the
/// form. Same singleton + sanitize + subscribe pattern as [PerfSettingsStore].
///
/// **Logged deviation:** `reloadBetweenCases` defaults to (and sanitizes to)
/// **false** on Flutter — Dart cannot reload its realm the way RN's
/// `DevSettings.reload()` does, so the flag is accepted-and-ignored. MCP's
/// `buildAutomationConfig` already defaults it false, so MCP-driven batches are
/// unaffected. The bounce-route remount still gives per-case first-render
/// isolation.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

import 'perf_types.dart';

const String automationConfigKey = '@react_buoy/perf-monitor/automation';

/// RN `DEFAULT_AUTOMATION_CONFIG`, with the one Flutter deviation
/// (`reloadBetweenCases: false`).
AutomationConfig defaultAutomationConfig() => const AutomationConfig(
      targetRoute: '',
      bounceRoute: '/',
      perCaseDurationMs: 5000,
      settleMs: 600,
      navTimeoutMs: 5000,
      cases: [],
      reloadBetweenCases: false,
      reloadStrategy: 'auto',
      // 3 runs balances confidence vs total batch time; 8s cooldown lets
      // CPU/GPU temp settle so later cases aren't thermally biased downward
      // (RN comment: batch-1779574310712-ghww showed 23→17→17 UI FPS).
      runsPerCase: 3,
      coolDownMs: 8000,
      discardWarmupRuns: 0,
      shuffleCases: true,
      captureRenders: true,
    );

int _nextLocalId = 1;

/// Editor-stable id; unique, never persisted as anything meaningful.
String makeCaseId() =>
    'case-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}-${(_nextLocalId++).toRadixString(36)}';

int _clampInt(Object? value, int min, int max, int fallback) {
  final n = value is num
      ? value.toDouble()
      : (value is String ? double.tryParse(value) : null);
  if (n == null || !n.isFinite) return fallback;
  return math.min(max, math.max(min, n.round()));
}

AutomationCase? _sanitizeCase(Object? raw) {
  if (raw is! Map) return null;
  final r = raw.cast<String, Object?>();
  final rawName = r['name'];
  final name = rawName is String && rawName.trim().isNotEmpty
      ? rawName
      : 'Untitled';
  final params = <String, String>{};
  final rawParams = r['params'];
  if (rawParams is Map) {
    for (final e in rawParams.entries) {
      final k = e.key.toString();
      if (k.isEmpty) continue;
      final v = e.value;
      if (v == null) continue;
      params[k] = v is String ? v : '$v';
    }
  }
  final rawRoute = r['route'];
  final route = rawRoute is String && rawRoute.trim().startsWith('/')
      ? rawRoute.trim()
      : null;
  final id = r['id'];
  return AutomationCase(
    id: id is String && id.isNotEmpty ? id : makeCaseId(),
    name: name,
    params: params,
    route: route,
  );
}

/// Validate-and-coerce an unknown value into a clean case list. Shared by the
/// config store and the saved-case-set store (RN `sanitizeAutomationCases`).
List<AutomationCase> sanitizeAutomationCases(Object? raw) {
  if (raw is! List) return [];
  return [
    for (final item in raw)
      ?_sanitizeCase(item),
  ];
}

/// Deep-clone cases with fresh editor ids so repeated loads never collide
/// (RN `cloneCasesWithNewIds`).
List<AutomationCase> cloneCasesWithNewIds(List<AutomationCase> cases) => [
      for (final c in cases)
        AutomationCase(
          id: makeCaseId(),
          name: c.name,
          params: {...c.params},
          route: (c.route != null && c.route!.isNotEmpty) ? c.route : null,
        ),
    ];

AutomationCase createBlankCase([String name = '']) => AutomationCase(
      id: makeCaseId(),
      name: name.isNotEmpty ? name : 'Untitled',
    );

/// Clamp + coerce a raw decoded blob into a valid config (RN `sanitize`).
AutomationConfig sanitizeAutomationConfig(Object? value) {
  final d = defaultAutomationConfig();
  if (value is! Map) return d;
  final v = value.cast<String, Object?>();

  final rawStrategy = v['reloadStrategy'];
  final reloadStrategy = (rawStrategy == 'dev-settings' ||
          rawStrategy == 'expo-updates' ||
          rawStrategy == 'auto')
      ? rawStrategy as String
      : 'auto';

  final rawPostReload = v['postReloadSettleMs'];
  final postReloadSettleMs = rawPostReload is num && rawPostReload.isFinite
      ? _clampInt(rawPostReload, 0, 60000, 0)
      : null;

  final rawTarget = v['targetRoute'];
  final rawBounce = v['bounceRoute'];

  return AutomationConfig(
    targetRoute: rawTarget is String ? rawTarget : '',
    bounceRoute: rawBounce is String && rawBounce.isNotEmpty
        ? rawBounce
        : d.bounceRoute,
    perCaseDurationMs:
        _clampInt(v['perCaseDurationMs'], 500, 120000, d.perCaseDurationMs),
    settleMs: _clampInt(v['settleMs'], 0, 30000, d.settleMs),
    navTimeoutMs: _clampInt(v['navTimeoutMs'], 500, 60000, d.navTimeoutMs),
    cases: sanitizeAutomationCases(v['cases']),
    // Flutter forces this off regardless of what was persisted (see the
    // library docstring).
    reloadBetweenCases: false,
    reloadStrategy: reloadStrategy,
    postReloadSettleMs: postReloadSettleMs,
    runsPerCase: _clampInt(v['runsPerCase'], 1, 10, d.runsPerCase),
    coolDownMs: _clampInt(v['coolDownMs'], 0, 30000, d.coolDownMs),
    discardWarmupRuns:
        _clampInt(v['discardWarmupRuns'], 0, 9, d.discardWarmupRuns),
    shuffleCases:
        v['shuffleCases'] is bool ? v['shuffleCases'] as bool : d.shuffleCases,
    captureRenders: v['captureRenders'] is bool
        ? v['captureRenders'] as bool
        : d.captureRenders,
  );
}

/// Process-wide automation config (RN module-singleton in automationSettings.ts).
class AutomationConfigStore {
  AutomationConfigStore._();
  static final AutomationConfigStore instance = AutomationConfigStore._();

  AutomationConfig _current = defaultAutomationConfig();
  bool _loaded = false;
  Future<void>? _loadFuture;
  final Set<void Function(AutomationConfig)> _subscribers = {};

  AutomationConfig get current => _current;

  Future<void> load() {
    if (_loaded) return Future.value();
    return _loadFuture ??= () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(automationConfigKey);
        if (raw != null) _current = sanitizeAutomationConfig(jsonDecode(raw));
      } catch (_) {
        // keep defaults
      } finally {
        _loaded = true;
        _notify();
      }
    }();
  }

  void Function() subscribe(void Function(AutomationConfig) fn) {
    _subscribers.add(fn);
    fn(_current);
    return () => _subscribers.remove(fn);
  }

  Future<void> save(AutomationConfig next) async {
    _current = sanitizeAutomationConfig(next.toJson());
    _notify();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        automationConfigKey,
        jsonEncode(_current.toJson()),
      );
    } catch (_) {
      // best-effort
    }
  }

  void _notify() {
    for (final fn in [..._subscribers]) {
      try {
        fn(_current);
      } catch (_) {
        // swallow
      }
    }
  }
}

// ─── Speed presets (RN SPEED_PRESETS / SPEED_PRESET_HINTS) ─────────────────

/// Tuning preset for the speed/accuracy trade-off.
enum AutomationSpeedPreset { fast, slow }

class _PresetFields {
  const _PresetFields({
    required this.perCaseDurationMs,
    required this.settleMs,
    required this.coolDownMs,
    required this.postReloadSettleMs,
    required this.shuffleCases,
  });
  final int perCaseDurationMs;
  final int settleMs;
  final int coolDownMs;
  final int postReloadSettleMs;
  final bool shuffleCases;
}

const Map<AutomationSpeedPreset, _PresetFields> _speedPresets = {
  // Fast: ~4 min for a 10×3 batch. Relies on the device staying cool.
  AutomationSpeedPreset.fast: _PresetFields(
    perCaseDurationMs: 5000,
    settleMs: 600,
    coolDownMs: 3000,
    postReloadSettleMs: 1200,
    shuffleCases: true,
  ),
  // Slow: ~9 min for a 10×3 batch. Long cooldown fully sheds heat.
  AutomationSpeedPreset.slow: _PresetFields(
    perCaseDurationMs: 5000,
    settleMs: 1500,
    coolDownMs: 20000,
    postReloadSettleMs: 3000,
    shuffleCases: true,
  ),
};

const Map<AutomationSpeedPreset, String> speedPresetHints = {
  AutomationSpeedPreset.fast:
      '~4 min for 10×3 batch. Cooling pads (ice-cold) massively reduce thermal noise — strongly recommended in Fast mode. Without cooling, late cases will look slower than they actually are.',
  AutomationSpeedPreset.slow:
      '~9 min for 10×3 batch. 20s cooldown lets the phone fully shed heat between runs. Use when you can\'t cool the device or need maximum-fidelity numbers.',
};

/// Merge a preset onto an existing config. Preserves cases, routes, reload
/// toggles, runsPerCase — only the pacing fields change.
AutomationConfig applySpeedPreset(
  AutomationConfig config,
  AutomationSpeedPreset preset,
) {
  final p = _speedPresets[preset]!;
  return config.copyWith(
    perCaseDurationMs: p.perCaseDurationMs,
    settleMs: p.settleMs,
    coolDownMs: p.coolDownMs,
    postReloadSettleMs: p.postReloadSettleMs,
    shuffleCases: p.shuffleCases,
  );
}

/// Which preset the config currently matches, or null when hand-edited.
AutomationSpeedPreset? detectSpeedPreset(AutomationConfig config) {
  for (final preset in AutomationSpeedPreset.values) {
    final p = _speedPresets[preset]!;
    if (config.perCaseDurationMs == p.perCaseDurationMs &&
        config.settleMs == p.settleMs &&
        config.coolDownMs == p.coolDownMs &&
        config.postReloadSettleMs == p.postReloadSettleMs &&
        config.shuffleCases == p.shuffleCases) {
      return preset;
    }
  }
  return null;
}
