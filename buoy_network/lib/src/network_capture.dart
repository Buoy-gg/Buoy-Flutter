import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

import 'package:buoy_core/buoy_core.dart';

import 'overrides/override_rule.dart';
import 'overrides/override_rules_store.dart';
// Cyclic with this file (presets builds a draft from a NetworkCaptureEvent).
// Dart resolves library cycles fine; the alternative is duplicating
// `patternForUrl`, which is exactly the logic that must not drift.
import 'overrides/presets.dart';
import 'network_tool/saved/network_saved_store.dart';
import 'overrides/resolve_override.dart';
import 'overrides/synthetic_response.dart';

/// Network capture for Dart/Flutter — the future buoy_network.
///
/// Everything is captured at the dart:io HttpClient level via
/// [BuoyHttpOverrides] (dio's IOHttpClientAdapter constructs HttpClient
/// through HttpOverrides too, so ONE hook covers dio, package:http, and raw
/// HttpClient with no double-capture). [BuoyDioAttribution] only stamps a
/// marker header so events can be attributed to dio; the wrapper strips it
/// before the request leaves the device.
const String _attributionHeader = 'x-buoy-flutter-client';

/// Mirrors @buoy-gg/network's SNAPSHOT_BODY_INLINE_LIMIT (protocol v2):
/// bodies above this are stripped from list snapshots and fetched on demand
/// via the getEventBody action.
const int snapshotBodyInlineLimit = 16 * 1024;

/// Total inline budget for one snapshot's event list, held under the emit
/// layer's 2MB so a snapshot is never DROPPED (a drop leaves the whole panel
/// stale). Per-field caps alone don't get there: 500 requests with 9KB
/// responses are all individually legal and still add up to ~4.7MB. Newest
/// events keep their bodies inline (that's what a developer is looking at);
/// once the budget is spent, older events degrade to metadata + fetch-on-demand.
///
/// 1.25 * 1024 * 1024, spelled as an int (Dart const double arithmetic).
const int snapshotEventsBudget = 1310720;

/// Header values above this are truncated on the snapshot. A single `cookie`
/// or `authorization` header can be kilobytes, and headers ride on EVERY event.
const int snapshotHeaderValueLimit = 64;

/// Should this body be withheld from the list snapshot?
///
/// Prefer the cached size proxy already on the event — it is free when it is
/// right. The walk is the fallback for when it is missing or WRONG (0 for a
/// fat or unencodable body), which is the case the size field alone could not
/// catch: a body the capture layer failed to measure rode every snapshot.
bool _shouldStripBody(Object? data, int? reportedSize) {
  if (data == null) return false;
  if ((reportedSize ?? 0) > snapshotBodyInlineLimit) return true;
  return isOverWireBudget(data, snapshotBodyInlineLimit);
}

/// Truncate oversized header values, preserving the key set so the dashboard
/// still shows WHICH headers were sent. Returns the original map (by identity)
/// when nothing needed capping, so callers can detect a change cheaply.
Map<String, String> _toWireHeaders(Map<String, String> headers) {
  Map<String, String>? slim;
  for (final entry in headers.entries) {
    if (entry.value.length <= snapshotHeaderValueLimit) continue;
    slim ??= Map<String, String>.of(headers);
    slim[entry.key] =
        '${entry.value.substring(0, snapshotHeaderValueLimit)}… '
        '[${entry.value.length - snapshotHeaderValueLimit} more]';
  }
  return slim ?? headers;
}

const int _maxCapturedBody = 2 * 1024 * 1024;
const int _maxEvents = 500;

/// Cap on requests held in the boot buffer before the first consumer
/// subscribes. Oldest are dropped first.
///
/// RN buffers RAW events, where a request and its response are two entries, so
/// its 200 is ~100 requests. Flutter buffers whole event objects (the same
/// instances the interceptor fills in), so 100 here is the same ~100 requests.
const int _bootBufferMax = 100;

/// URLs the capture layer skips entirely — Buoy's own broker socket plus any
/// app-registered noise. Mirrors the RN listener's ignoredUrls (which filters
/// Metro/dev-server traffic the same way). WebSocket upgrade requests are
/// always skipped (dart:io WebSocket.connect goes through HttpOverrides).
final List<RegExp> _ignoredUrlPatterns = [];

void addIgnoredCaptureUrl(Pattern hostOrPattern) {
  _ignoredUrlPatterns.add(
    hostOrPattern is RegExp
        ? hostOrPattern
        : RegExp(RegExp.escape(hostOrPattern.toString())),
  );
}

/// Buoy's own broker traffic is always ignored — resolved lazily from the
/// active sync client so zero-config apps never self-capture.
String? _brokerAuthority() {
  final url = Buoy.sync?.socketUrl;
  if (url == null) return null;
  return Uri.tryParse(url)?.authority;
}

bool _isIgnoredUrl(String url) {
  final broker = _brokerAuthority();
  if (broker != null && broker.isNotEmpty && url.contains(broker)) return true;
  return _ignoredUrlPatterns.any((pattern) => pattern.hasMatch(url));
}

/// Ports the RN `NetworkTimings` model.
///
/// Only TWO phases, on purpose. Queueing / DNS / TLS / request-send all happen
/// below the Dart layer with nothing to read them from. The design this came
/// from shows five, but derives the other three by multiplying the total by
/// fixed fractions — i.e. they are invented. Two real ones are worth more than
/// five where three are decoration.
class NetworkTimings {
  const NetworkTimings({required this.ttfb, required this.download});

  /// Request start → response headers available.
  ///
  /// NOTE when labelling this in UI: measured from Dart, so it includes
  /// everything before the headers land — queueing, DNS, TLS and sending the
  /// request — not just the server's think time. Chrome can separate those; we
  /// cannot, and implying otherwise would overstate the precision.
  final int ttfb;

  /// Response headers available → body fully read.
  final int download;

  Map<String, Object?> toJson() => {'ttfb': ttfb, 'download': download};
}

class NetworkCaptureEvent {
  NetworkCaptureEvent({
    required this.id,
    required this.method,
    required this.url,
    required this.timestamp,
    required this.requestClient,
    this.requestHeaders = const {},
  });

  final String id;
  final String method;
  final String url;
  final int timestamp;
  final String requestClient;
  Map<String, String> requestHeaders;
  Map<String, String> responseHeaders = const {};
  int? status;
  String? statusText;
  Object? requestData;
  Object? responseData;
  int? requestSize;
  int? responseSize;
  int? duration;
  String? error;
  String? responseType;
  String? operationName;
  Map<String, Object?>? graphqlVariables;

