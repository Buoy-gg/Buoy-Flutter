/// Ports packages/console/src/components/ConsoleRoot.tsx + the RN console patch.
///
/// Flutter has no global `console` to patch, so RN's single interception point
/// becomes four Dart hooks — all gated on [kDebugMode], all CHAINING (never
/// clobbering) existing handlers:
///
///  1. `print`     → level info (method `log`) — interceptable ONLY inside a
///     custom `Zone`, so [BuoyConsole.runZoned] wraps `runApp`.
///  2. `debugPrint`→ level verbose (method `debug`) — interceptable via the
///     mutable top-level, no zone needed.
///  3. `FlutterError.onError`            → level error (framework/build errors).
///  4. `PlatformDispatcher.onError`      → level error (uncaught async errors,
///     non-zoned apps).
///
/// Double-capture guards: `FlutterError.dumpErrorToConsole` and `debugPrint`'s
/// own default both funnel through `print`. `_inDebugForward` skips the zone
/// `print` hook while our `debugPrint` wrapper calls the original; `_suppress`
/// skips both hooks while the original `FlutterError.onError` dumps.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'console_log_store.dart';

/// Console capture install API. See the package README for wiring.
class BuoyConsole {
  BuoyConsole._();

  static bool _installed = false;

  /// Set while our `debugPrint` wrapper forwards to the original (whose default
  /// funnels through `print`) — the zone `print` hook skips recording so the
  /// line isn't captured twice (once as debug, once as log).
  static int _inDebugForward = 0;

  /// Set while the original `FlutterError.onError` dumps an already-recorded
  /// error via `debugPrint`/`print` — both hooks skip recording.
  static int _suppress = 0;

  static DebugPrintCallback? _originalDebugPrint;
  static FlutterExceptionHandler? _originalFlutterOnError;
  static bool Function(Object, StackTrace)? _originalPlatformOnError;

  /// Install everything interceptable WITHOUT a zone: `debugPrint`,
  /// `FlutterError.onError`, and `PlatformDispatcher.onError`. Idempotent, and
  /// a no-op outside [kDebugMode]. To also capture `print`, use [runZoned].
  static void install() {
    if (_installed || !kDebugMode) return;
    _installed = true;

    // Restore/clear the persisted buffer before capture starts (RN ConsoleRoot).
    unawaited(ConsoleLogStore.instance.initPersistence());

    // ── debugPrint → verbose ────────────────────────────────────────────
    _originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (_suppress == 0) {
        ConsoleLogStore.instance.record(
          'debug',
          [message ?? ''],
          rawStack: StackTrace.current,
        );
      }
      _inDebugForward++;
      try {
        _originalDebugPrint?.call(message, wrapWidth: wrapWidth);
      } finally {
        _inDebugForward--;
      }
    };

    // ── FlutterError.onError → [RENDER ERROR] ────────────────────────────
    // Tagged, but NOT marked fatal: Flutter fires this for a build error that
    // `ErrorWidget` then recovers from, with the same details as a real crash.
    // See ConsoleLogStore.recordFatal.
    _originalFlutterOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      ConsoleLogStore.instance.recordFatal(
        '[RENDER ERROR]',
        details.exception,
        stack: details.stack,
        fatal: false,
      );
      _suppress++;
      try {
        _originalFlutterOnError?.call(details);
      } finally {
        _suppress--;
      }
    };

    // ── PlatformDispatcher.onError → [UNCAUGHT] ──────────────────────────
    // Nothing else handled this error — it reached the platform. That is the
    // Flutter analogue of RN's global error handler.
    _originalPlatformOnError = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      ConsoleLogStore.instance.recordFatal(
        '[UNCAUGHT]',
        error,
        stack: stack,
      );
      return _originalPlatformOnError?.call(error, stack) ?? false;
    };
  }

  /// Run [body] (which calls `runApp`) inside a zone whose `print` is captured
  /// as level info, and whose uncaught errors are captured as level error. Also
  /// calls [install]. Outside [kDebugMode] it just runs [body] directly.
  ///
  /// The Flutter binding is initialized INSIDE the guarded zone (before [body]),
  /// so `runApp` and Buoy's own binding-dependent setup (preserve-log restore)
  /// share one zone — avoiding the "Zone mismatch" warning and the
  /// "Binding has not yet been initialized" error that a pre-binding
  /// SharedPreferences access would otherwise throw.
  static void runZoned(void Function() body) {
    if (!kDebugMode) {
      body();
      return;
    }
    runZonedGuarded(
      () {
        WidgetsFlutterBinding.ensureInitialized();
        install();
        body();
      },
      // Uncaught inside the guarded zone — the app kept running, but nothing
      // in app code handled this.
      (Object error, StackTrace stack) => ConsoleLogStore.instance.recordFatal(
        '[UNCAUGHT]',
        error,
        stack: stack,
      ),
      zoneSpecification: ZoneSpecification(
        print: (Zone self, ZoneDelegate parent, Zone zone, String line) {
          if (_suppress == 0 && _inDebugForward == 0) {
            ConsoleLogStore.instance.record(
              'log',
              [line],
              rawStack: StackTrace.current,
            );
          }
          parent.print(zone, line);
        },
      ),
    );
  }

}
