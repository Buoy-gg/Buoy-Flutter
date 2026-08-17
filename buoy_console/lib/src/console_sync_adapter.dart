/// Ports packages/console/src/sync/consoleSyncAdapter.ts.
///
/// Streams captured console entries from the device to the Buoy Desktop
/// dashboard. Field-for-field mirror of the RN adapter (version 1, snapshot
/// `{entries:[…]}`, action `clearEntries`) so the desktop ConsolePanel
/// `replaceEntries` from these snapshots with zero changes. Snapshots MUST be
/// JSON-serializable, so each entry's `args` are deep-sanitized (via
/// [ConsoleLogEntry.toJson]).
///
/// Oversized strings and the pre-rendered `message` are capped, and the entry
/// list is spent against a snapshot budget, so a single fat log cannot drop the
/// whole panel at the 2MB emit budget. The on-device store keeps the raw args.
library;

import 'package:buoy_core/buoy_core.dart';

import 'console_log_store.dart';
import 'sanitize.dart';

/// Soft cap so a burst of fat logs still fits under the 2MB emit budget.
const int maxSnapshotBytes = 1572864; // 1.5 * 1024 * 1024

/// One entry's args/message after string caps; fatter args collapse to a stub.
const int maxEntryBytes = 16 * 1024;

const Map<String, Object?> argsOmitted = {
  '__buoyTruncated': true,
  'note': 'Log payload omitted — inspect it on-device.',
};

/// One entry's wire form plus its measured cost, so the budget pass is free.
class _WireEntry {
  const _WireEntry(this.json, this.bytes);
  final Map<String, Object?> json;
  final int bytes;
}

/// Per-entry wire cache. A captured entry is never mutated — the store only
/// appends and trims — so keying on identity is correct and self-invalidating.
///
/// This is the whole cost of the tool. `sanitizeArgs` deep-copies every arg to
/// make it JSON-safe, and without a cache that copy is redone for all 1000
/// entries on every snapshot, ~5x/sec. Converting each entry once removes it
/// from the hot path entirely.
final Expando<_WireEntry> _wireCache = Expando<_WireEntry>('buoyConsoleWire');

_WireEntry _toWireEntry(ConsoleLogEntry entry) {
  final cached = _wireCache[entry];
  if (cached != null) return cached;

  // `toJson` already routes args through `sanitizeArgs` (which caps strings);
  // message and stack are raw on the model, so cap them here.
  final wired = Map<String, Object?>.of(entry.toJson());
  final message = wired['message'];
  if (message is String) wired['message'] = capString(message);
  final stack = wired['stack'];
  if (stack is String) wired['stack'] = capString(stack, 4 * 1024);

  // One walk decides both "is this entry too fat" and what it costs the
  // snapshot budget.
  final size = approxJsonSize(wired, maxEntryBytes);
  _WireEntry result;
  if (size.bytes <= maxEntryBytes) {
    result = _WireEntry(wired, size.bytes);
  } else {
    final stub = {...wired, 'args': [argsOmitted]};
    result = _WireEntry(stub, approxJsonSize(stub, maxEntryBytes).bytes);
  }
  _wireCache[entry] = result;
  return result;
}

/// Spend the snapshot budget newest-first, then restore chronological order.
/// A developer watching a crash cares about the last lines, so those are the
/// ones that survive a burst.
List<Map<String, Object?>> newestFitting(List<ConsoleLogEntry> entries) {
  final out = <Map<String, Object?>>[];
  var bytes = 16; // {"entries":[]}
  for (var i = entries.length - 1; i >= 0; i--) {
    final wired = _toWireEntry(entries[i]);
    if (bytes + wired.bytes > maxSnapshotBytes && out.isNotEmpty) break;
    out.add(wired.json);
    bytes += wired.bytes;
  }
  return out.reversed.toList();
}

/// The console tool's sync adapter — mirrors consoleSyncAdapter.ts.
final consoleSyncAdapter = ToolSyncAdapter(
  version: 1,
  getSnapshot: () => {
    'entries': newestFitting(ConsoleLogStore.instance.entries),
  },
  subscribe: (onChange) => ConsoleLogStore.instance.subscribe(onChange),
  actions: {
    'clearEntries': (_) {
      ConsoleLogStore.instance.clearEntries();
      return {'cleared': true};
    },
  },
);
