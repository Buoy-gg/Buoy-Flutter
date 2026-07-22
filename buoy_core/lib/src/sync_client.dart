import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:socket_io_client/socket_io_client.dart' as io;

/// Connection state surfaced to the settings modal's DESKTOP SYNC card
/// (mirrors the RN useDesktopSyncStatus states).
enum BuoySyncState { connecting, connected, retrying }

class BuoySyncStatus {
  const BuoySyncStatus({
    required this.state,
    required this.targetUrl,
    this.lastError,
  });

  final BuoySyncState state;
  final String targetUrl;
  final String? lastError;
}

/// Dart port of Buoy's device-side sync bridge (@buoy-gg/external-sync).
/// Speaks sync protocol v1 to the Buoy Desktop broker: announces tool
/// capabilities on (re)connect, obeys the watch/backpressure contract, sends
/// throttled snapshots, and executes remote actions.
///
/// This is the seed of the future `buoy_flutter` package — it lives in the
/// example app until Phase 3 extracts it.
const int syncProtocolVersion = 1;
const int defaultBrokerPort = 42831;

typedef ToolAction = FutureOr<Object?> Function(Object? params);

/// Mirror of the RN ToolSyncAdapter contract. Payloads must be
/// JSON-serializable.
class ToolSyncAdapter {
  const ToolSyncAdapter({
    required this.version,
    required this.getSnapshot,
    required this.subscribe,
    this.actions = const {},
  });

  final int version;
  final Object? Function() getSnapshot;

  /// Called when a dashboard starts watching; returns an unsubscribe.
  final void Function() Function(void Function() onChange) subscribe;
  final Map<String, ToolAction> actions;
}

class BuoySyncClient {
  BuoySyncClient({
    required this.deviceName,
    required this.deviceId,
    required this.platform,
    String socketUrl = 'http://localhost:$defaultBrokerPort',
    this.licenseKey,
    this.tools = const {},
    this.throttle = const Duration(milliseconds: 200),
    Map<String, Object?> extraDeviceInfo = const {},
  }) : socketUrl = _platformSpecificUrl(socketUrl, platform),
       _extraDeviceInfo = Map.of(extraDeviceInfo);

  final String deviceName;
  final String deviceId;
  final String platform;
  final String socketUrl;

  /// When set, the device reports Pro status to the broker after each
  /// (re)connect — required for the MCP server's data/action tools, which are
  /// gated on the device's isPro flag.
  final String? licenseKey;
  final Map<String, ToolSyncAdapter> tools;
  final Duration throttle;
  final Map<String, Object?> _extraDeviceInfo;

  /// The Android emulator reaches the host machine at 10.0.2.2, not
  /// localhost (port of getPlatformSpecificURL in @buoy-gg/external-sync).
  static String _platformSpecificUrl(String url, String platform) {
    if (platform != 'android') return url;
    return url
        .replaceFirst('://localhost', '://10.0.2.2')
        .replaceFirst('://127.0.0.1', '://10.0.2.2');
  }

  io.Socket? _socket;
  final Map<String, void Function()> _unsubs = {};
  final Map<String, int> _lastEmit = {};
  final Map<String, Timer> _timers = {};

  /// The app's client, for status display (set on [connect]).
  static BuoySyncClient? instance;

  /// Live connection status for the settings modal.
  late final ValueNotifier<BuoySyncStatus> status = ValueNotifier(
    BuoySyncStatus(state: BuoySyncState.connecting, targetUrl: socketUrl),
  );

  void _setStatus(BuoySyncState state, [String? lastError]) {
    status.value = BuoySyncStatus(
      state: state,
      targetUrl: socketUrl,
      lastError: lastError,
    );
  }

  bool get isConnected => _socket?.connected ?? false;

  void connect() {
    if (_socket != null) return;
    instance = this;

    final nonce =
        '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}-flutter';

    final socket = io.io(
      socketUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setQuery({
            'deviceName': deviceName,
            'deviceId': deviceId,
            'platform': platform,
            'extraDeviceInfo': _jsonEncode(_extraDeviceInfo),
            'envVariables': '{}',
            'connectionNonce': nonce,
          })
          .enableReconnection()
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(5000)
          .build(),
    );
    _socket = socket;

    socket.onConnect((_) {
      _setStatus(BuoySyncState.connected);
      _sendCapabilities();
      _sendLicense();
    });
    socket.onDisconnect((_) => _setStatus(BuoySyncState.retrying));
    socket.onConnectError(
      (error) => _setStatus(BuoySyncState.retrying, error?.toString()),
    );
    socket.on('devtool-watch', (data) => _handleWatch(_asMap(data)));
    socket.on('request-devtool-state', (data) => _handleRequest(_asMap(data)));
    socket.on('devtool-action', (data) => _handleAction(_asMap(data)));
  }

