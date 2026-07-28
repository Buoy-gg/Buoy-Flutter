import 'package:flutter_test/flutter_test.dart';

import 'package:buoy_shared_ui/buoy_shared_ui.dart';

/// Parity tests against packages/shared/src/storage/devToolsStorageKeys.ts —
/// exact key strings must match so persisted state carries across frameworks.
void main() {
  group('devToolsStorageKeys — exact RN key strings', () {
    test('base prefix', () {
      expect(DevToolsStorageKeys.base, '@react_buoy');
    });

    test('bubble', () {
      expect(devToolsStorageKeys.bubble.root(), '@react_buoy_bubble');
      expect(devToolsStorageKeys.bubble.settings(),
          '@react_buoy_bubble_settings');
      expect(devToolsStorageKeys.bubble.userPreferences(),
          '@react_buoy_bubble_user_preferences');
      expect(devToolsStorageKeys.bubble.position(),
          '@react_buoy_bubble_position');
    });

    test('modal', () {
      expect(devToolsStorageKeys.modal.state(), '@react_buoy_modal_state');
      expect(devToolsStorageKeys.modal.dimensions(),
          '@react_buoy_modal_dimensions');
    });

    test('network', () {
      expect(devToolsStorageKeys.network.root(), '@react_buoy_network');
      expect(devToolsStorageKeys.network.modal(), '@react_buoy_network_modal');
      expect(devToolsStorageKeys.network.copyModal(),
          '@react_buoy_network_copy_modal');
      expect(devToolsStorageKeys.network.ignoredDomains(),
          '@react_buoy_network_ignored_domains');
      expect(devToolsStorageKeys.network.copyOptions(),
          '@react_buoy_network_copy_options');
    });

    test('events', () {
      expect(devToolsStorageKeys.events.root(), '@react_buoy_events');
      expect(devToolsStorageKeys.events.enabledSources(),
          '@react_buoy_events_enabled_sources');
      expect(devToolsStorageKeys.events.isCapturing(),
          '@react_buoy_events_is_capturing');
      expect(devToolsStorageKeys.events.copySettings(),
          '@react_buoy_events_copy_settings');
    });

    test('reactQuery uses the _rq root', () {
      expect(devToolsStorageKeys.reactQuery.root(), '@react_buoy_rq');
      expect(devToolsStorageKeys.reactQuery.ignoredPatterns(),
          '@react_buoy_rq_ignored_patterns');
    });

    test('storage detail/diff keys', () {
      expect(devToolsStorageKeys.storage.detailView(),
          '@react_buoy_storage_detail_view');
      expect(devToolsStorageKeys.storage.diffViewerMode(),
          '@react_buoy_storage_diff_viewer_mode');
    });

    test('settings global + benchmark selectedReports', () {
      expect(devToolsStorageKeys.settings.global(),
          '@react_buoy_settings_global');
      expect(devToolsStorageKeys.benchmark.selectedReports(),
          '@react_buoy_benchmark_selected_reports');
    });
  });

  group('isDevToolsStorageKey', () {
    test('matches @react_buoy prefix', () {
      expect(isDevToolsStorageKey('@react_buoy_network_modal'), isTrue);
    });
    test('matches buoy- and @buoy prefixes', () {
      expect(isDevToolsStorageKey('buoy-modal-state'), isTrue);
      expect(isDevToolsStorageKey('@buoy/impersonate'), isTrue);
    });
    test('matches legacy patterns', () {
      expect(isDevToolsStorageKey('@storage_modal'), isTrue);
      expect(isDevToolsStorageKey('dev_last_route'), isTrue);
    });
    test('rejects empty and app keys', () {
      expect(isDevToolsStorageKey(''), isFalse);
      expect(isDevToolsStorageKey('user_profile'), isFalse);
      expect(isDevToolsStorageKey('@my_app_token'), isFalse);
    });
    test('filterOutDevToolsKeys keeps only app keys', () {
      final out = filterOutDevToolsKeys([
        '@react_buoy_network_modal',
        'user_profile',
        'buoy-license',
        'cart_items',
      ]);
      expect(out, ['user_profile', 'cart_items']);
    });
  });
}
