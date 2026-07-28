# buoy_env

Environment-variable debugger for the [Buoy](https://buoy.gg) Flutter devtools.
Inspect and validate your app's env vars on-device — required-variable checks,
type detection, per-variable status badges, and a 0–100% health score — all
mirrored live to Buoy Desktop. A 1:1 Flutter port of `@buoy-gg/env`.

## Why registration (not discovery)?

Flutter has no enumerable `process.env`: `--dart-define` values are compile-time
and cannot be listed at runtime. So instead of auto-discovering vars, you hand
Buoy the map explicitly:

```dart
import 'package:buoy_env/buoy_env.dart';

registerBuoyEnv(
  vars: {
    'API_URL': const String.fromEnvironment('API_URL'),
    'ENVIRONMENT': const String.fromEnvironment('ENVIRONMENT'),
    // ...any runtime config strings
  },
  requiredEnvVars: [
    envVar('API_URL').withType('url').build(),
    RequiredEnvVar.value('ENVIRONMENT', 'production'),
    'FEATURE_FLAG', // existence check
  ],
);
```

### flutter_dotenv (optional)

`vars:` accepts any `Map<String, String>`, so a `.env` file works with no extra
dependency in this package:

```dart
await dotenv.load();
registerBuoyEnv(vars: dotenv.env, requiredEnvVars: [...]);
```

## Usage

`registerBuoyEnv()` is called automatically by the `buoy` umbrella
(`BuoyDevTools`). Call it yourself (once, before `runApp`) only when you depend
on `buoy_env` directly, or to supply `vars` / `requiredEnvVars`. Everything is
gated on `kDebugMode`.
