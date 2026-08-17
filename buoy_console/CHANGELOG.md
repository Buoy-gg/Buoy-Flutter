## 0.3.1

- Crashes are now visible to Buoy Desktop and the MCP server. A crash used to
  take the sync bridge down with it, so the throttled snapshot never fired and
  the dashboard just showed a device that had stopped answering.
- Entries carry a `fatal` flag, and crash entries are tagged: `[UNCAUGHT]` for
  errors from `PlatformDispatcher.onError` and the guarded zone, `[RENDER ERROR]`
  for `FlutterError.onError`. The render tag is deliberately NOT marked fatal —
  Flutter fires it for a build error `ErrorWidget` then recovers from.
- Crash entries push to the dashboard immediately (bypassing the 200ms throttle);
  repeats of the same headline within 2s are still recorded, but only push once.
  Ordinary error entries also push, rate-limited to 150ms.
- Entries are spent against a 1.5MB snapshot budget with a per-entry wire cache,
  and `sanitizeArgs` now caps long strings — a single fat log could previously
  drop the whole console panel.
- Fixed: `sanitizeArgs` used an `==`-keyed set for its cycle check, so the second
  of two equal-but-distinct maps was rendered as `[Circular]`.

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