  /// Absent — not zeroed — when unmeasurable. See [NetworkTimings].
  NetworkTimings? timings;

  /// Milliseconds from request start to response headers, stamped the moment
  /// they land. Kept separate from [timings] because the download half isn't
  /// known until the body finishes.
  int? ttfbMs;

  /// Set when a response override produced this event instead of the network.
  /// Mirrors RN's `NetworkEvent.override`; the list badges it and pins it into
  /// the OVERRIDDEN section.
  NetworkOverrideMark? override;

  Map<String, Object?> toJson({
    bool stripLargeBodies = false,

    /// Force both bodies off the wire regardless of size — the metadata-only
    /// form used for the tail of the list once the snapshot budget is spent.
    bool metadataOnly = false,
  }) {
    final uri = Uri.tryParse(url);
    final stripRequest =
        (stripLargeBodies || metadataOnly) &&
        requestData != null &&
        (metadataOnly || _shouldStripBody(requestData, requestSize));
    final stripResponse =
        (stripLargeBodies || metadataOnly) &&
        responseData != null &&
        (metadataOnly || _shouldStripBody(responseData, responseSize));
    final wireRequestHeaders = stripLargeBodies || metadataOnly
        ? _toWireHeaders(requestHeaders)
        : requestHeaders;
    final wireResponseHeaders = stripLargeBodies || metadataOnly
        ? _toWireHeaders(responseHeaders)
        : responseHeaders;
    return {
      'id': id,
      'method': method,
      'url': url,
      if (status != null) 'status': status,
      if (statusText != null) 'statusText': statusText,
      'requestHeaders': wireRequestHeaders,
      'responseHeaders': wireResponseHeaders,
      if (!identical(wireRequestHeaders, requestHeaders) ||
          !identical(wireResponseHeaders, responseHeaders))
        'headersOmitted': true,
      if (!stripRequest && requestData != null) 'requestData': requestData,
      if (!stripResponse && responseData != null) 'responseData': responseData,
      // Sizes stay HONEST — a doctored size used to be the only signal, so a
      // withheld body was indistinguishable from an absent one. These explicit
      // flags are what tell the dashboard to fetch via `getEventBody`.
      if (stripRequest) 'requestBodyOmitted': true,
      if (stripResponse) 'responseBodyOmitted': true,
      if (requestSize != null) 'requestSize': requestSize,
      if (responseSize != null) 'responseSize': responseSize,
      'timestamp': timestamp,
      if (duration != null) 'duration': duration,
      if (error != null) 'error': error,
      if (uri != null) 'host': uri.host,
      if (uri != null) 'path': uri.path,
      if (uri != null && uri.query.isNotEmpty) 'query': uri.query,
      if (responseType != null) 'responseType': responseType,
      'requestClient': requestClient,
      if (operationName != null) 'operationName': operationName,
      if (graphqlVariables != null) 'graphqlVariables': graphqlVariables,
      if (timings != null) 'timings': timings!.toJson(),
      if (override != null) 'override': override!.toJson(),
    };
  }
}

/// One event's wire form plus its measured cost, so the budget pass is free.
class _WireEvent {
  const _WireEvent(this.json, this.bytes);
  final Map<String, Object?> json;
  final int bytes;
}

class NetworkEventStore {
  NetworkEventStore._();
  static final NetworkEventStore instance = NetworkEventStore._();

  final List<NetworkCaptureEvent> _events = [];
  final List<void Function()> _listeners = [];
  int _idCounter = 0;

  /// Capture is gated on a dashboard watching the tool (backpressure parity
  /// with the RN adapter: "subscribing starts the interceptor").
  bool capturing = false;

  /// How many consumers are holding capture open. `getCaptureStatus` reports
  /// this because it, not the interceptor, is what decides whether events are
  /// actually being recorded.
  int get subscriberCount => _listeners.length;

  String nextId() =>
      'flt-${DateTime.now().millisecondsSinceEpoch}-${_idCounter++}';

  /// Requests captured before the first consumer subscribed — see [add].
  ///
  /// Chronological (oldest first), unlike [_events].
  final List<NetworkCaptureEvent> _bootBuffer = [];

  void add(NetworkCaptureEvent event) {
    // Boot buffer. Capture normally starts with the first subscriber — the
    // Network modal opening, a dashboard watch, an MCP watch — which is long
    // after the app's startup requests (main() fetches, session bootstrap, the
    // first screen's loads) have already fired. Those used to be unrecoverable:
    // by the time anything subscribed, boot traffic was simply gone, and
    // `get_network_requests` answered "No requests captured" for a screen that
    // had visibly loaded data.
    //
    // The interceptor is already installed at registerBuoyNetwork() time, so
    // the events exist — they were just being dropped. Park them instead, and
    // flush on the first subscribe. If nothing EVER subscribes, nothing is ever
    // flushed: an explicit capture-off state never gains events it didn't ask
    // for, and the buffer stays bounded.
    if (!capturing) {
      _bootBuffer.add(event);
      if (_bootBuffer.length > _bootBufferMax) _bootBuffer.removeAt(0);
      return;
    }
    _events.insert(0, event);
    if (_events.length > _maxEvents) {
      _events.removeRange(_maxEvents, _events.length);
    }
    notify();
  }

  /// Move boot-buffered requests into the live list, oldest first so the
  /// newest ends up at the head (`_events` is newest-first).
  ///
  /// The buffered objects are the SAME instances the interceptor mutates with
  /// the response, so a request that completed while buffered arrives already
  /// filled in — no replay of raw request/response pairs is needed the way the
  /// RN port does it.
  void _flushBootBuffer() {
    if (_bootBuffer.isEmpty) return;
    for (final event in _bootBuffer) {
      _events.insert(0, event);
    }
    _bootBuffer.clear();
    if (_events.length > _maxEvents) {
      _events.removeRange(_maxEvents, _events.length);
    }
  }

  /// A tracked event changed — refresh its pinned snapshot, then notify.
  ///
  /// RN calls `networkSavedStore.syncFromLive` from the same place. Pinning a
  /// request that is still in flight would otherwise freeze it as "Pending"
  /// forever. The no-op path (nothing pinned) is a single empty-Set check.
  void update(NetworkCaptureEvent event) {
    NetworkSavedStore.instance.syncFromLive(event);
    notify();
  }

  /// Completed/error updates mutate the event in place; just notify.
  void notify() {
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }

