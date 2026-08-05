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
