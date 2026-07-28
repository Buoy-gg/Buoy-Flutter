# buoy_riverpod

Riverpod state inspector for Flutter — the state-inspector tool in the
[Buoy](https://buoy.gg) devtools suite. Browse every provider's live value and a
`prev → next` write log with tree/split diffs, in an in-app panel that streams to
Buoy Desktop.

Riverpod is the closest analog to Jotai (atom-like providers), so this ports the
`@buoy-gg/jotai` tool's UI onto a `ProviderObserver` backend.

## Setup

```dart
import 'package:buoy_riverpod/buoy_riverpod.dart';

void main() {
  registerBuoyRiverpod(); // or use the `buoy` umbrella widget
  runApp(
    ProviderScope(
      observers: const [buoyRiverpodObserver],
      child: const MyApp(),
    ),
  );
}
```

Name your providers (`StateProvider(..., name: 'counter')`) so the list reads
well — unnamed providers fall back to their runtime type.

See <https://buoy.gg> for docs.
