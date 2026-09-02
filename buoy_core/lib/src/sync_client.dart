import 'dart:async';
import 'dart:math';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show ValueListenable, ValueNotifier, debugPrint;
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'license/license_manager.dart';
import 'sync/crash_flush.dart';
import 'sync/wire_budget.dart';

/// Log prefix, matching the RN bridge's so desktop-side triage of a mixed
/// RN/Flutter fleet greps for one string.
const String _log = '[ExternalSync]';

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
  static String? _instanceId;

  BuoySyncClient({
    required this.deviceName,
    required this.deviceId,
    required this.platform,
    String socketUrl = 'http://localhost:$defaultBrokerPort',
    this.license,
    @Deprecated('Pass `license` (a BuoyLicenseManager.state) instead; a bare '
        'key is validated by an internal manager for compatibility.')
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

  /// The VALIDATED licence state (tier + key) this device announces to the
  /// broker on every (re)connect and whenever it changes. The MCP server's
  /// data/action tools are gated on the device's tier, so this must be the
  /// truth, not a claim — see FLUTTER_TIER_PORT.md.
  final ValueListenable<BuoyLicenseState>? license;

  /// Legacy: a bare key. Validated by a private [BuoyLicenseManager] on
  /// [connect] so it announces the real tier rather than `isPro: true`.
  final String? licenseKey;

  BuoyLicenseManager? _ownedLicense;
  ValueListenable<BuoyLicenseState>? _licenseSource;
  void Function()? _removeLicenseListener;
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

  /// Register a tool after construction (late registration from tool
  /// packages). Re-announces capabilities so the broker/dashboards learn the
  /// new tool and re-send its watch state.
  void addTool(String toolId, ToolSyncAdapter adapter) {
    tools[toolId] = adapter;
    if (isConnected) _sendCapabilities();
  }

  /// The crash-flush escape hatch, registered while this client is connected.
  ///
  /// Guarded exactly like the throttled path: a disconnected socket or an
  /// unwatched tool means there is nothing to push, and pushing anyway would
  /// build a snapshot in a customer's app for no observer. Cancels any pending
  /// throttle timer first so the crash entry isn't immediately re-sent.
  void _flushNow(String toolId) {
    if (!isConnected) return;
    if (!_unsubs.containsKey(toolId)) return; // nobody is watching this tool
    _timers.remove(toolId)?.cancel();
    _sendSnapshot(toolId);
  }

  void connect() {
    if (_socket != null) return;
    instance = this;
    registerToolFlusher(_flushNow);
    _attachLicense();

    final nonce =
        '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}-flutter';
    // Identifies this ISOLATE, not this socket: the broker uses it to tell
    // "one device, several sockets" from "two apps that pinned the same
    // deviceId" (flagged as a collision). RN parity: getInstanceId().
    _instanceId ??=
        '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}-'
        '${Random().nextInt(0x7fffffff).toRadixString(36)}';

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
            'instanceId': _instanceId,
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
    unregisterToolFlusher(_flushNow);
    _removeLicenseListener?.call();
    _removeLicenseListener = null;
    _ownedLicense?.dispose();
    _ownedLicense = null;
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

  /// Mirrors RN's `safeEmit`: socket.io encodes the payload synchronously, and
  /// an unencodable field throws from inside `emit`. Unguarded, that exception
  /// unwinds through whatever store notification triggered the snapshot — a
  /// devtool taking down app code. Report it and carry on instead.
  void _emit(String event, Map<String, Object?> message) {
    try {
      _socket?.emit(event, message);
    } catch (error) {
      debugPrint(
        '$_log Failed to emit "$event": $error. '
        'Payload must be JSON-serializable.',
      );
    }
  }

  /// Warn once per tool. This fires on a snapshot loop, so an unconditional
  /// warning would itself become the performance problem it reports.
  final Set<String> _warnedOversized = <String>{};

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

  /// Resolve which licence state to announce: the injected listenable, or a
  /// private manager validating the legacy bare key. Re-announces on change.
  void _attachLicense() {
    var source = license;
    // ignore: deprecated_member_use_from_same_package
    final legacyKey = licenseKey;
    if (source == null && legacyKey != null && legacyKey.isNotEmpty) {
      final owned = BuoyLicenseManager();
      _ownedLicense = owned;
      source = owned.state;
      unawaited(owned.setLicenseKey(legacyKey));
    }
    _licenseSource = source;
    if (source == null) return;
    void onChange() {
      if (isConnected) _sendLicense();
    }
    source.addListener(onChange);
    _removeLicenseListener = () => source!.removeListener(onChange);
  }

  /// Broker treats this event as the authoritative tier (the handshake value
  /// is ignored because real license validation is async). Sent on every
  /// (re)connect and whenever the tier resolves or changes, matching the RN
  /// client — including with no key at all, which announces `anonymous`.
  ///
  /// `isPro` stays for brokers older than the tier split; newer ones prefer
  /// `tier` (`tierFromLicensePayload` in @buoy-gg/sync-broker).
  void _sendLicense() {
    final state = _licenseSource?.value ?? const BuoyLicenseState();
    _emit('device-license', {
      'isPro': state.isPro,
      'tier': state.tier.name,
      'licenseKey': state.licenseKey ?? '',
    });
  }

  void _sendSnapshot(String toolId) {
    final tool = tools[toolId];
    if (tool == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    _lastEmit[toolId] = now;
    final payload = tool.getSnapshot();

    // The choke-point guard. Per-adapter caps get missed, and one adapter
    // shipping a raw state tree janks every app that opens a dashboard. An
    // oversized payload is DROPPED here rather than encoded: the panel goes
    // stale for that tool instead of the whole app stuttering.
    final walk = approxJsonSize(payload, maxSnapshotEmitBytes);
    if (walk.bytes > maxSnapshotEmitBytes) {
      if (_warnedOversized.add(toolId)) {
        debugPrint(
          '$_log "$toolId" snapshot ≈${(walk.bytes / 1e6).toStringAsFixed(1)}MB '
          'exceeds the ${maxSnapshotEmitBytes ~/ 1000000}MB sync budget — dropped '
          '(dashboard will be stale for this tool). The adapter should ship a '
          'wire-form snapshot (summaries + on-demand detail).',
        );
      }
      return;
    }

    _emit('devtool-sync', {
      'toolId': toolId,
      'persistentDeviceId': deviceId,
      'timestamp': now,
      'version': tool.version,
      'kind': 'snapshot',
      'payload': payload,
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

    // Action results get a larger budget than snapshots — a caller asking for
    // one event's body has explicitly opted into the cost — but not an
    // unlimited one. Over it, the caller gets an actionable error instead of a
    // silent freeze.
    if (result['ok'] == true) {
      final walk = approxJsonSize(result['result'], maxActionResultBytes);
      if (walk.bytes > maxActionResultBytes) {
        result['ok'] = false;
        result['result'] = null;
        result['error'] =
            'Result ≈${(walk.bytes / 1e6).toStringAsFixed(1)}MB exceeds the '
            '${maxActionResultBytes ~/ 1000000}MB sync budget. Narrow the request '
            '(e.g. includeValues:false, a limit, or a more specific action).';
      }
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
