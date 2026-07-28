/// Ports packages/console/src/sync/consoleSyncAdapter.ts.
///
/// Streams captured console entries from the device to the Buoy Desktop
/// dashboard. Field-for-field mirror of the RN adapter (version 1, snapshot
/// `{entries:[…]}`, action `clearEntries`) so the desktop ConsolePanel
/// `replaceEntries` from these snapshots with zero changes. Snapshots MUST be
/// JSON-serializable, so each entry's `args` are deep-sanitized (via
/// [ConsoleLogEntry.toJson]).
library;

import 'package:buoy_core/buoy_core.dart';

import 'console_log_store.dart';

/// The console tool's sync adapter — mirrors consoleSyncAdapter.ts.
final consoleSyncAdapter = ToolSyncAdapter(
  version: 1,
  getSnapshot: () => {
    'entries': [for (final e in ConsoleLogStore.instance.entries) e.toJson()],
  },
  subscribe: (onChange) => ConsoleLogStore.instance.subscribe(onChange),
  actions: {
    'clearEntries': (_) {
      ConsoleLogStore.instance.clearEntries();
      return {'cleared': true};
    },
  },
);
