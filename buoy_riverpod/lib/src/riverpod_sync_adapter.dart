/// Sync adapter for the `riverpod` tool — mirrors the SHAPES of
/// packages/jotai/src/jotai/sync/jotaiSyncAdapter.ts (version 1) under the new
/// `riverpod` tool id.
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

Map<String, Object?>? _asMap(Object? params) {
  if (params is Map<String, Object?>) return params;
  if (params is Map) return params.cast<String, Object?>();
  return null;
}

final riverpodSyncAdapter = ToolSyncAdapter(
  version: 1,
  getSnapshot: () => {
    'changes': [
      for (final c in riverpodStateStore.getChanges())
        c.toJson(serialize: serializeValue),
    ],
    'atoms': [
      for (final s in riverpodStateStore.getProviderSnapshots()) s.toJson(),
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
