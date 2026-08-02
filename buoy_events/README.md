# buoy_events

Buoy unified events timeline for Flutter — one chronological stream that
aggregates every other Buoy tool's events (network, storage, routes) so a whole
user flow reads in order.

Part of the [Buoy](https://buoy.gg) Flutter devtools suite. This is the
**aggregator**: it captures nothing itself. Each source tool registers an
`EventSourceAdapter` into `buoy_shared_ui`'s `eventSourceRegistry` at its own
`registerBuoyX()` time, and `buoy_events` renders whatever is registered — so it
depends on nothing tool-specific.

## Features

- ONE interleaved, newest-first timeline across all installed source tools.
- Per-source filter badges (toggle a source on/off; subscriber + event counts).
- Header search filters the timeline live as you type (titles, subtitles, full
  network URLs) — stacks with the source badges.
- The tools' REAL detail views — a network event opens the same detail page the
  Network tool shows, including the shared Ignore-Domain / Ignore-URL toggles
  that hide matches from **both** the Events and Network lists.
- Capture power toggle + Copy (markdown/json/plaintext/mermaid export).
- Streams to Buoy Desktop and the MCP server (`get_events`) via the events sync
  adapter (protocol v2).

## Usage

The `buoy` umbrella registers it automatically. To use it standalone:

```dart
import 'package:buoy_events/buoy_events.dart';

void main() {
  if (kDebugMode) {
    // Register the source tools first so their adapters are in the registry…
    registerBuoyNetwork();
    registerBuoyStorage();
    registerBuoyRoutes();
    // …then the aggregator.
    registerBuoyEvents();
  }
  runApp(const MyApp());
}
```

See <https://buoy.gg> for full docs.
