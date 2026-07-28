/// Ports packages/shared/src/storage/devToolsStorageKeys.ts.
///
/// Centralized storage keys for every dev tool. All keys start with the
/// `@react_buoy` prefix so the Storage Browser can filter Buoy's own keys out.
/// Key strings here are byte-for-byte identical to the RN source so persisted
/// state and cross-framework filtering line up.
library;

class BubbleKeys {
  const BubbleKeys();
  String root() => '${DevToolsStorageKeys.base}_bubble';
  String settings() => '${root()}_settings';
  String userPreferences() => '${root()}_user_preferences';
  String position() => '${root()}_position';
}

class ModalKeys {
  const ModalKeys();
  String root() => '${DevToolsStorageKeys.base}_modal';
  String state() => '${root()}_state';
  String position() => '${root()}_position';
  String dimensions() => '${root()}_dimensions';
  String hintAcknowledged() => '${root()}_hint_acknowledged';
}

class SettingsKeys {
  const SettingsKeys();
  String root() => '${DevToolsStorageKeys.base}_settings';
  String theme() => '${root()}_theme';
  String preferences() => '${root()}_preferences';
  String wifiEnabled() => '${root()}_wifi_enabled';
  String global() => '${root()}_global';
  String activeTab() => '${root()}_active_tab';
  String modalOpen() => '${root()}_modal_open';
}

class DialKeys {
  const DialKeys();
  String root() => '${DevToolsStorageKeys.base}_dial';
  String isOpen() => '${root()}_is_open';
  String usage() => '${root()}_usage';
}

class ClipboardKeys {
  const ClipboardKeys();
  String root() => '${DevToolsStorageKeys.base}_clipboard';
  String hintAcknowledged() => '${root()}_hint_acknowledged';
}

class EnvKeys {
  const EnvKeys();
  String root() => '${DevToolsStorageKeys.base}_env';
  String modal() => '${root()}_modal';
  String currentEnv() => '${root()}_current';
  String overrides() => '${root()}_overrides';
}

class SentryKeys {
  const SentryKeys();
  String root() => '${DevToolsStorageKeys.base}_sentry';
  String modal() => '${root()}_modal';
  String filters() => '${root()}_filters';
  String preferences() => '${root()}_preferences';
}

class StorageKeys {
  const StorageKeys();
  String root() => '${DevToolsStorageKeys.base}_storage';
  String modal() => '${root()}_modal';
  String eventsModal() => '${root()}_events_modal';
  String filters() => '${root()}_filters';
  String eventFilters() => '${root()}_event_filters';
  String keyFilters() => '${root()}_key_filters';
  String pinnedKeys() => '${root()}_pinned_keys';
  String preferences() => '${root()}_preferences';
  String activeTab() => '${root()}_active_tab';
  String isMonitoring() => '${root()}_is_monitoring';
  String detailView() => '${root()}_detail_view';
  String diffViewerMode() => '${root()}_diff_viewer_mode';
}

class ReactQueryKeys {
  const ReactQueryKeys();
  String root() => '${DevToolsStorageKeys.base}_rq';
  String modal() => '${root()}_modal';
  String browserModal() => '${root()}_browser_modal';
  String mutationModal() => '${root()}_mutation_modal';
  String filters() => '${root()}_filters';
  String ignoredPatterns() => '${root()}_ignored_patterns';
  String includedPatterns() => '${root()}_included_patterns';
  String preferences() => '${root()}_preferences';
}

class NetworkKeys {
  const NetworkKeys();
  String root() => '${DevToolsStorageKeys.base}_network';
  String modal() => '${root()}_modal';
  String copyModal() => '${root()}_copy_modal';
  String filters() => '${root()}_filters';
  String ignoredDomains() => '${root()}_ignored_domains';
  String ignoredUrls() => '${root()}_ignored_urls';
  String preferences() => '${root()}_preferences';
  String copyOptions() => '${root()}_copy_options';
}

