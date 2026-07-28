/// Ports packages/images/src/sync/imagesSyncAdapter.ts — the device→desktop /
/// MCP bridge. Payload/version/action names match the RN adapter field-for-field
/// so `get_images`, `image_action`, and `set_image_simulation` round-trip
/// unchanged.
library;

import 'package:buoy_core/buoy_core.dart';
import 'package:flutter/painting.dart' show PaintingBinding;

import 'image_record.dart';
import 'images_actions.dart';
import 'images_store.dart';

/// Slim wire form of a record (heavy/derived fields precomputed + rounded) —
/// RN toWire.
Map<String, Object?> _toWire(ImageRecord record) {
  final factor = oversizeFactor(record);
  final needed = neededPixels(record);
  return {
    'id': record.id,
    'lib': record.lib.name,
    'uri': record.uri,
    'kind': record.sourceKind.name,
    'status': record.status.name,
    'mounted': record.mounted,
    'cache': record.cacheVerdict?.name,
    'cacheSource': record.cacheVerdictSource,
    'ms': record.durationMs?.round(),
    'intrinsic': record.intrinsic?.toJson(),
    'layout': record.layout?.toJson(),
    'neededPx': needed?.toJson(),
    'oversizeFactor': factor != null ? (factor * 100).round() / 100 : null,
    'decodedKB': (estDecodedBytes(record) / 1024).round(),
    'wastedKB': (estWastedBytes(record) / 1024).round(),
    'progressSeen': record.progressSeen,
    'bytesTotal': record.bytesTotal,
    'error': record.error,
    'errorCode': record.errorCode,
    'loadCount': record.loadCount,
    'overrideLabel': record.overrideLabel,
    'hasAltText': record.hasAltText,
    'layoutShifts': record.layoutShifts,
    'ageMs': DateTime.now().millisecondsSinceEpoch - record.createdAt,
  };
}

ImageRecord _requireRecord(Object? params) {
  final id = params is Map ? params['id'] : null;
  if (id is! int) throw Exception('Missing numeric `id` param');
  final record = ImagesStore.instance.getRecord(id);
  if (record == null) {
    throw Exception(
      'Image record $id not found (cleared or evicted) — re-run the list '
      'action for current ids.',
    );
  }
  return record;
}

Map<String, Object?> _overview() {
  final snapshot = ImagesStore.instance.getSnapshot();
  final modes = ImagesActions.instance.globalModes;
  return {
    'stats': computeStats(snapshot).toJson(),
    'captureStatus': const CaptureStatus(installed: true).toJson(),
    'globalModes': {'network': modes.network, 'blank': modes.blank},
    'insights': computeInsights(snapshot).toJson(),
    // records handled by the caller (reverse + slice + toWire)
    '_records': snapshot,
  };
}

List<Map<String, Object?>> _wireRecords(List<ImageRecord> records) =>
    [for (final r in records) _toWire(r)];

