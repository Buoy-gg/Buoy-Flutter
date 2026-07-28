import 'package:buoy_core/buoy_core.dart';
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';

import 'network_capture.dart';
import 'network_tool/network_detail_view.dart';
import 'network_tool/network_event_row.dart';
import 'network_tool/network_modal.dart';

bool _registered = false;

/// One-call setup for the network tool: installs the HTTP capture hook,
/// keeps the in-app store live, and registers the tool + sync adapter with
/// [Buoy]. Idempotent. Called automatically by the `buoy` umbrella widget;
/// apps depending on `buoy_network` directly call it once before `runApp`
/// (or let `BuoyDevTools` mount trigger it via the umbrella).
void registerBuoyNetwork({bool installHttpOverrides = true}) {
  if (_registered) return;
  _registered = true;

  if (installHttpOverrides) BuoyHttpOverrides.install();

  // Keep capture on for the in-app panel even when no desktop is watching.
  NetworkEventStore.instance.subscribe(() {});

  // Contribute the network source to the events-tool timeline (RN
  // `tryLoadNetworkSource` in autoDiscoverEventSources.ts).
  eventSourceRegistry.register(_networkEventSource());

  Buoy.registerTool(
    BuoyTool(
      id: 'network',
      name: 'Network',
      description: 'Inspect HTTP requests',
      color: const Color(0xFF38BDF8),
      icon: (size, _) => BuoyIcon(networkIconData, size: size),
      modalBuilder: (context, storage, onClose, onMinimize) => NetworkModal(
        storage: storage,
        onClose: onClose,
        onMinimize: onMinimize,
      ),
    ),
    adapter: networkSyncAdapter,
  );
}

// ── Events-tool source ───────────────────────────────────────────────────────

/// The network [EventSourceAdapter] for the unified timeline.
///
/// [NetworkEventStore] predates [BaseEventStore] and exposes only a bulk-notify
/// `subscribe()` (no per-event callback), so — rather than retrofit the shipped
/// store/panel/adapter — the events source is SHIMMED: a diff over the store's
/// notify emits a [UnifiedEvent] whenever a request first appears or its
/// response/error/timing changes. Existing buffered requests are seeded (not
/// re-emitted) so subscribing doesn't replay history (RN parity: the network
/// source uses `onEvent(cb, replayExisting=false)`).
EventSourceAdapter _networkEventSource() => EventSourceAdapter(
      id: 'network',
      name: 'Network',
      eventSources: const [EventSourceIds.network],
      // Standalone store — no BaseEventStore subscriber tracking to expose.
      subscribe: (emit) {
        final store = NetworkEventStore.instance;
        final lastSignature = <String, String>{};

        String signatureOf(NetworkCaptureEvent e) =>
            '${e.status}|${e.duration}|${e.error}|${e.responseSize}';

        // Seed current events without emitting (don't replay buffered history).
        for (final e in store.events) {
          lastSignature[e.id] = signatureOf(e);
        }

        void pump() {
          // Store holds newest-first; walk oldest→newest so the unified store's
          // prepend keeps chronological (newest-first) order.
          final events = store.events;
          for (var i = events.length - 1; i >= 0; i--) {
            final e = events[i];
            final sig = signatureOf(e);
            if (lastSignature[e.id] == sig) continue;
            lastSignature[e.id] = sig;
            emit(_transformNetworkEvent(e));
          }
        }

        return store.subscribe(pump);
      },
      rowBuilder: (context, event, onPress) {
        final e = event.originalEvent as NetworkCaptureEvent;
        return NetworkEventRow(event: e, onTap: (_) => onPress());
      },
      detailBuilder: (context, event, _) {
        final e = event.originalEvent as NetworkCaptureEvent;
        // NetworkDetailView already wires the shared IgnoredPatternsStore's
        // Ignore-Domain / Ignore-URL toggles, so hiding a domain here also hides
        // it from the Network tool and the events list (both directions).
        return NetworkDetailView(event: e);
      },
    );

int _networkUnifiedId = 0;

/// Ports `transformNetworkEvent` (autoDiscoverEventSources.ts).
UnifiedEvent _transformNetworkEvent(NetworkCaptureEvent e) {
  final EventStatus status;
  if (e.status == null) {
    status = EventStatus.pending;
  } else if (e.error != null || e.status! >= 400) {
    status = EventStatus.error;
  } else if (e.status! >= 200 && e.status! < 400) {
    status = EventStatus.success;
  } else {
    status = EventStatus.neutral;
  }

  final uri = Uri.tryParse(e.url);
  final path = uri?.path ?? e.url;
  final host = uri?.host ?? '';
  final title = e.operationName ?? '${e.method} ${path.isEmpty ? e.url : path}';

  final parts = <String>[];
  if (e.status != null) {
    parts.add('${e.status}');
  } else if (e.error != null) {
    parts.add('Error');
  } else {
    parts.add('Pending');
  }
  if (e.duration != null) parts.add('${e.duration}ms');
  if (host.isNotEmpty) parts.add(host);

  return UnifiedEvent(
    id: 'network-${DateTime.now().millisecondsSinceEpoch}-${++_networkUnifiedId}',
    source: EventSourceIds.network,
    timestamp: e.timestamp,
    title: title,
    subtitle: parts.join(' · '),
    status: status,
    originalEvent: e,
    data: e.toJson(),
  );
}
