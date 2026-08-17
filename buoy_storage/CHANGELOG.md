## 0.3.1

- Sync adapter is now **version 3**, matching the React Native adapter.
- Values over 16KB are replaced on the list snapshot with a
  `__buoyValueOnDevice` marker, and the whole event list is spent against a
  1.25MB budget (newest first) so a burst of individually-legal values degrades
  the oldest events instead of the emit layer dropping the entire panel.
- Added the `getEventDetail` action: the size-guarded, on-demand channel for one
  event's real `value`/`prevValue`.
- Added the `mmkv.get` action, and the MMKV + SecureStore browse dumps now go
  through the same inline cap (the dashboard polls those, so one oversized value
  was re-sent on every refresh).

## 0.3.0

- Initial release of the Buoy storage inspector for Flutter.
- Browse every `shared_preferences` key/value in an in-app panel, with a live
  Events stream, key-pattern filters, and pin/hide.
- Live monitoring of storage writes via an owned-write wrapper (`BuoyPrefs`)
  plus a poll/diff timer (shared_preferences has no change stream).
- Optional secure/MMKV backend registration seams (no native deps by default).
- Streams to Buoy Desktop / MCP via the storage sync adapter (protocol v1),
  matching `@buoy-gg/storage`.