  void clear() {
    _events.clear();
    // Drop boot-buffered requests too: "clear" has to mean the list stays
    // empty, not that a later subscribe resurrects pre-clear traffic.
    _bootBuffer.clear();
    notify();
  }

  NetworkCaptureEvent? byId(String id) {
    for (final event in _events) {
      if (event.id == id) return event;
    }
    return null;
  }

  /// Per-event wire caches. The store never mutates an event in place — a
  /// response/override update replaces the object — so keying on identity is
  /// correct and self-invalidating, and a completed request is converted once
  /// instead of on all ~5 snapshots per second for as long as it stays in the
  /// list. This is what keeps the guards off the hot path.
  static final Expando<_WireEvent> _wireCache = Expando<_WireEvent>(
    'buoyNetworkWire',
  );
  static final Expando<_WireEvent> _strippedCache = Expando<_WireEvent>(
    'buoyNetworkWireStripped',
  );

  static _WireEvent _wireFor(NetworkCaptureEvent event) {
    final cached = _wireCache[event];
    if (cached != null) return cached;
    _WireEvent entry;
    try {
      final json = event.toJson(stripLargeBodies: true);
      entry = _WireEvent(
        json,
        approxJsonSize(json, snapshotEventsBudget).bytes,
      );
    } catch (_) {
      // A body that blows up the size walk itself degrades to metadata rather
      // than letting getSnapshot throw and taking the whole panel down.
      final json = event.toJson(metadataOnly: true);
      var bytes = 1024;
      try {
        bytes = approxJsonSize(json, snapshotEventsBudget).bytes;
      } catch (_) {
        // keep the nominal estimate
      }
      entry = _WireEvent(json, bytes);
    }
    _wireCache[event] = entry;
    return entry;
  }

  static _WireEvent _strippedFor(NetworkCaptureEvent event) {
    final cached = _strippedCache[event];
    if (cached != null) return cached;
    final json = event.toJson(metadataOnly: true);
    final entry = _WireEvent(
      json,
      approxJsonSize(json, snapshotEventsBudget).bytes,
    );
    _strippedCache[event] = entry;
    return entry;
  }

  /// Spend the snapshot budget newest-first. `_events` is newest-first already,
  /// so this hands the developer full detail on what they are actually looking
  /// at and degrades the tail rather than dropping the whole panel.
  List<Object?> snapshot() {
    final out = <Object?>[];
    var spent = 0;
    for (final event in _events) {
      final full = _wireFor(event);
      if (spent + full.bytes <= snapshotEventsBudget) {
        out.add(full.json);
        spent += full.bytes;
      } else {
        final lean = _strippedFor(event);
        out.add(lean.json);
        spent += lean.bytes;
      }
    }
    return out;
  }

  /// Newest-first, for the in-app network tool.
  List<NetworkCaptureEvent> get events => List.unmodifiable(_events);

  void Function() subscribe(void Function() onChange) {
    _listeners.add(onChange);
    capturing = true;
    // Every new consumer — the Network modal opening, a dashboard watch
    // attaching — is a chance to notice and repair a clobbered interceptor
    // (RN `subscribeToEvents` does the same).
    ensureInterception();
    // Flush BEFORE the first consumer reads, so its very first snapshot already
    // carries boot traffic.
    _flushBootBuffer();
    return () {
      _listeners.remove(onChange);
      if (_listeners.isEmpty) capturing = false;
    };
  }

  /// Whether requests actually flow through capture right now: the installed
  /// override is (or wraps) ours. `HttpOverrides.global = …` gets re-assigned
  /// in the wild — a cert-bypass installed after login, a proxy toggle, a
  /// second dev tool — and after that every request bypasses capture while
  /// `registerBuoyNetwork` still believes it installed the hook.
  static bool get interceptionLive =>
      HttpOverrides.current is BuoyHttpOverrides;

  /// Re-assert the interceptor if something re-assigned `HttpOverrides.global`
  /// since capture started (port of RN `ensureInterception`). A no-op costing
  /// one `is` check when healthy; re-installs by WRAPPING the current override
  /// so whatever replaced us keeps working underneath. Only while this store
  /// is capturing — a store nobody is reading must not install anything.
  void ensureInterception() {
    if (!capturing || !_installRequested) return;
    if (interceptionLive) return;
    BuoyHttpOverrides.install();
  }

  /// Set by `BuoyHttpOverrides.install()`: the app asked for the hook, so
  /// repairing it later is honouring that request, not overriding
  /// `installHttpOverrides: false`.
  static bool _installRequested = false;
}

/// Live store first, then the saved store — a pin may hold the only remaining
/// copy of a request that has since been cleared or aged out.
NetworkCaptureEvent? _resolveEvent(String id) =>
    NetworkEventStore.instance.byId(id) ??
    NetworkSavedStore.instance.getEventById(id);

String? _readId(Object? params) =>
    params is Map && params['id'] is String ? params['id'] as String : null;

bool _readBool(Object? params, String key) =>
    params is Map && params[key] == true;

