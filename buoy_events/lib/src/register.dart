/// Ports packages/events/src/preset.tsx (eventsToolPreset) — the one-call
/// registration of the events tool + its sync adapter with [Buoy].
library;

import 'package:buoy_core/buoy_core.dart';
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';

import 'events_sync_adapter.dart';
import 'events_tool/events_modal.dart';

bool _registered = false;

/// Register the unified events timeline. Idempotent. Called automatically by the
/// `buoy` umbrella widget AFTER the source tools (network/storage/routes) so
/// their [EventSourceAdapter]s are already in the registry; apps depending on
/// `buoy_events` directly call it once before `runApp`.
///
/// The tool captures nothing itself — it aggregates whatever source tools have
/// registered into `buoy_shared_ui`'s `eventSourceRegistry`.
void registerBuoyEvents() {
  if (_registered) return;
  _registered = true;

  Buoy.registerTool(
    BuoyTool(
      // RN toolId 'events'; EVENTS_ICON_COLOR (#00D4FF, cyan); timeline glyph.
      id: 'events',
      name: 'EVENTS',
      description: 'Unified event timeline',
      color: const Color(0xFF00D4FF),
      icon: (size, _) => BuoyIcon(eventsIconData, size: size),
      modalBuilder: (context, storage, onClose, onMinimize) => EventsModal(
        storage: storage,
        onClose: onClose,
        onMinimize: onMinimize,
      ),
    ),
    adapter: eventsSyncAdapter,
  );
}
