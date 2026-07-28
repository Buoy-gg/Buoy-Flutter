/// Ports packages/perf-monitor/src/perf-monitor/utils/settings.ts.
///
/// Singleton with synchronous get/subscribe and async load from
/// shared_preferences under `@react_buoy/perf-monitor/settings`. UIs render
/// against [PerfSettingsStore.current] immediately and re-render when
/// [PerfSettingsStore.subscribe] fires after the persisted value loads.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

import 'perf_types.dart';

const String perfSettingsKey = '@react_buoy/perf-monitor/settings';

const int _windowMsMin = 1000;
const int _windowMsMax = 30000;

bool _boolOr(Object? v, bool fallback) => v is bool ? v : fallback;

int _windowMsOr(Object? v, int fallback) {
  if (v is! num || !v.isFinite) return fallback;
  return math.max(_windowMsMin, math.min(_windowMsMax, v.round()));
}

String _frameBudgetModeOr(Object? v, String fallback) =>
    (v == 'fps' || v == 'ms') ? v as String : fallback;

/// Clamp + sanitize a raw decoded blob into a valid [PerfSettings].
/// Pure — unit-tested directly.
PerfSettings sanitizePerfSettings(Object? value) {
  const d = PerfSettings.defaults;
  if (value is! Map) return d;
  return PerfSettings(
    autoStopOnBackground:
        _boolOr(value['autoStopOnBackground'], d.autoStopOnBackground),
    captureRenders: _boolOr(value['captureRenders'], d.captureRenders),
    showLiveRenders: _boolOr(value['showLiveRenders'], d.showLiveRenders),
    showJsFps: _boolOr(value['showJsFps'], d.showJsFps),
    showUiFps: _boolOr(value['showUiFps'], d.showUiFps),
    showCpu: _boolOr(value['showCpu'], d.showCpu),
    showMem: _boolOr(value['showMem'], d.showMem),
    showReaFps: _boolOr(value['showReaFps'], d.showReaFps),
    windowMs: _windowMsOr(value['windowMs'], d.windowMs),
    frameBudgetMode:
        _frameBudgetModeOr(value['frameBudgetMode'], d.frameBudgetMode),
  );
}

/// Process-wide perf settings (RN module-singleton in settings.ts).
class PerfSettingsStore {
  PerfSettingsStore._();
  static final PerfSettingsStore instance = PerfSettingsStore._();

  PerfSettings _current = PerfSettings.defaults;
  bool _loaded = false;
  Future<void>? _loadFuture;
  final Set<void Function(PerfSettings)> _subscribers = {};

  PerfSettings get current => _current;

  void _notify() {
    for (final fn in [..._subscribers]) {
      try {
        fn(_current);
      } catch (_) {
        // swallow
      }
    }
  }

  /// Kick off the load if it hasn't started; idempotent.
  Future<void> load() {
    if (_loaded) return Future.value();
    return _loadFuture ??= () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(perfSettingsKey);
        if (raw != null) _current = sanitizePerfSettings(jsonDecode(raw));
      } catch (_) {
        // keep defaults
      } finally {
        _loaded = true;
        _notify();
      }
    }();
  }

  void Function() subscribe(void Function(PerfSettings) fn) {
    _subscribers.add(fn);
    fn(_current);
    return () => _subscribers.remove(fn);
  }

  Future<void> update(PerfSettings Function(PerfSettings) patch) async {
    _current = sanitizePerfSettings(patch(_current).toJson());
    _notify();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(perfSettingsKey, jsonEncode(_current.toJson()));
    } catch (_) {
      // best-effort
    }
  }

  /// Restore defaults + drop the persisted blob (RN `resetSettings`).
  Future<void> reset() async {
    _current = PerfSettings.defaults;
    _notify();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(perfSettingsKey);
    } catch (_) {
      // best-effort
    }
  }
}
