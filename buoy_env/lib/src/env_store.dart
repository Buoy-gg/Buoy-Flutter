/// The Dart env source — the Flutter analog of packages/env-tools/src/env/
/// hooks/useDynamicEnv.ts + utils/remoteEnv.ts.
///
/// Flutter has no enumerable `process.env` (`--dart-define` values are
/// compile-time and cannot be listed), so instead of discovery the app hands
/// Buoy its env map explicitly via [BuoyEnv.configure] / `registerBuoyEnv`.
/// The modal and the sync adapter both read from this singleton. RN's
/// `remoteEnv` override is a desktop-only concern (the dashboard points its own
/// modal at the synced device), so there is no device-side analog here.
library;

import 'env_types.dart';

/// Holds the app-provided env values + required-var config for the env tool.
/// Effectively static (env doesn't change at runtime), but [configure] notifies
/// listeners so a hot-reloaded/reconfigured env re-pushes a snapshot.
class BuoyEnv {
  BuoyEnv._();

  /// The process-wide env source.
  static final BuoyEnv instance = BuoyEnv._();

  final Map<String, String> _vars = {};
  List<RequiredEnvVar> _requiredEnvVars = const [];
  final List<void Function()> _listeners = [];

  /// The collected env values (immutable view).
  Map<String, String> get vars => Map.unmodifiable(_vars);

  /// The required-variable config the tool validates against.
  List<RequiredEnvVar> get requiredEnvVars => _requiredEnvVars;

  /// Merge [vars] into the env map and/or set the [requiredEnvVars] config.
  /// Passing a map integrates any source (including `flutter_dotenv`'s
  /// `dotenv.env`) without this package depending on it. Notifies listeners.
  void configure({
    Map<String, String>? vars,
    List<RequiredEnvVar>? requiredEnvVars,
  }) {
    var changed = false;
    if (vars != null) {
      _vars.addAll(vars);
      changed = true;
    }
    if (requiredEnvVars != null) {
      _requiredEnvVars = List.unmodifiable(requiredEnvVars);
      changed = true;
    }
    if (changed) _emit();
  }

  /// Replace the entire env map (RN parity for a full reset).
  void setVars(Map<String, String> vars) {
    _vars
      ..clear()
      ..addAll(vars);
    _emit();
  }

  /// Subscribe to configuration changes; returns an unsubscribe.
  void Function() subscribe(void Function() onChange) {
    _listeners.add(onChange);
    return () => _listeners.remove(onChange);
  }

  void _emit() {
    for (final l in List.of(_listeners)) {
      l();
    }
  }

  /// Test-only reset.
  void resetForTest() {
    _vars.clear();
    _requiredEnvVars = const [];
    _listeners.clear();
  }
}
