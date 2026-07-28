## 0.3.0

- Initial release: 1:1 Flutter port of `@buoy-gg/image-overlay`.
- Free Placement (drag + aspect-locked resize) and Component Match modes, with
  opacity / scale / offset / flip controls and Auto Track.
- Renders through the new `BuoyOverlayHost` layer in `buoy_core` (overlay drawn
  over the app, outside the control modal). Pure-UI tool — no data capture and,
  matching the RN package, no desktop-sync adapter.