class RouteEventsKeys {
  const RouteEventsKeys();
  String root() => '${DevToolsStorageKeys.base}_route_events';
  String modal() => '${root()}_modal';
  String eventFilters() => '${root()}_event_filters';
  String activeTab() => '${root()}_active_tab';
  String isMonitoring() => '${root()}_is_monitoring';
  String detailView() => '${root()}_detail_view';
  String diffViewerMode() => '${root()}_diff_viewer_mode';
}

class HighlightUpdatesKeys {
  const HighlightUpdatesKeys();
  String root() => '${DevToolsStorageKeys.base}_highlight_updates';
  String modal() => '${root()}_modal';
  String isTracking() => '${root()}_is_tracking';
  String filters() => '${root()}_filters';
  String settings() => '${root()}_settings';
  String copySettings() => '${root()}_copy_settings';
}

class BenchmarkKeys {
  const BenchmarkKeys();
  String root() => '${DevToolsStorageKeys.base}_benchmark';
  String modal() => '${root()}_modal';
  String isRecording() => '${root()}_is_recording';
  String activeTab() => '${root()}_active_tab';
  String settings() => '${root()}_settings';
  String selectedReports() => '${root()}_selected_reports';
}

class EventsKeys {
  const EventsKeys();
  String root() => '${DevToolsStorageKeys.base}_events';
  String modal() => '${root()}_modal';
  String enabledSources() => '${root()}_enabled_sources';
  String isCapturing() => '${root()}_is_capturing';
  String copySettings() => '${root()}_copy_settings';
}

class ImagesKeys {
  const ImagesKeys();
  String root() => '${DevToolsStorageKeys.base}_images';
  String modal() => '${root()}_modal';
}

/// Centralized dev-tool storage-key registry. Access via the [devToolsStorageKeys]
/// singleton, e.g. `devToolsStorageKeys.network.modal()`.
class DevToolsStorageKeys {
  const DevToolsStorageKeys();

  /// Base prefix every dev-tool key starts with.
  static const String base = '@react_buoy';

  final BubbleKeys bubble = const BubbleKeys();
  final ModalKeys modal = const ModalKeys();
  final SettingsKeys settings = const SettingsKeys();
  final DialKeys dial = const DialKeys();
  final ClipboardKeys clipboard = const ClipboardKeys();
  final EnvKeys env = const EnvKeys();
  final SentryKeys sentry = const SentryKeys();
  final StorageKeys storage = const StorageKeys();
  final ReactQueryKeys reactQuery = const ReactQueryKeys();
  final NetworkKeys network = const NetworkKeys();
  final RouteEventsKeys routeEvents = const RouteEventsKeys();
  final HighlightUpdatesKeys highlightUpdates = const HighlightUpdatesKeys();
  final BenchmarkKeys benchmark = const BenchmarkKeys();
  final EventsKeys events = const EventsKeys();
  final ImagesKeys images = const ImagesKeys();
}

/// Singleton mirror of RN's `devToolsStorageKeys` object.
const devToolsStorageKeys = DevToolsStorageKeys();

/// Legacy dev-tool key prefixes from before the `@react_buoy` standardization.
const _legacyDevToolPatterns = [
  '@devtools',
  '@dev_tools_',
  '@modal_state_',
  '@react_query_browser_modal',
  '@react_query_modal',
  '@react_query_mutation_modal',
  '@sentry_logs_modal',
  '@floating_rn_better_dev_tools_',
  '@floating_tools_',
  '@apphost_',
  '@bubble_settings_',
  '@env_vars_modal',
  '@storage_modal',
  '@floating_@devtools_',
  'dev_last_route',
];

/// Whether [key] belongs to Buoy dev tools (RN `isDevToolsStorageKey`).
bool isDevToolsStorageKey(String key) {
  if (key.isEmpty) return false;
  if (key.startsWith(DevToolsStorageKeys.base)) return true;
  if (key.startsWith('buoy-')) return true;
  if (key.startsWith('@buoy')) return true;
  for (final pattern in _legacyDevToolPatterns) {
    if (key.startsWith(pattern)) return true;
  }
  return false;
}

/// Drop dev-tool keys from [keys] (RN `filterOutDevToolsKeys`).
List<String> filterOutDevToolsKeys(List<String> keys) =>
    [for (final k in keys) if (!isDevToolsStorageKey(k)) k];
