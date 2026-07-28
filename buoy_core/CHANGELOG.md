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
