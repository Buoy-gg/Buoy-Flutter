## 0.3.0

- Initial release of the Buoy unified events timeline for Flutter.
- Aggregator tool — captures nothing itself; each source tool (buoy_network /
  buoy_storage / buoy_routes) contributes an `EventSourceAdapter` to
  `buoy_shared_ui`'s `eventSourceRegistry` at register time (the Dart analog of
  RN's optional-require auto-discovery), so `buoy_events` depends on nothing
  tool-specific.
- One chronological (newest-first) timeline interleaving every source, with
  per-source filter badges (subscriber + event counts), SOURCE tags, and the
  tools' REAL detail views — a network event opens the same NetworkDetailView
  the Network tool shows, with the shared Ignore-Domain / Ignore-URL toggles
  that hide matches from both tools.
- Enabled-source badges + capturing toggle persist (`@react_buoy_events_*`
  keys, matching `@buoy-gg/events`).
- LLM/MCP export via the events sync adapter (protocol v2): the `exportEvents`
  action drives the same Copy-Settings formatter (markdown / json / plaintext /
  mermaid, presets llm / bugReport / json / errors / minimal / mermaid) MCP
  `get_events` reads.