/// Turn a rule sent over the wire into one the store will accept.
///
/// Validated rather than trusted: these params arrive from the dashboard and
/// from MCP clients, and a malformed rule doesn't just fail — it gets PERSISTED
/// and re-applied to real traffic on every launch. Mirrors `readRuleDraft` in
/// the RN adapter, including its two prefill sources.
OverrideRule? _readRuleDraft(Object? params) {
  if (params is! Map) return null;
  final raw = params['rule'] is Map ? params['rule'] as Map : params;

  final store = OverrideRulesStore.instance;
  final id = raw['id'] is String ? raw['id'] as String : null;
  final existing = id == null
      ? null
      : store.rules.where((rule) => rule.id == id).firstOrNull;

  // `fromRequestId` builds the rule the way the UI's Override button does —
  // notably running the URL through `patternForUrl`, which drops the query to
  // `*`. Pasting an exact URL is the mistake that produces a rule sitting at 0
  // hits against a cache-busting client.
  OverrideRule? base;
  final fromRequestId = params['fromRequestId'];
  if (fromRequestId is String && fromRequestId.isNotEmpty) {
    final event = NetworkEventStore.instance.byId(fromRequestId);
    if (event == null) return null;
    base = draftFromEvent(event);
  }

  var pattern = raw['urlPattern'] is String
      ? (raw['urlPattern'] as String).trim()
      : '';
  if (pattern.isEmpty) pattern = base?.urlPattern ?? '';
  if (pattern.isEmpty) return null;

  // A remote surface editing a rule whose body was stripped from the snapshot
  // has nothing to send back for it. Without this the save would write a null
  // body and destroy the payload — the one field a rule exists for.
  final bodyOmitted = raw['bodyOmitted'] == true;
  final body = raw['body'] is String
      ? raw['body'] as String
      : (bodyOmitted ? existing?.body : base?.body);

  return OverrideRule(
    id: id ?? store.nextId(),
    enabled: raw['enabled'] != false,
    name: raw['name'] is String ? raw['name'] as String : base?.name,
    urlPattern: pattern,
    methods: raw['methods'] is List
        ? [
            for (final m in raw['methods'] as List)
              if (m is String) m.toUpperCase(),
          ]
        : base?.methods,
    kind: raw['kind'] is String
        ? OverrideRuleKind.fromJson(raw['kind'])
        : (base?.kind ?? OverrideRuleKind.respond),
    status: raw['status'] is num
        ? (raw['status'] as num).toInt()
        : base?.status,
    statusText: raw['statusText'] is String
        ? raw['statusText'] as String
        : base?.statusText,
    headers: raw['headers'] is Map
        ? {
            for (final e in (raw['headers'] as Map).entries)
              e.key.toString(): '${e.value}',
          }
        : base?.headers,
    // Objects are accepted and serialized so a caller can send JSON directly
    // instead of pre-stringifying it, which is the mistake everyone makes once.
    body:
        body ??
        (raw['body'] != null
            ? const JsonEncoder.withIndent('  ').convert(raw['body'])
            : null),
    failKind: raw['failKind'] == null
        ? null
        : OverrideFailKind.fromJson(raw['failKind']),
    delayMs: raw['delayMs'] is num ? (raw['delayMs'] as num).toInt() : null,
    times: raw['times'] is num ? (raw['times'] as num).toInt() : null,
    alternate: raw['alternate'] == true,
    createdAt: existing?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
  );
}

/// The network tool's sync adapter — payload/version/action names match the RN
/// `networkSyncAdapter` so Buoy Desktop and the MCP server need zero changes.
///
/// v4: the payload is an OBJECT — `{events, saved, overrides}`, matching RN
/// field for field. Pins can't ride as flags on the events: a pin outlives the
/// event that produced it (that is its whole purpose), so it has to be its own
/// list.
///
/// v5: honest request/responseSize + explicit request/responseBodyOmitted
/// flags, and a total snapshot budget so the list degrades instead of the whole
/// panel being dropped at the emit layer.
final networkSyncAdapter = ToolSyncAdapter(
  version: 5,
  getSnapshot: () {
    // Piggyback the interception health check on the watch loop: while a
    // dashboard/MCP watch is open this runs continuously, so a clobbered
    // HttpOverrides heals within one snapshot tick instead of staying dead
    // for the session (RN does the same).
    NetworkEventStore.instance.ensureInterception();
    return {
      'events': NetworkEventStore.instance.snapshot(),
      // Saved snapshots ride on EVERY snapshot, so they go through the same body
      // strip as events — a fat pin would otherwise land in the same 200ms loop
      // that the stripping exists to protect.
      'saved': [
        for (final record in NetworkSavedStore.instance.records)
          {
            ...record.toJson(),
            'event': record.event.toJson(stripLargeBodies: true),
          },
      ],
      // Rules live on the DEVICE — that's the only place they can run, since a
      // rule is applied inside the app's own HttpClient. Remote surfaces mirror
      // this and forward their edits back as actions.
      'overrides': OverrideRulesStore.instance.snapshotState(
        snapshotBodyInlineLimit,
      ),
    };
  },
  subscribe: (onChange) {
    final unsubscribeEvents = NetworkEventStore.instance.subscribe(onChange);
    // Pinning with no traffic in flight still has to reach the dashboard, and
    // so does editing a rule — both stores drive the snapshot.
    final unsubscribeSaved = NetworkSavedStore.instance.subscribe(onChange);
    final unsubscribeRules = OverrideRulesStore.instance.subscribe(onChange);
    return () {
      unsubscribeEvents();
      unsubscribeSaved();
      unsubscribeRules();
    };
  },
  actions: {
    'clearEvents': (_) {
      NetworkEventStore.instance.clear();
      return null;
    },
    'getEventBody': (params) {
      final id = _readId(params);
      if (id == null) return null;
      final event = _resolveEvent(id);
      if (event == null) return null;
      return {
        'requestData': event.requestData,
        'responseData': event.responseData,
      };
    },

    // ── Pinned + saved ───────────────────────────────────────────────────────

    /// Pin/unpin a request from the dashboard.
    'setPinned': (params) {
      final id = _readId(params);
      if (id == null) return null;
      final event = _resolveEvent(id);
      if (event == null) return null;
      final wanted = _readBool(params, 'pinned');
      // `flagsForEventId`, not `isPinned` — the id may be a `saved:<key>`
      // snapshot, which the live-id Sets deliberately don't carry.
      final current = flagsForEventId(
        NetworkSavedStore.instance.state,
        id,
      ).pinned;
      if (current == wanted) return {'ok': true};
      final result = NetworkSavedStore.instance.togglePin(event);
      return {'ok': result.succeeded, 'active': result.active};
    },

    /// Save/unsave a request from the dashboard.
    'setSaved': (params) {
      final id = _readId(params);
      if (id == null) return null;
      final event = _resolveEvent(id);
      if (event == null) return null;
      final wanted = _readBool(params, 'saved');
      final current = flagsForEventId(
        NetworkSavedStore.instance.state,
        id,
      ).saved;
      if (current == wanted) return {'ok': true};
      final result = NetworkSavedStore.instance.toggleSave(event);
      return {'ok': result.succeeded, 'active': result.active};
    },

    /// Drop one pinned/saved record by its stable key.
    'removeSavedRecord': (params) {
      final key = params is Map && params['key'] is String
          ? params['key'] as String
          : null;
      if (key == null) return null;
      NetworkSavedStore.instance.remove(key);
      return {'ok': true};
    },

    'clearSavedRequests': (_) {
      NetworkSavedStore.instance.clearSaved();
      return {'ok': true};
    },

    'clearPinnedRequests': (_) {
      NetworkSavedStore.instance.clearPinned();
      return {'ok': true};
    },

    // ── Response overrides ───────────────────────────────────────────────────

    /// Master switch — turns every rule off without losing any of them.
    'setOverridesEnabled': (params) {
      OverrideRulesStore.instance.setEnabled(_readBool(params, 'enabled'));
      return {'ok': true, 'enabled': OverrideRulesStore.instance.enabled};
    },

    /// Create a rule, or replace one by id.
    'upsertOverrideRule': (params) {
      final draft = _readRuleDraft(params);
      if (draft == null) {
        final wanted = params is Map ? params['fromRequestId'] : null;
        return {
          'ok': false,
          'error': wanted is String
              ? 'No captured request `$wanted` — it may have been cleared. '
                    'Send a urlPattern instead.'
              : 'A rule needs a non-empty urlPattern.',
        };
      }
      final rule = OverrideRulesStore.instance.upsertRule(draft);
      if (rule == null) {
        return {'ok': false, 'error': 'Override rule limit reached.'};
      }
      // A rule pushed from a remote surface is meant to take effect now;
      // leaving it dark under an OFF master switch reads as a silent failure.
      if (rule.enabled) OverrideRulesStore.instance.setEnabled(true);
      // A RECEIPT, not the rule: `fromRequestId` seeds the real response as the
      // body, so echoing the whole rule would send hundreds of KB back down the
      // socket for something no caller reads.
      return {
        'ok': true,
        'rule': {
          'id': rule.id,
          'urlPattern': rule.urlPattern,
          'enabled': rule.enabled,
          'kind': rule.kind.wireName,
          'status': rule.status,
          'bodySize': rule.body?.length ?? 0,
        },
      };
    },

    'setOverrideRuleEnabled': (params) {
      final id = _readId(params);
      if (id == null) return {'ok': false, 'error': 'Missing rule id.'};
      OverrideRulesStore.instance.setRuleEnabled(
        id,
        _readBool(params, 'enabled'),
      );
      return {'ok': true};
    },

    'deleteOverrideRule': (params) {
      final id = _readId(params);
      if (id == null) return {'ok': false, 'error': 'Missing rule id.'};
      OverrideRulesStore.instance.removeRule(id);
      return {'ok': true};
    },

    'clearOverrideRules': (_) {
      OverrideRulesStore.instance.clearRules();
      return {'ok': true};
    },

    /// Read the rules back — hit counts included, which the snapshot coalesces.
    'listOverrideRules': (_) => OverrideRulesStore.instance.state,

    /// The full body of one rule, for the surfaces the snapshot withheld it
    /// from. Fetched when the user opens the rule, the only moment it's needed.
    'getOverrideRuleBody': (params) {
      final id = _readId(params);
      if (id == null) return null;
      final rule = OverrideRulesStore.instance.rules
          .where((candidate) => candidate.id == id)
          .firstOrNull;
      if (rule == null) return null;
      return {'body': rule.body};
    },

    /// "Why is the list empty?" — the honest answer, instead of leaving the
    /// caller to guess. The plausible guesses ("interception is broken on this
    /// runtime") are usually wrong; the usual answer is that nothing is
    /// holding capture open.
    ///
    /// RECORDING is what the caller actually wants to know, and it is driven
    /// by the store's subscriber count — not by whether the interceptor is
    /// installed. Those genuinely differ: an enabled override rule pins the
    /// interceptor without anything writing to the event store.
    'getCaptureStatus': (_) {
      final subscribers = NetworkEventStore.instance.subscriberCount;
      return {
        'capturing': subscribers > 0,
        'subscribers': subscribers,
        'interceptorInstalled': HttpOverrides.current is BuoyHttpOverrides,
        // installed:true + live:false = something re-assigned
        // HttpOverrides.global over the interceptor (it self-heals on the
        // next subscribe/snapshot — see ensureInterception).
        'interceptorLive': NetworkEventStore.interceptionLive,
        'listenerCount': subscribers,
        'eventCount': NetworkEventStore.instance.events.length,
      };
    },

    /// Why isn't my rule firing? Reports the engine's own view of the world.
    'debugOverrides': (params) {
      final url =
          (params is Map && params['url'] is String
              ? params['url'] as String
              : null) ??
          'https://example.com/';
      final store = OverrideRulesStore.instance;
      return {
        'interceptorInstalled': HttpOverrides.current is BuoyHttpOverrides,
        'listenerCount': NetworkEventStore.instance.capturing ? 1 : 0,
        'engine': {
          'hooksInstalled': true,
          'devFlag': kDebugMode,
          'ruleCount': store.activeRules.length,
          'matches': findMatchingRule(url, 'GET', store.activeRules) != null,
        },
        'store': {
          'enabled': store.enabled,
          'ruleCount': store.rules.length,
          'rulesVisibleToEngine': store.activeRules.length,
        },
      };
    },
  },
);

