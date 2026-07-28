# buoy_storage

Buoy storage inspector for Flutter — browse and monitor `shared_preferences`
(plus optional secure / MMKV backends) in an in-app panel that streams live to
[Buoy Desktop](https://buoy.gg).

Part of the [Buoy](https://buoy.gg) devtools suite. Ports `@buoy-gg/storage`
1:1: the same browser / events tabs, filters, storage keys, and sync protocol.

## Usage

Zero-config via the umbrella:

```dart
import 'package:buoy/buoy.dart';

MaterialApp(
  builder: (context, child) =>
      BuoyDevTools(child: child ?? const SizedBox.shrink()),
);
```

Or register the tool directly:

```dart
import 'package:buoy_storage/buoy_storage.dart';

if (kDebugMode) registerBuoyStorage();
```

### Live monitoring

`shared_preferences` has no change stream, so Buoy monitors writes two ways:

1. **Owned writes** — use `BuoyPrefs` instead of `SharedPreferences` for writes
   you want reflected instantly in the Events stream.
2. **Poll/diff** — while monitoring is on, Buoy snapshots and diffs all keys on
   a timer so writes made through any path still surface.

### Secure / MMKV (optional)

No native storage deps are pulled by default. Implement a backend against your
storage plugin and register it — its keys then show up in the browser (with a
Secure / MMKV badge and the instance they came from) and in the desktop/MCP
`secure.*` / `mmkv.*` actions:

```dart
registerBuoySecureBackend(mySecureBackend);
registerBuoyMmkvBackend(myMmkvBackend);
```

`BuoySecureBackend.keys()` returns one descriptor per key —
`{key, description?, keychainService?, requireAuthentication?}`. Keys marked
`requireAuthentication` are listed but never read (a read would fire a biometric
prompt). Secure keys are read once when the browser opens; each read hits the
keychain.

`BuoyMmkvBackend.snapshot()` returns one entry per instance —
`{id, encrypted, readOnly, entries: [{key, value, valueType}]}` where
`valueType` is `string` | `number` | `boolean` | `buffer`. MMKV is enumerable,
so Buoy also polls it for changes and emits `set.*` / `delete` events. To report
a write the moment it happens, call
`StorageEventStore.instance.recordOwnedWrite(storageType: 'mmkv', …)` from your
backend's setter.

See `example-flutter/lib/state/demo_storage.dart` for a working in-memory pair.

## License

See [buoy.gg](https://buoy.gg). Proprietary — © Buoy.
