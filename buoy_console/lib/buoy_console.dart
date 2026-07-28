/// Buoy console capture for Flutter.
///
/// Captures `print` (via [BuoyConsole.runZoned]), `debugPrint`, `FlutterError`,
/// and uncaught async errors, and renders them in a 1:1 Chrome-DevTools-style
/// Console panel that streams live to Buoy Desktop. Ports `@buoy-gg/console`
/// 1:1: register [consoleSyncAdapter] via [registerBuoyConsole] and mount
/// [ConsoleModal] through a [BuoyTool].
library;

export 'package:buoy_core/buoy_core.dart'
    show Buoy, BuoyDevTools, BuoySyncClient, BuoyTool;

export 'src/register.dart';
export 'src/console_capture.dart' show BuoyConsole;
export 'src/console_log_store.dart'
    show ConsoleLogStore, ConsoleLogEntry, ConsoleLevel, levelForMethod;
export 'src/console_sync_adapter.dart' show consoleSyncAdapter;
export 'src/console_tool/console_modal.dart' show ConsoleModal;