/// Dio interceptor that stamps the attribution marker. Add to every Dio
/// instance; the HttpClient wrapper strips the header before send.
class BuoyDioAttribution extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers[_attributionHeader] = 'dio';
    handler.next(options);
  }
}

class BuoyHttpOverrides extends HttpOverrides {
  BuoyHttpOverrides({this.previous});

  /// Overrides that were installed before ours (cert-bypass and proxy
  /// overrides are common in the wild). We wrap their client instead of
  /// clobbering them — last-writer-wins otherwise.
  final HttpOverrides? previous;

  /// Install globally, chaining to any pre-existing override. Call before
  /// runApp so lazily-created shared clients (NetworkImage, WebSocket) are
  /// constructed through the wrapper.
  static void install() {
    NetworkEventStore._installRequested = true;
    final current = HttpOverrides.current;
    HttpOverrides.global = BuoyHttpOverrides(
      previous: current is BuoyHttpOverrides ? null : current,
    );
  }

  @override
  HttpClient createHttpClient(SecurityContext? context) => _CapturingHttpClient(
    previous?.createHttpClient(context) ?? super.createHttpClient(context),
  );

  @override
  String findProxyFromEnvironment(Uri url, Map<String, String>? environment) =>
      previous?.findProxyFromEnvironment(url, environment) ??
      super.findProxyFromEnvironment(url, environment);
}

class _CapturingHttpClient implements HttpClient {
  _CapturingHttpClient(this._inner);
  final HttpClient _inner;

