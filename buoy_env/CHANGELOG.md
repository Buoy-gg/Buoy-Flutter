## 0.3.0

- Initial release of the Buoy environment-variable debugger for Flutter.
- Explicit env registration (`registerBuoyEnv(vars: {...})` / `BuoyEnv.configure`)
  — the Flutter analog of RN's auto-discovery, since `--dart-define` values are
  not enumerable. Optional `flutter_dotenv` integration via a no-dependency seam
  (`registerBuoyEnv(vars: dotenv.env)`).
- Required-variable validation (`RequiredEnvVar` + fluent `envVar()` builder):
  existence, expected-value, and expected-type checks with per-var status
  (Valid / Missing / Wrong / Type Error / Set).
- Type detection (string / number / boolean / array / object / url) and a
  0–100% environment health score with HEALTHY / WARNING / ERROR / CRITICAL
  status, matching `@buoy-gg/env`.
- 1:1 modal UI: health header, ALL / MISSING / ISSUES filter cards, searchable
  variable list with expandable value / expected / description rows and type
  badges.
- Streams to Buoy Desktop / MCP via the env sync adapter (protocol v1),
  matching `@buoy-gg/env`.
