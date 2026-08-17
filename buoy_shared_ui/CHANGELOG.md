## 0.3.2

- Re-exports the new `buoy_core` wire-size guards (`approxJsonSize`,
  `isOverWireBudget`, `isJsonEncodable`, `maxSnapshotEmitBytes`,
  `maxActionResultBytes`) so tool adapters import them from their usual barrel.

## 0.3.1

- New `devToolsStorageKeys.network` keys: `saved()` (pinned + saved request
  snapshots) and `overrides()` (response-override rules) — same keys as RN, so
  the persisted blobs are interchangeable between the two runtimes.
- `ModalHeaderBack` gains a semantic `label` so every tool's back button is
  announced and targetable by assistive tech / UI drivers.
- `DevtoolsCard` refinements for header menus.

## 0.3.0

- Initial extraction from `buoy_network`: the shared color systems, list/badge/filter
  widgets, `DataViewer`, and modal chrome now live here so every Buoy Flutter tool can
  share them.
- New shared ports from `@buoy-gg/shared-ui`: `BaseEventStore` (+ subscriber-count
  notifier), `devToolsStorageKeys`/`isDevToolsStorageKey`, `CompactRow`, `EmptyState`
  family, `SearchBar`, `CompactFilterChips`, `StatusBadge`/`CountBadge`/`PillBadge`,
  `ExpandedInfoRow`, `CollapsibleSection`, `StatsCard`, `RelativeTime`, and the Buoy icon
  set.
