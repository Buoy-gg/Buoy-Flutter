## 0.3.0

- Refactored onto the shared `buoy_shared_ui` package (list/badge/filter widgets,
  DataViewer, modal chrome now come from there). No change to capture behavior.

## 0.2.0

- Zero-config setup: mount one `BuoyDevTools` widget and installed tools
  self-register (capture, in-app menu, desktop sync). No manual wiring in
  `main()` needed; `Buoy.init`/`registerBuoyNetwork` remain for advanced use.
- Buoy broker traffic is auto-excluded from network capture.

## 0.1.0

- Initial beta release.
