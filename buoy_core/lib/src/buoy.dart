import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import 'device_identity.dart';
import 'license/license_manager.dart';
import 'sync_client.dart';
import 'tool.dart';

/// Global Buoy runtime: tool registry + desktop-sync lifecycle.
///
/// Tool packages self-register via [registerTool] (usually from a one-line
/// `registerBuoyX()` call or the `buoy` umbrella widget), and [BuoyDevTools]
/// renders whatever is registered — so apps mount ONE widget and never touch
/// this class directly. [init] is idempotent and is normally invoked by
/// `BuoyDevTools` with its constructor props, mirroring the RN
/// `<FloatingDevTools externalSync={...} />` API.
class Buoy {
  Buoy._();

  static BuoySyncClient? _sync;
  static BuoyLicenseManager? _license;
  static final Map<String, ToolSyncAdapter> _adapters = {};
  static final List<BuoyTool> _tools = [];
  static final List<VoidCallback> _registryListeners = [];

  static bool get isInitialized => _sync != null;
  static BuoySyncClient? get sync => _sync;

  /// The validated licence: resolved tier + key. Created on first access so
  /// the settings modal can read it before (or without) [init]. Validated
  /// once per [init], cached 30 days, re-announced to the broker on every
  /// reconnect and change.
  static BuoyLicenseManager get license => _license ??= BuoyLicenseManager();

  /// Registered in-app tools, in registration order.
  static List<BuoyTool> get tools => List.unmodifiable(_tools);

  /// Notifies when [tools] changes (BuoyDevTools re-renders the dial).
  static VoidCallback addRegistryListener(VoidCallback listener) {
    _registryListeners.add(listener);
    return () => _registryListeners.remove(listener);
  }

  /// Register an in-app tool and (optionally) its desktop-sync adapter.
  /// Safe to call before or after [init]; duplicate ids are ignored.
  static void registerTool(BuoyTool tool, {ToolSyncAdapter? adapter}) {
    if (_tools.any((t) => t.id == tool.id)) return;
    _tools.add(tool);
    if (adapter != null) registerAdapter(tool.id, adapter);
    for (final listener in List.of(_registryListeners)) {
      listener();
    }
  }

  /// Register a sync adapter without an in-app tool (headless tools).
  static void registerAdapter(String toolId, ToolSyncAdapter adapter) {
    _adapters[toolId] = adapter;
    _sync?.addTool(toolId, adapter);
  }

  static bool _starting = false;

  /// Start the desktop sync connection. Idempotent — the first call wins.
  /// All parameters are optional; defaults mirror the RN zero-config path:
  /// leave `deviceId` unset and each install mints `flutter-app-ios-<8 hex>`
  /// once (see device_identity.dart), so a simulator and a phone on the same
  /// build are two devices in Buoy Desktop. If you pin an id it MUST be
  /// unique per device.
  ///
  /// The socket dials after one SharedPreferences read when the id is not
  /// pinned; [isInitialized] flips true at that point.
  static void init({
    String? deviceName,
    String? deviceId,
    String? socketUrl,
    String? licenseKey,
    Map<String, Object?> extraDeviceInfo = const {'framework': 'Flutter'},
  }) {
    if (_sync != null || _starting) return;
    _starting = true;
    final platform = Platform.isIOS ? 'ios' : 'android';
    void start(String installId) {
      final identity = buildDeviceIdentity(
        platform: platform,
        installId: installId,
        deviceName: deviceName,
        deviceId: deviceId,
      );
      final client = BuoySyncClient(
        deviceName: identity.deviceName,
        deviceId: identity.deviceId,
        platform: platform,
        socketUrl: socketUrl ?? 'http://localhost:$defaultBrokerPort',
        license: license.state,
        extraDeviceInfo: extraDeviceInfo,
        tools: _adapters,
      );
      _sync = client;
      _starting = false;
      client.connect();
      // Validation is async (a Keygen round-trip) and must never block
      // startup; the client announces `anonymous` now and the real tier when
      // it lands.
      unawaited(license.setLicenseKey(licenseKey));
    }

    if (deviceId != null) {
      start('');
      return;
    }
    unawaited(loadInstallId().then(start));
  }
}
