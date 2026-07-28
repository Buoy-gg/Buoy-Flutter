/// One-call registration of the Riverpod state inspector — the Dart analog of
/// packages/jotai/src/preset.tsx. Registers the [BuoyTool] (dial + modal), the
/// [riverpodSyncAdapter], and the `riverpod` events-timeline source.
///
/// Does NOT create/attach the observer — the app owns its `ProviderScope`, so it
/// adds [buoyRiverpodObserver] to `ProviderScope(observers: [...])` itself
/// (mirrors how the Routes tool needs the app's router). Idempotent; safe to
/// call from the `buoy` umbrella.
library;

import 'package:buoy_core/buoy_core.dart';
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';

import 'riverpod_state_store.dart';
import 'riverpod_sync_adapter.dart';
import 'riverpod_types.dart';
import 'riverpod_tool/provider_change_detail.dart';
import 'riverpod_tool/provider_change_item.dart';
import 'riverpod_tool/riverpod_modal.dart';

bool _registered = false;

/// The Riverpod tool color — adapts Jotai's icon color (#6C47FF). The dial icon
/// is a water drop (Riverpod's river identity) rather than Jotai's "J" glyph.
const int riverpodIconColor = 0xFF6C47FF;

void registerBuoyRiverpod() {
  if (_registered) return;
  _registered = true;

  eventSourceRegistry.register(_riverpodEventSource());

  Buoy.registerTool(
    BuoyTool(
      id: 'riverpod',
      name: 'Riverpod',
      description: 'Provider state & write inspector',
      color: const Color(riverpodIconColor),
      icon: (size, _) => BuoyIcon(riverpodIconData, size: size),
      modalBuilder: (context, storage, onClose, onMinimize) => RiverpodModal(
        storage: storage,
        onClose: onClose,
        onMinimize: onMinimize,
      ),
    ),
    adapter: riverpodSyncAdapter,
  );
}

// ── Events-tool source ───────────────────────────────────────────────────────

int _unifiedId = 0;

EventSourceAdapter _riverpodEventSource() => EventSourceAdapter(
      id: 'riverpod',
      name: 'Riverpod',
      eventSources: const [EventSourceIds.riverpod],
      subscribe: (emit) => riverpodStateStore
          .subscribeToNewChanges((change) => emit(_transform(change))),
      // The store's change-listener count is private; like the network source,
      // report no count (filter badge shows no left count).
      rowBuilder: (context, event, onPress) => ProviderChangeItem(
        change: event.originalEvent as ProviderChange,
        onPress: onPress,
      ),
      detailBuilder: (context, event, _) {
        final change = event.originalEvent as ProviderChange;
        return ProviderChangeDetail(
          change: change,
          changes: [change],
          selectedIndex: 0,
          onIndexChange: (_) {},
          disableInternalFooter: true,
        );
      },
    );

UnifiedEvent _transform(ProviderChange change) {
  return UnifiedEvent(
    id: 'riverpod-${DateTime.now().millisecondsSinceEpoch}-${++_unifiedId}',
    source: EventSourceIds.riverpod,
    timestamp: change.timestamp,
    title: change.providerLabel,
    subtitle: change.hasValueChange
        ? change.diffSummary
        : providerCategoryName(change.category),
    status: change.category == ProviderChangeCategory.error
        ? EventStatus.error
        : change.hasValueChange
            ? EventStatus.success
            : EventStatus.neutral,
    originalEvent: change,
    data: change.toJson(),
  );
}
