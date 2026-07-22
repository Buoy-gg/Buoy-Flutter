import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;

import 'package:dio/dio.dart';

import 'package:buoy_core/buoy_core.dart';

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

const int _maxCapturedBody = 2 * 1024 * 1024;
const int _maxEvents = 500;

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

  Map<String, Object?> toJson({bool stripLargeBodies = false}) {
    final uri = Uri.tryParse(url);
    final stripRequest =
        stripLargeBodies &&
        requestData != null &&
        (requestSize ?? 0) > snapshotBodyInlineLimit;
    final stripResponse =
        stripLargeBodies &&
        responseData != null &&
        (responseSize ?? 0) > snapshotBodyInlineLimit;
    return {
      'id': id,
      'method': method,
      'url': url,
      if (status != null) 'status': status,
      if (statusText != null) 'statusText': statusText,
      'requestHeaders': requestHeaders,
      'responseHeaders': responseHeaders,
      if (!stripRequest && requestData != null) 'requestData': requestData,
      if (!stripResponse && responseData != null) 'responseData': responseData,
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
    };
  }
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

  String nextId() =>
      'flt-${DateTime.now().millisecondsSinceEpoch}-${_idCounter++}';

  void add(NetworkCaptureEvent event) {
    if (!capturing) return;
    _events.insert(0, event);
    if (_events.length > _maxEvents) {
      _events.removeRange(_maxEvents, _events.length);
    }
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
    notify();
  }

  NetworkCaptureEvent? byId(String id) {
    for (final event in _events) {
      if (event.id == id) return event;
    }
    return null;
  }

  List<Object?> snapshot() => [
    for (final e in _events) e.toJson(stripLargeBodies: true),
  ];

  /// Newest-first, for the in-app network tool.
  List<NetworkCaptureEvent> get events => List.unmodifiable(_events);

  void Function() subscribe(void Function() onChange) {
    _listeners.add(onChange);
    capturing = true;
    return () {
      _listeners.remove(onChange);
      if (_listeners.isEmpty) capturing = false;
    };
  }
}

/// The network tool's sync adapter — payload/version/actions match the RN
/// networkSyncAdapter (protocol v2) so Buoy Desktop needs zero changes.
final networkSyncAdapter = ToolSyncAdapter(
  version: 2,
  getSnapshot: () => NetworkEventStore.instance.snapshot(),
  subscribe: (onChange) => NetworkEventStore.instance.subscribe(onChange),
  actions: {
    'clearEvents': (_) {
      NetworkEventStore.instance.clear();
      return null;
    },
    'getEventBody': (params) {
      final id = params is Map ? params['id'] as String? : null;
      if (id == null) return null;
      final event = NetworkEventStore.instance.byId(id);
      if (event == null) return null;
      return {
        'requestData': event.requestData,
        'responseData': event.responseData,
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

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    final request = await _inner.openUrl(method, url);
    return _CapturingRequest(request);
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
  _CapturingRequest(this._inner)
    : _startMs = DateTime.now().millisecondsSinceEpoch;

  final HttpClientRequest _inner;
  final int _startMs;
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
      final response = await _inner.close();
      if (event == null) return response;
      return _finishWithResponse(event, response);
    } catch (error) {
      if (event != null) {
        event.error = error.toString();
        event.duration = DateTime.now().millisecondsSinceEpoch - _startMs;
        NetworkEventStore.instance.notify();
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
    event.status = response.statusCode;
    event.statusText = response.reasonPhrase;
    final headers = <String, String>{};
    response.headers.forEach((name, values) {
      headers[name] = values.join(', ');
    });
    event.responseHeaders = headers;
    // Full header value, matching the RN store (not just the mime type).
    event.responseType = response.headers.value('content-type');
    NetworkEventStore.instance.notify();
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
          NetworkEventStore.instance.notify();
        }
        _event.responseSize = _totalBytes;
        onData?.call(chunk);
      },
      onError: (Object error, StackTrace stackTrace) {
        _event.error = error.toString();
        _event.duration = DateTime.now().millisecondsSinceEpoch - _startMs;
        NetworkEventStore.instance.notify();
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
        _event.duration = DateTime.now().millisecondsSinceEpoch - _startMs;
        NetworkEventStore.instance.notify();
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
