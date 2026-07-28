# Buoy Shared UI for Flutter

**The shared UI kit + stores behind Buoy's Flutter devtools** — the macOS/Buoy color
systems, the list/badge/filter widgets every tool renders, the event-store base class,
and the centralized dev-tool storage keys. The Dart mirror of `@buoy-gg/shared-ui`.

> **Beta** — this is an internal building block. You usually want a tool package (start
> with [`buoy_network`](https://pub.dev/packages/buoy_network)) or the
> [`buoy`](https://pub.dev/packages/buoy) umbrella; both bring `buoy_shared_ui` in.

## What's inside

- **Colors** — `MacOSColors`, `BuoyColors`, `GameUIColors`, the `hexAlpha` extension.
- **Widgets** — `DataViewer`, `ModalHeader`, `TabSelector`, `DevToolsCard`, `CompactRow`,
  `SearchBar`, `CompactFilterChips`, `DynamicFilterView`, badges, `EmptyState`,
  `CollapsibleSection`, `StatsCard`, `CopyButton`, `PowerToggleButton`, and more.
- **Stores** — `BaseEventStore` (ring-buffer event store with subscriber-count
  notifications) + `subscriberCountNotifier`.
- **Storage keys** — `devToolsStorageKeys` + `isDevToolsStorageKey`, shared across tools so
  Buoy's own keys stay filterable.
- **Icons** — `BuoyIcons`, the Material glyphs mapping the Lucide set the RN tools use.

---

📚 [Docs](https://buoy.gg) · [Roadmap](https://buoy.gg/roadmap) · [React Native version](https://github.com/Buoy-gg/buoy)

Proprietary software. © Buoy LLC. [Terms](https://buoy.gg/terms)
