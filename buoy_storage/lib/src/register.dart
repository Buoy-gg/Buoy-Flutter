/// Ports packages/storage/src/preset.tsx (storageToolPreset) — the one-call
/// registration of the storage tool + sync adapter with [Buoy].
library;

import 'package:buoy_core/buoy_core.dart';
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';

import 'storage_capture.dart';
import 'storage_sync_adapter.dart';
import 'storage_tool/storage_event_card.dart';
import 'storage_tool/storage_event_detail.dart';
import 'storage_tool/storage_models.dart';
import 'storage_tool/storage_modal.dart';
import 'storage_tool/storage_value_type.dart';

bool _registered = false;

/// One-call setup for the storage tool: registers the tool + its sync adapter
/// with [Buoy]. Idempotent. Called automatically by the `buoy` umbrella widget;
/// apps depending on `buoy_storage` directly call it once before `runApp`.
///
/// Unlike the network tool, no permanent capture subscriber is installed —
/// capture runs only while a dashboard watches the adapter or the modal's
/// Events monitor is on (RN backpressure parity: "subscribing starts the
/// lifecycle").
void registerBuoyStorage() {
  // Night modals draw the shared ToolBackground; publish it once (idempotent).
  installToolBackground();
  if (_registered) return;
  _registered = true;

  // Contribute the storage source to the events-tool timeline (RN
  // `tryLoadStorageSource` in autoDiscoverEventSources.ts).
  eventSourceRegistry.register(_storageEventSource());

  Buoy.registerTool(
    BuoyTool(
      // RN toolId 'storage'; color = settings.ts storage tool color (#BA68C8);
      // icon = the database glyph (STORAGE icon).
      id: 'storage',
      name: 'Storage',
      description: 'Browse & monitor stored data',
      color: const Color(0xFFBA68C8),
      icon: (size, _) => BuoyIcon(storageIconData, size: size),
      modalBuilder: (context, storage, onClose, onMinimize) => StorageModal(
        storage: storage,
        onClose: onClose,
        onMinimize: onMinimize,
      ),
    ),
    adapter: storageSyncAdapter,
  );
}

// ── Events-tool source ───────────────────────────────────────────────────────

/// The storage [EventSourceAdapter] for the unified timeline. [StorageEventStore]
/// extends [BaseEventStore], so subscription rides its `onEvent` per-event hook
/// (capture auto-starts on the first subscriber — RN backpressure parity).
EventSourceAdapter _storageEventSource() => EventSourceAdapter(
      id: 'storage',
      name: 'Storage',
      eventSources: const [
        EventSourceIds.storageAsync,
        EventSourceIds.storageMmkv,
      ],
      subscribe: (emit) => StorageEventStore.instance.onEvent((event) {
        // The store's initial scan synthesizes a `setItem` for every key
        // already on disk (so the STORAGE tool's state views include
        // pre-existing keys). In a TIMELINE those read as dozens of writes
        // that never happened — stamped with the scan moment, so the first
        // subscribe after a quiet boot instantly "captured" ~60 events. This
        // timeline reports what happens, not what exists. (RN parity.)
        if (event.initialScan) return;
        emit(_transformStorageEvent(event));
      }),
      subscriberCount: () =>
          StorageEventStore.instance.getSubscriberCounts().total,
      rowBuilder: (context, event, onPress) {
        final e = event.originalEvent as StorageEvent;
        return StorageEventCard(
          storageKey: e.key.isEmpty ? 'unknown' : e.key,
          lastAction: e.action,
          lastEventTimestamp: e.timestamp,
          storageTypes: {e.storageType},
          onPress: onPress,
        );
      },
      detailBuilder: (context, event, _) {
        final e = event.originalEvent as StorageEvent;
        // Single-event conversation — RN builds the same one-event detail.
        return StorageEventDetail(
          conversation: StorageConversation(
            key: e.key.isEmpty ? 'unknown' : e.key,
            events: [e],
            lastEvent: e,
            totalOperations: 1,
            currentValue: e.value,
            valueType: getValueType(e.value),
            storageTypes: {e.storageType},
          ),
        );
      },
    );

int _storageUnifiedId = 0;

/// Ports `transformStorageEvent` (autoDiscoverEventSources.ts).
UnifiedEvent _transformStorageEvent(StorageEvent e) {
  final source = e.storageType == 'async'
      ? EventSourceIds.storageAsync
      : EventSourceIds.storageMmkv;

  // Title: humanized action label (async only, RN labelMap).
  const labelMap = {
    'setItem': 'Set Item',
    'removeItem': 'Remove Item',
    'mergeItem': 'Merge Item',
    'clear': 'Clear All',
    'multiSet': 'Multi Set',
    'multiRemove': 'Multi Remove',
    'multiMerge': 'Multi Merge',
  };
  var title = e.action;
  if (e.storageType == 'async') title = labelMap[e.action] ?? e.action;

  // Subtitle.
  var subtitle = '';
  if (e.storageType == 'async') {
    switch (e.action) {
      case 'setItem':
      case 'removeItem':
      case 'mergeItem':
        subtitle = e.key.isEmpty ? 'unknown key' : e.key;
        break;
      case 'clear':
        subtitle = 'all keys';
        break;
      default:
        subtitle = e.key.isEmpty ? 'unknown key' : e.key;
    }
  } else {
    subtitle = e.key.isNotEmpty ? e.key : (e.instanceId ?? 'unknown');
  }

  // Status: success for set/merge, else neutral (RN parity).
  final a = e.action;
  final isWrite = a.contains('set') ||
      a.contains('Set') ||
      a.contains('merge') ||
      a.contains('Merge');

  return UnifiedEvent(
    id: 'storage-${DateTime.now().millisecondsSinceEpoch}-${++_storageUnifiedId}',
    source: source,
    timestamp: e.timestamp.millisecondsSinceEpoch,
    title: title,
    subtitle: subtitle,
    status: isWrite ? EventStatus.success : EventStatus.neutral,
    originalEvent: e,
    data: e.toJson(),
  );
}