final imagesSyncAdapter = ToolSyncAdapter(
  version: 1,
  getSnapshot: () {
    final overview = _overview();
    final records =
        (overview.remove('_records') as List<ImageRecord>).reversed.toList();
    return {
      ...overview,
      'records': _wireRecords(records.take(100).toList()),
    };
  },
  subscribe: (onChange) {
    final unsubStore = ImagesStore.instance.subscribe(onChange);
    final unsubActions = ImagesActions.instance.subscribeActions(onChange);
    return () {
      unsubStore();
      unsubActions();
    };
  },
  actions: {
    /// List records (newest first). Params: { limit?, status? }.
    'list': (params) {
      final p = params is Map ? params : const {};
      final limit = ((p['limit'] as int?) ?? 50).clamp(1, 200);
      final overview = _overview();
      var records =
          (overview.remove('_records') as List<ImageRecord>).reversed.toList();
      final status = p['status'] as String?;
      if (status != null) {
        records = records.where((r) => r.status.name == status).toList();
      }
      return {
        ...overview,
        'total': records.length,
        'records': _wireRecords(records.take(limit).toList()),
      };
    },

    /// Full detail for one record. Params: { id }.
    'getDetail': (params) {
      final record = _requireRecord(params);
      return {..._toWire(record), 'errorHeaders': record.errorHeaders};
    },

    /// Bypass-cache reload. Params: { id }.
    'hardReload': (params) =>
        ImagesActions.instance.hardReloadRecord(_requireRecord(params)).toJson(),

    /// Plain fresh load attempt. Params: { id }.
    'retry': (params) =>
        ImagesActions.instance.retryRecord(_requireRecord(params)).toJson(),

    /// Flash a red border on the on-screen image. Params: { id }.
    'flash': (params) {
      ImagesActions.instance.flashRecord(_requireRecord(params).id);
      return {'ok': true, 'message': 'Flashing for 2.5s'};
    },

    /// Apply a simulation override. Params: { id, kind, uri? } where kind is
    /// 'error' | 'hang' | 'blank' | 'url' ('url' requires uri).
    'setOverride': (params) {
      final record = _requireRecord(params);
      final p = params as Map;
      final kind = p['kind'] as String?;
      if (kind == 'url') {
        final uri = p['uri'] as String?;
        if (uri == null) throw Exception("kind 'url' requires a `uri` param");
        ImagesActions.instance.setOverride(
          record.id,
          ImageOverride(
            source: OverrideSource(OverrideKind.url, uri: uri),
            label: 'URL swapped',
          ),
        );
        return {'ok': true, 'message': 'Source overridden to $uri'};
      }
      const entries = {
        'error': (kind: OverrideKind.error, label: 'Forced error'),
        'hang': (kind: OverrideKind.hang, label: 'Forced loading'),
        'blank': (kind: OverrideKind.blank, label: 'Blanked'),
      };
      final entry = kind != null ? entries[kind] : null;
      if (entry == null) throw Exception('Unknown override kind: $kind');
      if (!record.mounted) {
        return {
          'ok': false,
          'message': 'Instance unmounted — overrides need the image on screen',
        };
      }
      ImagesActions.instance.setOverride(
        record.id,
        ImageOverride(source: OverrideSource(entry.kind), label: entry.label),
      );
      return {'ok': true, 'message': '${entry.label} applied'};
    },

    /// Remove a simulation override. Params: { id }.
    'clearOverride': (params) {
      ImagesActions.instance.clearOverride(_requireRecord(params).id);
      return {
        'ok': true,
        'message': 'Override removed — original source restored',
      };
    },

    /// Mass action on every mounted image. Params: { kind } where kind is
    /// 'error' | 'loading' | 'blank' | 'reload' | 'flash' | 'restore'.
    'massAction': (params) {
      final kind = params is Map ? params['kind'] as String? : null;
      final actions = ImagesActions.instance;
      switch (kind) {
        case 'error':
          final n = actions.setOverrideForAllMounted(
            const OverrideSource(OverrideKind.error),
            'Forced error',
          );
          return {'ok': n > 0, 'message': 'Forced error on $n images'};
        case 'loading':
          final n = actions.setOverrideForAllMounted(
            const OverrideSource(OverrideKind.hang),
            'Forced loading',
          );
          return {'ok': n > 0, 'message': 'Forced loading on $n images'};
        case 'blank':
          final n = actions.setOverrideForAllMounted(
            const OverrideSource(OverrideKind.blank),
            'Blanked',
          );
          return {'ok': n > 0, 'message': 'Blanked $n images'};
        case 'reload':
          return actions.hardReloadAllMounted().toJson();
        case 'flash':
          final n = actions.flashAllMounted();
          return {'ok': n > 0, 'message': 'Flashing $n images'};
        case 'restore':
          final n = actions.clearAllOverrides();
          return {'ok': true, 'message': 'Restored $n images'};
        default:
          throw Exception('Unknown mass kind: $kind');
      }
    },

    /// Global network simulation. Params: { mode: 'normal'|'offline'|'cold' }.
    'setNetworkMode': (params) {
      final mode = params is Map ? params['mode'] as String? : null;
      final parsed = switch (mode) {
        'normal' => NetworkMode.normal,
        'offline' => NetworkMode.offline,
        'cold' => NetworkMode.cold,
        _ => throw Exception("mode must be 'normal' | 'offline' | 'cold'"),
      };
      ImagesActions.instance.setNetworkMode(parsed);
      final modes = ImagesActions.instance.globalModes;
      return {
        'ok': true,
        'modes': {'network': modes.network, 'blank': modes.blank},
      };
    },

    /// Chrome-style disable-images. Params: { enabled: boolean }.
    'setBlankImages': (params) {
      final enabled = params is Map && params['enabled'] == true;
      ImagesActions.instance.setBlankImages(enabled);
      final modes = ImagesActions.instance.globalModes;
      return {
        'ok': true,
        'modes': {'network': modes.network, 'blank': modes.blank},
      };
    },

    /// Clear the captured registry (keeps in-flight loads).
    'clearRecords': (_) {
      ImagesStore.instance.clearRecords();
      return {'ok': true, 'message': 'Registry cleared'};
    },

    /// Re-encode at displayed size — no Flutter equivalent (deviation).
    'proveSavings': (params) {
      _requireRecord(params);
      return {
        'ok': false,
        'message': 'On-device re-encode is not supported in the Flutter port',
      };
    },

    /// Best-effort disk eviction via a disk-backed provider's cacheManager.
    'evictDisk': (params) {
      _requireRecord(params);
      return {
        'ok': false,
        'message':
            'Per-entry disk eviction is not exposed by the Flutter image cache '
            '(use clearExpoCaches to clear the memory cache).',
      };
    },

    /// Clear the Flutter image (memory) cache. Params ignored.
    'clearExpoCaches': (_) {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      return {'ok': true, 'message': 'Cleared Flutter image (memory) cache'};
    },

    'getCaptureStatus': (_) => const CaptureStatus(installed: true).toJson(),
  },
);
