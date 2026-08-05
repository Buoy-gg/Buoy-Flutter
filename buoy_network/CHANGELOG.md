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
