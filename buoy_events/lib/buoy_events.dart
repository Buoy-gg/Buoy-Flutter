/// Buoy unified events timeline for Flutter.
///
/// The aggregator tool: it captures nothing itself. Each source tool
/// (buoy_network / buoy_storage / buoy_routes) registers an `EventSourceAdapter`
/// into `buoy_shared_ui`'s `eventSourceRegistry` at its own `registerBuoyX()`
/// time; this package reads that registry and renders ONE chronological
/// timeline with source badges, per-source filters, the tools' real detail
/// views, and LLM/MCP export. Ports `@buoy-gg/events` 1:1 (sync protocol v2;
/// MCP `get_events` reads it via the `exportEvents` action).
///
/// Call [registerBuoyEvents] once (the `buoy` umbrella does it automatically,
/// after the source tools), then mount the `buoy` umbrella / a [BuoyTool].
library;

export 'package:buoy_core/buoy_core.dart'
    show Buoy, BuoyDevTools, BuoySyncClient, BuoyTool;

export 'src/copy_settings.dart';
export 'src/event_export_formatter.dart';
export 'src/events_sync_adapter.dart' show eventsSyncAdapter;
export 'src/events_tool/events_modal.dart' show EventsModal;
export 'src/register.dart' show registerBuoyEvents;
export 'src/unified_event_store.dart'
    show unifiedEventStore, UnifiedEventStore, eventSourceToDiscoveryId;
