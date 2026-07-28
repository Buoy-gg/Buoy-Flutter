## 0.3.0

- Initial release of the Buoy console capture for Flutter.
- Captures `print` (via `BuoyConsole.runZoned`), `debugPrint`, `FlutterError`,
  and uncaught async errors — all chaining to existing handlers.
- 1:1 Chrome-DevTools-style Console panel: level filter chips
  (verbose/info/warning/error), text + `/regex/` + `-exclude` search, repeat
  collapse, `console.group` nesting, Timeline / Grouped layouts, expandable
  object/array values, and stack traces on error/warn.
- Preserve-log persistence across reloads (off by default).
- Streams to Buoy Desktop / MCP via the console sync adapter (protocol v1),
  matching `@buoy-gg/console`.