  /// The one place a response override is decided.
  ///
  /// Resolved here, at connect time, rather than at `close()` — see
  /// `overrides/synthetic_response.dart` for the dio evidence. In short: dio
  /// only maps a `SocketException` to `connectionError`/`connectionTimeout`
  /// when it comes out of `openUrl`, which is also where a REAL offline failure
  /// surfaces. Raised from `close()` the same exception would arrive as
  /// `DioExceptionType.unknown` and no app's error handling would recognise it.
  OverrideOutcome? _resolveOutcome(String method, Uri url) {
    // A shipped app synthesizing 500s would be catastrophic. Same gate as RN's
    // `__DEV__` check, and the port briefing's rule 3.
    if (!kDebugMode) return null;
    final store = OverrideRulesStore.instance;
    final rules = store.activeRules;
    if (rules.isEmpty) return null;

    final href = url.toString();
    // Broker traffic and app-registered noise are off limits for the same
    // reason they're never captured — and this is what keeps a `*` catch-all
    // from severing Buoy's own socket.
    if (_isIgnoredUrl(href)) return null;

    final rule = findMatchingRule(href, method, rules);
    if (rule == null) return null;

    // The match is recorded even when the rule declines to apply: `alternate`
    // advances its phase on the requests it deliberately lets through.
    final applies = shouldApply(rule);
    store.recordMatch(rule.id);
    if (!applies) return null;
    store.recordHit(rule.id);
    return toOutcome(rule);
  }

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    final outcome = _resolveOutcome(method, url);

    if (outcome is FailOutcome) {
      // Recorded before the throw so the tool shows the request that failed.
      // Headers are absent by necessity, not oversight: callers set them on the
      // returned request, and there is no returned request — exactly the state
      // a real connection failure leaves behind.
      final event =
          NetworkCaptureEvent(
              id: NetworkEventStore.instance.nextId(),
              method: method,
              url: url.toString(),
              timestamp: DateTime.now().millisecondsSinceEpoch,
              requestClient: 'http',
            )
            ..override = NetworkOverrideMark.forOutcome(outcome)
            ..error = outcome.failKind == OverrideFailKind.timeout
                ? 'Network request timed out'
                : 'Network request failed'
            ..duration = outcome.delayMs;
      NetworkEventStore.instance.add(event);

      if (outcome.delayMs > 0) {
        await Future<void>.delayed(Duration(milliseconds: outcome.delayMs));
      }
      throw failException(outcome, url);
    }

    if (outcome is RespondOutcome) {
      // Never touches `_inner`, so an overridden request opens no socket at
      // all — matching RN, where the override path never calls the original
      // `send`.
      return SyntheticHttpClientRequest(
        method: method,
        uri: url,
        outcome: outcome,
        onBody: (body, headers) async =>
            _recordSynthetic(method, url, outcome, body, headers),
      );
    }

    final request = await _inner.openUrl(method, url);
    return _CapturingRequest(
      request,
      // `delay` alone lets the real request run, just late. The wait happens in
      // `close()`, which is the span dio measures with `receiveTimeout` — so a
      // long delay produces a receive timeout, the way a slow server would,
      // rather than a connect timeout.
      delayMs: outcome is DelayOutcome ? outcome.delayMs : 0,
      overrideMark: outcome == null
          ? null
          : NetworkOverrideMark.forOutcome(outcome),
    );
  }

  /// Record the event for a synthesized response, completed in one step —
  /// there is no network round trip to wait for.
  void _recordSynthetic(
    String method,
    Uri url,
    RespondOutcome outcome,
    List<int> body,
    HttpHeaders headers,
  ) {
    final store = NetworkEventStore.instance;
    final requestHeaders = <String, String>{};
    headers.forEach((name, values) => requestHeaders[name] = values.join(', '));

    final event =
        NetworkCaptureEvent(
            id: store.nextId(),
            method: method,
            url: url.toString(),
            timestamp: DateTime.now().millisecondsSinceEpoch,
            requestClient:
                requestHeaders['x-request-client'] ??
                requestHeaders[_attributionHeader] ??
                'http',
            requestHeaders: requestHeaders..remove(_attributionHeader),
          )
          ..override = NetworkOverrideMark.forOutcome(outcome)
          ..status = outcome.status
          ..statusText = outcome.statusText
          ..responseHeaders = outcome.headers
          ..responseType = outcome.headers['content-type']
          ..duration = outcome.delayMs;

    if (body.isNotEmpty) {
      event.requestSize = body.length;
      event.requestData = _decodeBody(body, requestHeaders['content-type']);
    }
    final bytes = utf8.encode(outcome.body);
    event.responseSize = bytes.length;
    event.responseData = _decodeBody(bytes, outcome.headers['content-type']);
    store.add(event);
  }

  @override
  Future<HttpClientRequest> open(
    String method,
    String host,
    int port,
    String path,
  ) => openUrl(method, Uri.parse('http://$host:$port$path'));

  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);
  @override
  Future<HttpClientRequest> get(String host, int port, String path) =>
      open('GET', host, port, path);
  @override
  Future<HttpClientRequest> postUrl(Uri url) => openUrl('POST', url);
  @override
  Future<HttpClientRequest> post(String host, int port, String path) =>
      open('POST', host, port, path);
  @override
  Future<HttpClientRequest> putUrl(Uri url) => openUrl('PUT', url);
  @override
  Future<HttpClientRequest> put(String host, int port, String path) =>
      open('PUT', host, port, path);
  @override
  Future<HttpClientRequest> deleteUrl(Uri url) => openUrl('DELETE', url);
  @override
  Future<HttpClientRequest> delete(String host, int port, String path) =>
      open('DELETE', host, port, path);
  @override
  Future<HttpClientRequest> patchUrl(Uri url) => openUrl('PATCH', url);
  @override
  Future<HttpClientRequest> patch(String host, int port, String path) =>
      open('PATCH', host, port, path);
  @override
  Future<HttpClientRequest> headUrl(Uri url) => openUrl('HEAD', url);
  @override
  Future<HttpClientRequest> head(String host, int port, String path) =>
      open('HEAD', host, port, path);

  @override
  Duration get idleTimeout => _inner.idleTimeout;
  @override
  set idleTimeout(Duration value) => _inner.idleTimeout = value;
  @override
  Duration? get connectionTimeout => _inner.connectionTimeout;
  @override
  set connectionTimeout(Duration? value) => _inner.connectionTimeout = value;
  @override
  int? get maxConnectionsPerHost => _inner.maxConnectionsPerHost;
  @override
  set maxConnectionsPerHost(int? value) => _inner.maxConnectionsPerHost = value;
  @override
  bool get autoUncompress => _inner.autoUncompress;
  @override
  set autoUncompress(bool value) => _inner.autoUncompress = value;
  @override
  String? get userAgent => _inner.userAgent;
  @override
  set userAgent(String? value) => _inner.userAgent = value;

  @override
  set authenticate(
    Future<bool> Function(Uri url, String scheme, String? realm)? f,
  ) => _inner.authenticate = f;
  @override
  void addCredentials(
    Uri url,
    String realm,
    HttpClientCredentials credentials,
  ) => _inner.addCredentials(url, realm, credentials);
  @override
  set authenticateProxy(
    Future<bool> Function(String host, int port, String scheme, String? realm)?
    f,
  ) => _inner.authenticateProxy = f;
  @override
  void addProxyCredentials(
    String host,
    int port,
    String realm,
    HttpClientCredentials credentials,
  ) => _inner.addProxyCredentials(host, port, realm, credentials);
  @override
  set connectionFactory(
    Future<ConnectionTask<Socket>> Function(
      Uri url,
      String? proxyHost,
      int? proxyPort,
    )?
    f,
  ) => _inner.connectionFactory = f;
  @override
  set findProxy(String Function(Uri url)? f) => _inner.findProxy = f;
  @override
  set badCertificateCallback(
    bool Function(X509Certificate cert, String host, int port)? callback,
  ) => _inner.badCertificateCallback = callback;
  @override
  set keyLog(Function(String line)? callback) => _inner.keyLog = callback;
  @override
  void close({bool force = false}) => _inner.close(force: force);
}