  void dispose() {
    for (final unsub in _unsubs.values) {
      unsub();
    }
    _unsubs.clear();
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    _socket?.dispose();
    _socket = null;
  }

  bool _isForThisDevice(String? target) =>
      target == 'All' || target == deviceId;

  void _emit(String event, Map<String, Object?> message) {
    _socket?.emit(event, message);
  }

  void _sendCapabilities() {
    _emit('devtool-capabilities', {
      'persistentDeviceId': deviceId,
      'protocolVersion': syncProtocolVersion,
      'tools': [
        for (final entry in tools.entries)
          {
            'toolId': entry.key,
            'version': entry.value.version,
            'actions': entry.value.actions.keys.toList(),
          },
      ],
    });
  }

  /// Broker treats this event as the authoritative Pro status (the handshake
  /// value is ignored because real license validation is async). Re-sent on
  /// every reconnect, matching the RN client.
  void _sendLicense() {
    final key = licenseKey;
    if (key == null || key.isEmpty) return;
    _emit('device-license', {'isPro': true, 'licenseKey': key});
  }

  void _sendSnapshot(String toolId) {
    final tool = tools[toolId];
    if (tool == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    _lastEmit[toolId] = now;
    _emit('devtool-sync', {
      'toolId': toolId,
      'persistentDeviceId': deviceId,
      'timestamp': now,
      'version': tool.version,
      'kind': 'snapshot',
      'payload': tool.getSnapshot(),
    });
  }

  /// Leading + trailing throttle, matching the RN bridge: emit immediately
  /// outside the window, otherwise flush at the window's end so the dashboard
  /// converges to the latest state.
  void _scheduleSnapshot(String toolId) {
    if (_timers.containsKey(toolId)) return;
    final elapsed =
        DateTime.now().millisecondsSinceEpoch - (_lastEmit[toolId] ?? 0);
    if (elapsed >= throttle.inMilliseconds) {
      _sendSnapshot(toolId);
      return;
    }
    _timers[toolId] = Timer(
      Duration(milliseconds: throttle.inMilliseconds - elapsed),
      () {
        _timers.remove(toolId);
        _sendSnapshot(toolId);
      },
    );
  }

  void _handleWatch(Map<String, Object?>? message) {
    if (message == null) return;
    if (!_isForThisDevice(message['targetDeviceId'] as String?)) return;
    final toolId = message['toolId'] as String?;
    if (toolId == null) return;

    if (message['watching'] == true) {
      final tool = tools[toolId];
      if (tool == null || _unsubs.containsKey(toolId)) return;
      _unsubs[toolId] = tool.subscribe(() => _scheduleSnapshot(toolId));
      _sendSnapshot(toolId);
    } else {
      _unsubs.remove(toolId)?.call();
      _timers.remove(toolId)?.cancel();
    }
  }

  void _handleRequest(Map<String, Object?>? message) {
    if (message == null) return;
    if (!_isForThisDevice(message['targetDeviceId'] as String?)) return;
    final toolId = message['toolId'] as String?;
    if (toolId != null) _sendSnapshot(toolId);
  }

  Future<void> _handleAction(Map<String, Object?>? message) async {
    if (message == null) return;
    if (!_isForThisDevice(message['targetDeviceId'] as String?)) return;

    final requestId = message['requestId'];
    final toolId = message['toolId'] as String?;
    final action = message['action'] as String?;

    final result = <String, Object?>{
      'requestId': requestId,
      'toolId': toolId,
      'action': action,
      'persistentDeviceId': deviceId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'ok': false,
    };

    final tool = toolId == null ? null : tools[toolId];
    final fn = action == null ? null : tool?.actions[action];
    if (fn == null) {
      result['error'] = tool == null
          ? 'Unknown tool "$toolId"'
          : 'Unknown action "$action" on tool "$toolId"';
      _emit('devtool-action-result', result);
      return;
    }

    try {
      result['result'] = await fn(message['params']);
      result['ok'] = true;
    } catch (error) {
      result['error'] = error.toString();
    }
    result['timestamp'] = DateTime.now().millisecondsSinceEpoch;
    _emit('devtool-action-result', result);
  }
}

Map<String, Object?>? _asMap(dynamic data) {
  if (data is Map<String, Object?>) return data;
  if (data is Map) return data.cast<String, Object?>();
  return null;
}

String _jsonEncode(Object? value) {
  try {
    return jsonEncode(value);
  } catch (_) {
    return '{}';
  }
}
