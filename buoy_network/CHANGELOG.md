## 0.3.3

- Sync adapter is now **version 5**, matching the React Native adapter.
- Boot-time requests are no longer lost. Capture used to start with the first
  subscriber (modal open, dashboard or MCP watch), long after the app's startup
  requests had fired; those are now parked in a bounded buffer and flushed in on
  first subscribe.
- Body stripping falls back to a size walk when the cached `requestSize` /
  `responseSize` proxy is missing or wrong (it read 0 for a body the capture
  layer failed to measure, so that body rode every snapshot uncapped).
- Explicit `requestBodyOmitted` / `responseBodyOmitted` / `headersOmitted` flags,
  so a withheld body is distinguishable from a request that had none. Sizes stay
  honest rather than being doctored down.
- Header values over 64 chars are truncated, keeping the key set.
- The event list is spent against a 1.25MB snapshot budget, newest first.
- Added the `getCaptureStatus` action, which answers "why is the list empty?"
  with the subscriber count rather than leaving the caller to guess.

## 0.3.2

- Chrome-style **response overrides**: match rules (URL pattern + method) that
  edit or fully synthesize responses — status, headers, body, delay — with a
  rule editor, presets, and per-rule enable toggles. Persisted under the same
  storage key as RN, and drivable from Buoy Desktop / MCP via the new
  override sync actions.
- **Saved requests**: pin or save any request as a snapshot that survives
  Clear, the capture cap, and app restarts, with a dedicated Saved screen and
  pinned-row split in the list.
- Response-editor explorer views for nested body data; header action menu.

## 0.3.1

- Request detail view gains a Previous/Next stepper footer that walks
  exactly what the list was showing — same pinned rows, filters, and search
  (or the Saved list and its search when opened from there), with a live
  `REQUEST N OF M` counter that re-scopes as new requests arrive.

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