class _CapturingRequest implements HttpClientRequest {
  _CapturingRequest(this._inner, {this.delayMs = 0, this.overrideMark})
    : _startMs = DateTime.now().millisecondsSinceEpoch;

  final HttpClientRequest _inner;
  final int _startMs;

  /// Latency injected by a `delay` rule, awaited in [close].
  final int delayMs;

  /// Marks the event when a `delay` rule produced this request.
  final NetworkOverrideMark? overrideMark;
  final BytesBuilder _requestBody = BytesBuilder(copy: false);
  bool _built = false;
  NetworkCaptureEvent? _event;

  void _captureBytes(List<int> data) {
    if (_requestBody.length < _maxCapturedBody) {
      _requestBody.add(data);
    }
  }

  /// Builds and stores the event at send time (headers are final by then).
  /// Returns null — and captures nothing further — for ignored URLs and
  /// WebSocket upgrade requests (Buoy's own broker socket included).
  NetworkCaptureEvent? _ensureEvent() {
    if (_built) return _event;
    _built = true;

    final url = _inner.uri.toString();
    final isUpgrade = (_inner.headers.value('connection') ?? '')
        .toLowerCase()
        .contains('upgrade');
    if (isUpgrade || _isIgnoredUrl(url)) return null;

    final store = NetworkEventStore.instance;
    // Attribution order matches RN: explicit X-Request-Client header wins
    // (how apps tag graphql/grpc-web), then our internal dio marker, else raw.
    final explicitClient = _inner.headers.value('x-request-client');
    final marker = _inner.headers.value(_attributionHeader);
    // Strip our internal attribution marker so it never leaves the device —
    // but only when it's actually present (it's set solely by our own dio
    // interceptor). package:http, used by cached_network_image, pipes the
    // request body via addStream() BEFORE calling close(), which commits and
    // locks the dart:io request headers; an unconditional removeAll() then
    // throws "HTTP headers are not mutable" and fails every image load. Guard
    // the mutation so a committed-headers request can never crash here.
    if (marker != null) {
      try {
        _inner.headers.removeAll(_attributionHeader);
      } catch (_) {
        // Headers already committed (streamed body): leave the harmless
        // internal marker rather than throwing the whole request.
      }
    }
    final client = explicitClient ?? marker ?? 'http';

    final headers = <String, String>{};
    _inner.headers.forEach((name, values) {
      headers[name] = values.join(', ');
    });

    final event = NetworkCaptureEvent(
      id: store.nextId(),
      method: _inner.method,
      url: url,
      timestamp: _startMs,
      requestClient: client,
      requestHeaders: headers,
    );
    final bodyBytes = _requestBody.takeBytes();
    if (bodyBytes.isNotEmpty) {
      event.requestSize = bodyBytes.length;
      event.requestData = _decodeBody(
        bodyBytes,
        _inner.headers.contentType?.toString(),
      );
    }
    if (client == 'graphql') _extractGraphQL(event);
    event.override = overrideMark;
    store.add(event);
    _event = event;
    return event;
  }

  /// RN-parity GraphQL enrichment (extractOperationName + variables) — only
  /// for requests explicitly tagged via X-Request-Client: graphql.
  static void _extractGraphQL(NetworkCaptureEvent event) {
    final data = event.requestData;
    if (data is! Map) return;
    final explicit = data['operationName'];
    if (explicit is String && explicit.trim().isNotEmpty) {
      event.operationName = explicit.trim();
    } else {
      final query = data['query'];
      if (query is String) {
        event.operationName = RegExp(
          r'(?:query|mutation|subscription)\s+(\w+)',
        ).firstMatch(query)?.group(1);
      }
    }
    final vars = data['variables'];
    if (vars is Map) event.graphqlVariables = vars.cast<String, Object?>();
  }

  @override
  Future<HttpClientResponse> close() async {
    final event = _ensureEvent();
    try {
      // Injected latency lands here rather than at connect time: this is the
      // span dio measures with `receiveTimeout`, so "delay 10s" against a 5s
      // receiveTimeout correctly produces a receive timeout — a slow server,
      // not a slow connection.
      if (delayMs > 0) {
        await Future<void>.delayed(Duration(milliseconds: delayMs));
      }
      final response = await _inner.close();
      if (event == null) return response;
      return _finishWithResponse(event, response);
    } catch (error) {
      if (event != null) {
        event.error = error.toString();
        event.duration = DateTime.now().millisecondsSinceEpoch - _startMs;
        NetworkEventStore.instance.update(event);
      }
      rethrow;
    }
  }

  @override
  Future<HttpClientResponse> get done async {
    // `close()` is what application code awaits; done mirrors the inner
    // request's lifecycle without re-wrapping.
    final response = await _inner.done;
    return response;
  }

  HttpClientResponse _finishWithResponse(
    NetworkCaptureEvent event,
    HttpClientResponse response,
  ) {
    // Headers are here — that's the TTFB boundary. The download half is
    // filled in when the body finishes; see the response stream's onDone.
    event.ttfbMs = DateTime.now().millisecondsSinceEpoch - _startMs;
    event.status = response.statusCode;
    event.statusText = response.reasonPhrase;
    final headers = <String, String>{};
    response.headers.forEach((name, values) {
      headers[name] = values.join(', ');
    });
    event.responseHeaders = headers;
    // Full header value, matching the RN store (not just the mime type).
    event.responseType = response.headers.value('content-type');
    NetworkEventStore.instance.update(event);
    return _CapturingResponse(response, event, _startMs);
  }

