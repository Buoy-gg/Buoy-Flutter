/// Ports packages/perf-monitor/src/perf-monitor/utils/hudPreferences.ts.
///
/// Two persisted slots under the RN key names, stored via shared_preferences:
///  - `@react_buoy/perf-monitor/hud-prefs`   → mode + last position + hidden
///  - `@react_buoy/perf-monitor/hud-enabled` → JSON `true`/`false`
/// Separate slots so the controller (enabled) and the overlay (position/mode)
/// write independently without racing on one blob (RN parity).
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'perf_types.dart';

const String hudPrefsKey = '@react_buoy/perf-monitor/hud-prefs';
const String hudEnabledKey = '@react_buoy/perf-monitor/hud-enabled';

Future<HudPreferences> loadHudPreferences() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(hudPrefsKey);
    if (raw == null) return HudPreferences.defaults;
    final parsed = jsonDecode(raw);
    if (parsed is! Map) return HudPreferences.defaults;
    final pos = parsed['position'];
    ({double x, double y}) position = HudPreferences.defaults.position;
    if (pos is Map && pos['x'] is num && pos['y'] is num) {
      final x = (pos['x'] as num).toDouble();
      final y = (pos['y'] as num).toDouble();
      if (x.isFinite && y.isFinite) position = (x: x, y: y);
    }
    return HudPreferences(
      mode: HudModeWire.fromWire(parsed['mode']),
      position: position,
      hidden: parsed['hidden'] == true,
    );
  } catch (_) {
    return HudPreferences.defaults;
  }
}

Future<void> saveHudPreferences(HudPreferences prefs) async {
  try {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(hudPrefsKey, jsonEncode(prefs.toJson()));
  } catch (_) {
    // best-effort
  }
}

Future<bool> loadHudEnabled() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(hudEnabledKey);
    if (raw == null) return false;
    return jsonDecode(raw) == true;
  } catch (_) {
    return false;
  }
}

Future<void> saveHudEnabled(bool enabled) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(hudEnabledKey, jsonEncode(enabled));
  } catch (_) {
    // best-effort
  }
}
