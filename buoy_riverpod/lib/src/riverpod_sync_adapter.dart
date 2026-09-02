/// Sync adapter for the `riverpod` tool — mirrors the SHAPES of
/// packages/jotai/src/jotai/sync/jotaiSyncAdapter.ts (version 2) under the new
/// `riverpod` tool id.
///
/// v2 (RN parity, Aug 2026): the per-snapshot stream is VALUE-FREE. Change-log
/// `prevValue`/`nextValue` are replaced with on-device markers and oversized /
/// unserializable `atoms[].currentValue` uses the same marker; dashboards
/// fetch values on demand via `getChangeDetail` / `getAtomValue`. Same hazard
/// as storage/redux/zustand: up to 200 changes × 2 values on every 200ms
/// snapshot janked every app that opened a dashboard.
///
/// Compatibility decision (logged in riverpod.md): the wire keeps Jotai's field
/// names (`changes`/`atoms`, actions `listAtoms`/`setAtom`/`clearEvents`) so a
/// future riverpod desktop panel can reuse the jotai renderer. Note MCP's
/// `get_jotai_state`/`jotai_action` target tool-id `jotai`, so they will NOT
/// auto-read `riverpod`; generic `get_snapshot`/`call_action` do.
///
/// `setAtom` is honestly unsupported: a [ProviderObserver] has no generic write
/// handle into providers, so it throws rather than pretend.
library;

import 'package:buoy_core/buoy_core.dart';

import 'riverpod_serialize.dart';
import 'riverpod_state_store.dart';
import 'riverpod_types.dart';

/// Sentinel used in WIRE-FORM snapshots in place of raw values. Byte-identical
/// to the RN constant — the desktop panel matches on `__buoyValueOnDevice`.
const Map<String, Object?> valueOnDevice = {
  '__buoyValueOnDevice': true,
  'note':
      'Atom values stay on the device — fetched on demand via getChangeDetail / getAtomValue.',
};

const int _maxChangeDetailBytes = 8 * 1024 * 1024;
const int _maxWirePayloadBytes = 16 * 1024;

/// Per-change wire cache — the store prepends and never mutates a recorded
/// change, so identity is a correct, self-invalidating key. `Expando` is the
/// `WeakMap`.
final Expando<Map<String, Object?>> _changeCache = Expando('riverpodWireChange');

Map<String, Object?> _toWireChange(ProviderChange change) {
  final cached = _changeCache[change];
  if (cached != null) return cached;
  final wire = change.toJson(serialize: serializeValue)
    ..['prevValue'] = valueOnDevice
    ..['nextValue'] = valueOnDevice;
  _changeCache[change] = wire;
  return wire;
}

Object? _toWireValue(Object? value) {
  final serialized = serializeValue(value);
  return isOverWireBudget(serialized, _maxWirePayloadBytes)
      ? valueOnDevice
      : serialized;
}

const Map<String, Object?> _cappedNote = {
  '__buoyTruncated': true,
  'note':
      'Exceeds the ${_maxChangeDetailBytes ~/ (1024 * 1024)}MB detail limit — inspect it on-device.',
};

Object? _cap(Object? value) {
  final serialized = serializeValue(value);
  return isOverWireBudget(serialized, _maxChangeDetailBytes) ? _cappedNote : serialized;
}

Map<String, Object?>? _asMap(Object? params) {
  if (params is Map<String, Object?>) return params;
  if (params is Map) return params.cast<String, Object?>();
  return null;
}

final riverpodSyncAdapter = ToolSyncAdapter(
  version: 2,
  getSnapshot: () => {
    'changes': [
      for (final c in riverpodStateStore.getChanges()) _toWireChange(c),
    ],
    'atoms': [
      for (final s in riverpodStateStore.getProviderSnapshots())
        {...s.toJson(), 'currentValue': _toWireValue(s.currentValue)},
    ],
  },
  subscribe: (onChange) {
    final unsubChanges = riverpodStateStore.subscribe((_) => onChange());
    final unsubProviders =
        riverpodStateStore.subscribeToProviders((_) => onChange());
    return () {
      unsubChanges();
      unsubProviders();
    };
  },
  actions: {
    'clearEvents': (_) {
      riverpodStateStore.clearChanges();
      return null;
    },

    /// On-demand detail: one change's real prevValue/nextValue. The
    /// per-snapshot stream stays value-free; this is the explicit,
    /// size-guarded channel for the detail pane.
    'getChangeDetail': (params) {
      final id = _asMap(params)?['id'] as String?;
      if (id == null || id.isEmpty) return {'found': false, 'reason': 'missing id'};
      final change = riverpodStateStore.getChangeById(id);
      if (change == null) return {'found': false, 'reason': 'unknown id'};
      return {
        'found': true,
        'id': id,
        'prevValue': _cap(change.prevValue),
        'nextValue': _cap(change.nextValue),
      };
    },

    /// On-demand current value for one provider. Wire-form snapshots replace
    /// oversized / unserializable `currentValue` with [valueOnDevice].
    'getAtomValue': (params) {
      final label = _asMap(params)?['label'] as String?;
      if (label == null || label.isEmpty) {
        return {'found': false, 'reason': 'missing label'};
      }
      final provider = riverpodStateStore.getProvider(label);
      if (provider == null) return {'found': false, 'reason': 'unknown label'};
      return {'found': true, 'label': label, 'currentValue': _cap(provider.currentValue)};
    },

    /// Compact provider reader for a remote driver (mirrors jotai `listAtoms`).
    'listAtoms': (params) {
      final map = _asMap(params);
      final includeValues = map?['includeValues'] == true;
      final limitRaw = map?['limit'];
      final limit = limitRaw is int ? limitRaw : null;
      final all = riverpodStateStore.getProviders();
      final capped =
          (limit != null && limit > 0) ? all.take(limit).toList() : all;
      final atoms = [
        for (final p in capped)
          {
            'label': p.label,
            'changes': p.changeCount,
            // Riverpod providers aren't remotely writable via the observer.
            'writable': false,
            if (includeValues) 'currentValue': serializeValue(p.currentValue),
          },
      ];
      return {
        'atoms': atoms,
        'total': all.length,
        'returned': atoms.length,
        'includedValues': includeValues,
      };
    },

    /// Writes are not supported: a ProviderObserver has no generic write path.
    'setAtom': (_) {
      throw StateError(
        'Riverpod providers are read-only via the observer — remote setAtom '
        'is not supported.',
      );
    },
  },
);
