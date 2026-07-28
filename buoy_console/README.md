# buoy_console

Buoy console capture for Flutter — captures `print`, `debugPrint`, and uncaught
errors and renders them in a 1:1 Chrome-DevTools-style Console panel that streams
live to [Buoy Desktop](https://buoy.gg).

Part of the [Buoy](https://buoy.gg) devtools suite. Ports `@buoy-gg/console`
1:1: the same level filter chips, text/regex search, preserve-log, repeat
collapse, group nesting, and sync protocol.

## Usage

To capture `print`, wrap `runApp` in `BuoyConsole.runZoned` (a `Zone` is the only
way to intercept `print`). `debugPrint` and uncaught errors are captured with or
without the zone.

```dart
import 'package:buoy/buoy.dart';

void main() {
  BuoyConsole.runZoned(() {
    runApp(const MyApp());
  });
}

MaterialApp(
  builder: (context, child) =>
      BuoyDevTools(child: child ?? const SizedBox.shrink()),
);
```

Or register the tool directly (without the umbrella):

```dart
import 'package:buoy_console/buoy_console.dart';

void main() {
  if (kDebugMode) registerBuoyConsole();
  BuoyConsole.runZoned(() => runApp(const MyApp()));
}
```

If you never call `BuoyConsole.runZoned`, call `BuoyConsole.install()` once to
still capture `debugPrint`, `FlutterError`, and uncaught async errors — only
`print` requires the zone.

### Preserve log

Off by default: the buffer is in-memory and a hot restart / relaunch starts
fresh. Turn on "Preserve log" in the console's Filters panel to persist the
buffer across reloads (Chrome's "Preserve log").

## License

See [buoy.gg](https://buoy.gg). Proprietary — © Buoy.