  // ---- IOSink / body forwarding ----
  @override
  void add(List<int> data) {
    _captureBytes(data);
    _inner.add(data);
  }

  @override
  void write(Object? object) {
    final text = object?.toString() ?? '';
    _captureBytes(encoding.encode(text));
    _inner.write(object);
  }

  @override
  void writeAll(Iterable objects, [String separator = '']) {
    write(objects.join(separator));
  }

  @override
  void writeCharCode(int charCode) => write(String.fromCharCode(charCode));

  @override
  void writeln([Object? object = '']) => write('$object\n');

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _inner.addError(error, stackTrace);

  @override
  Future addStream(Stream<List<int>> stream) => _inner.addStream(
    stream.map((chunk) {
      _captureBytes(chunk);
      return chunk;
    }),
  );

  @override
  Future flush() => _inner.flush();

  @override
  void abort([Object? exception, StackTrace? stackTrace]) =>
      _inner.abort(exception, stackTrace);

  @override
  Encoding get encoding => _inner.encoding;
  @override
  set encoding(Encoding value) => _inner.encoding = value;
  @override
  bool get bufferOutput => _inner.bufferOutput;
  @override
  set bufferOutput(bool value) => _inner.bufferOutput = value;
  @override
  int get contentLength => _inner.contentLength;
  @override
  set contentLength(int value) => _inner.contentLength = value;
  @override
  bool get followRedirects => _inner.followRedirects;
  @override
  set followRedirects(bool value) => _inner.followRedirects = value;
  @override
  int get maxRedirects => _inner.maxRedirects;
  @override
  set maxRedirects(int value) => _inner.maxRedirects = value;
  @override
  bool get persistentConnection => _inner.persistentConnection;
  @override
  set persistentConnection(bool value) => _inner.persistentConnection = value;
  @override
  String get method => _inner.method;
  @override
  Uri get uri => _inner.uri;
  @override
  HttpHeaders get headers => _inner.headers;
  @override
  List<Cookie> get cookies => _inner.cookies;
  @override
  HttpConnectionInfo? get connectionInfo => _inner.connectionInfo;
}

class _CapturingResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _CapturingResponse(this._inner, this._event, this._startMs);

  final HttpClientResponse _inner;
  final NetworkCaptureEvent _event;
  final int _startMs;
  final BytesBuilder _body = BytesBuilder(copy: false);
  int _totalBytes = 0;
  bool _streamingMarked = false;

  bool get _isEventStream =>
      (_inner.headers.value('content-type') ?? '').contains('event-stream');

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _inner.listen(
      (chunk) {
        _totalBytes += chunk.length;
        if (_body.length < _maxCapturedBody) _body.add(chunk);
        // Long-lived streams (SSE) may never fire onDone; surface something
        // in the panel as soon as data flows so the request isn't a mystery.
        if (!_streamingMarked && _isEventStream) {
          _streamingMarked = true;
          _event.responseData = '[streaming response — body updates omitted]';
          NetworkEventStore.instance.update(_event);
        }
        _event.responseSize = _totalBytes;
        onData?.call(chunk);
      },
      onError: (Object error, StackTrace stackTrace) {
        _event.error = error.toString();
        _event.duration = DateTime.now().millisecondsSinceEpoch - _startMs;
        NetworkEventStore.instance.update(_event);
        if (onError is void Function(Object, StackTrace)) {
          onError(error, stackTrace);
        } else if (onError is void Function(Object)) {
          onError(error);
        }
      },
      onDone: () {
        final bytes = _body.takeBytes();
        _event.responseSize = _totalBytes;
        final truncated = _totalBytes > bytes.length;
        _event.responseData = _decodeBody(
          bytes,
          _inner.headers.contentType?.toString(),
        );
        if (truncated && _event.responseData is String) {
          _event.responseData =
              '${_event.responseData}'
              '\n[truncated: captured ${bytes.length} of $_totalBytes bytes]';
        }
        final duration = DateTime.now().millisecondsSinceEpoch - _startMs;
        _event.duration = duration;
        final ttfb = _event.ttfbMs;
        if (ttfb != null) {
          _event.timings = NetworkTimings(
            ttfb: ttfb,
            // Clamped: the two are sampled at different points, so a
            // sub-millisecond body can read as negative.
            download: duration - ttfb < 0 ? 0 : duration - ttfb,
          );
        }
        NetworkEventStore.instance.update(_event);
        onDone?.call();
      },
      cancelOnError: cancelOnError,
    );
  }

  @override
  int get statusCode => _inner.statusCode;
  @override
  String get reasonPhrase => _inner.reasonPhrase;
  @override
  int get contentLength => _inner.contentLength;
  @override
  HttpClientResponseCompressionState get compressionState =>
      _inner.compressionState;
  @override
  bool get persistentConnection => _inner.persistentConnection;
  @override
  bool get isRedirect => _inner.isRedirect;
  @override
  List<RedirectInfo> get redirects => _inner.redirects;
  @override
  HttpHeaders get headers => _inner.headers;
  @override
  List<Cookie> get cookies => _inner.cookies;
  @override
  X509Certificate? get certificate => _inner.certificate;
  @override
  HttpConnectionInfo? get connectionInfo => _inner.connectionInfo;
  @override
  Future<HttpClientResponse> redirect([
    String? method,
    Uri? url,
    bool? followLoops,
  ]) => _inner.redirect(method, url, followLoops);
  @override
  Future<Socket> detachSocket() => _inner.detachSocket();
}

/// Decode a captured body: JSON → structured object (the desktop renders it
/// as a tree), text → string, binary → placeholder string with the size.
Object? _decodeBody(List<int> bytes, String? contentType) {
  if (bytes.isEmpty) return null;
  final type = contentType?.toLowerCase() ?? '';
  final looksText =
      type.contains('json') ||
      type.startsWith('text/') ||
      type.contains('xml') ||
      type.contains('x-www-form-urlencoded');
  if (!looksText) return '[binary ${bytes.length} bytes: $contentType]';
  try {
    final text = utf8.decode(bytes);
    if (type.contains('json')) {
      try {
        return jsonDecode(text);
      } catch (_) {
        return text;
      }
    }
    return text;
  } catch (_) {
    return '[binary ${bytes.length} bytes]';
  }
}
