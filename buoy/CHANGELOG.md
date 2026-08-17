## 0.3.1

- Picks up the sync payload size guards across every bundled tool, plus
  crash-visible console capture and boot-time network capture. See the individual
  package changelogs.

## 0.3.0

- The umbrella now bundles the full tool suite — network, storage, console, env,
  routes, images, impersonate, image overlay, events, riverpod, and perf monitor
  (previously network only). One `flutter pub add buoy` wires them all.

## 0.2.0

- Zero-config setup: mount one `BuoyDevTools` widget and installed tools
  self-register (capture, in-app menu, desktop sync). No manual wiring in
  `main()` needed; `Buoy.init`/`registerBuoyNetwork` remain for advanced use.
- Buoy broker traffic is auto-excluded from network capture.

## 0.1.0

- Initial beta release.
