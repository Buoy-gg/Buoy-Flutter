## 0.3.2

- Added `wire_budget.dart`: `approxJsonSize` / `isOverWireBudget` /
  `isJsonEncodable` plus the emit budgets. Size guards measure with an
  early-abort walk (O(limit), never O(payload)) and only reach for `jsonEncode`
  when the walk saw something that could actually make it throw. Ports
  `@buoy-gg/shared-ui`'s `wireBudget.ts`.
- Added `crash_flush.dart`: `registerToolFlusher` / `flushToolSyncNow`, a
  "push this tool's snapshot NOW" seam so a tool that knows the app is about to
  die can bypass the 200ms snapshot throttle.
- `BuoySyncClient` now drops an oversized snapshot (with a warn-once message)
  instead of encoding it, returns an actionable error for an oversized action
  result, and guards `socket.emit` so an unencodable payload can no longer
  throw through app code. Previously an encode failure was silently turned into
  the string `{}`.

## 0.3.1

- Dial menu now ranks tools by recency-weighted usage (`dial_usage.dart`,
  ported from RN's `dialUsage.ts` — ~3-day half-life decay).
- Modal visibility plumbing (`modal_visibility.dart`) so tools can react to
  their modal being shown/hidden.
- Regenerated icon set with new `bookmark` and `flask-conical` glyphs
  (network saved requests + override rules).

## 0.3.0

- Added `BuoyOverlayHost`: a shared overlay layer that tool packages draw HUDs and
  full-screen overlays through (used by the perf-monitor HUD and image-overlay tool).
- Extracted the shared UI kit and stores into the new `buoy_shared_ui` package;
  tool packages now depend on it directly.
- Core continues to provide the tool-registry contract, the floating bubble + dial
  shell, the desktop-sync client (Buoy Desktop broker, Socket.IO), and persistent
  settings storage.

## 0.2.0

- Zero-config setup: mount one `BuoyDevTools` widget and installed tools
  self-register (capture, in-app menu, desktop sync). `Buoy.init` remains for
  advanced use.

## 0.1.0

- Initial beta release.
