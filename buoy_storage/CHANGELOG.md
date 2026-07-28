## 0.3.0

- Initial release of the Buoy storage inspector for Flutter.
- Browse every `shared_preferences` key/value in an in-app panel, with a live
  Events stream, key-pattern filters, and pin/hide.
- Live monitoring of storage writes via an owned-write wrapper (`BuoyPrefs`)
  plus a poll/diff timer (shared_preferences has no change stream).
- Optional secure/MMKV backend registration seams (no native deps by default).
- Streams to Buoy Desktop / MCP via the storage sync adapter (protocol v1),
  matching `@buoy-gg/storage`.
