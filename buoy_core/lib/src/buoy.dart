import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

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
  static final Map<String, ToolSyncAdapter> _adapters = {};
  static final List<BuoyTool> _tools = [];
  static final List<VoidCallback> _registryListeners = [];

  static bool get isInitialized => _sync != null;
  static BuoySyncClient? get sync => _sync;

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

  /// Start the desktop sync connection. Idempotent — the first call wins.
  /// All parameters are optional; defaults mirror the RN zero-config path.
  static void init({
    String deviceName = 'Flutter App',
    String? deviceId,
    String? socketUrl,
    String? licenseKey,
    Map<String, Object?> extraDeviceInfo = const {'framework': 'Flutter'},
  }) {
    if (_sync != null) return;
    final client = BuoySyncClient(
      deviceName: deviceName,
      deviceId: deviceId ??
          deviceName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-'),
      platform: Platform.isIOS ? 'ios' : 'android',
      socketUrl: socketUrl ?? 'http://localhost:$defaultBrokerPort',
      licenseKey: licenseKey,
      extraDeviceInfo: extraDeviceInfo,
      tools: _adapters,
    );
    _sync = client;
    client.connect();
  }
}
