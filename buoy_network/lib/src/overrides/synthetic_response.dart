/// The Dart half of packages/network/src/network/overrides/applyToXhr.ts —
/// fabricating an HTTP response that never touched the network.
///
/// RN had to reach into React Native's XMLHttpRequest and set private fields
/// (`_sent`, `_requestId`, `_responseType`) because its XHR is a plain JS object
/// whose internals are writable; four separate bugs came out of getting that
/// wrong. Dart needs none of it. `HttpClientRequest` and `HttpClientResponse`
/// are ordinary interfaces, and `network_capture.dart` already implements both
/// as wrappers — so a fabricated response is just one more implementation of
/// the same public contract. No private state, no feature detection.
///
/// ## Where each outcome is raised, and why it matters
///
/// Verified against dio 5.10.0 `lib/src/adapters/io_adapter.dart`:
///
/// - `httpClient.openUrl(...)` is awaited INSIDE a `try { … } on
///   SocketException` block. A SocketException raised there becomes
///   `DioExceptionType.connectionError`, or `connectionTimeout` when the
///   message contains "timed out". That is also where a REAL offline failure
///   surfaces, because dart:io connects during openUrl.
/// - `request.close()` is NOT inside that block — only `HttpException` is
///   caught there. A SocketException thrown from `close()` escapes to dio's
///   generic handler and arrives as `DioExceptionType.unknown`.
///
/// So a faked failure must be raised from `openUrl`; raised from `close()` it
/// would not look like a real one to any dio app. [failException] builds the
/// exception; `network_capture.dart` throws it at the right site.
///
/// Latency is the opposite: dio applies `receiveTimeout` to `request.close()`,
/// so delaying there makes "delay 10s" against a 5s receiveTimeout correctly
/// produce a receive timeout — a faithful slow-server simulation. Delaying at
/// openUrl would trip the *connect* timeout instead, which is the wrong failure.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;

import 'override_rule.dart';

/// The exception a [FailOutcome] raises, shaped so dio classifies it the way a
/// real failure would.
///
/// dio branches on the message text, so the wording is load-bearing: "timed
/// out" selects `connectionTimeout`, anything else `connectionError`. Apps on
/// package:http or raw HttpClient see a SocketException either way, which is
/// exactly what they'd see with no network.
SocketException failException(FailOutcome outcome, Uri url) {
  final message = switch (outcome.failKind) {
    OverrideFailKind.timeout => 'Connection timed out',
    OverrideFailKind.network => 'Network is unreachable',
  };
  return SocketException(
    message,
    osError: const OSError('Buoy override', 0),
    address: null,
    port: url.hasPort ? url.port : null,
  );
}

/// A response built from a rule instead of a socket.
class SyntheticHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  SyntheticHttpClientResponse(this.outcome, this.uri)
    : _bytes = utf8.encode(outcome.body),
      headers = SyntheticHttpHeaders(outcome.headers);

  final RespondOutcome outcome;
  final Uri uri;
  final List<int> _bytes;

  @override
  final HttpHeaders headers;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    // A single-subscription stream of one chunk, exactly like a small real
    // response. Empty bodies emit nothing and just close, so a 204 or an empty
    // 500 doesn't hand the app a zero-length chunk it has to special-case.
    final controller = StreamController<List<int>>();
    if (_bytes.isNotEmpty) controller.add(_bytes);
    controller.close();
    return controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  int get statusCode => outcome.status;

  @override
  String get reasonPhrase => outcome.statusText.isNotEmpty
      ? outcome.statusText
      : _defaultReason(outcome.status);

  @override
  int get contentLength => _bytes.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  bool get persistentConnection => false;

  @override
  bool get isRedirect => false;

  @override
  List<RedirectInfo> get redirects => const [];

  @override
  List<Cookie> get cookies => const [];

  @override
  X509Certificate? get certificate => null;

  @override
  HttpConnectionInfo? get connectionInfo => null;

  @override
  Future<HttpClientResponse> redirect([
    String? method,
    Uri? url,
    bool? followLoops,
  ]) => Future.error(
    const HttpException('Buoy override: synthesized responses never redirect'),
  );

  @override
  Future<Socket> detachSocket() => Future.error(
    const HttpException('Buoy override: synthesized responses have no socket'),
  );
}

/// The request that produces one. Never touches a real [HttpClient], so an
/// overridden request opens no socket at all — matching RN, where the override
/// path never calls the original `send`.
///
/// Body writes are captured (the tool still shows what the app tried to send)
/// and then dropped.
class SyntheticHttpClientRequest implements HttpClientRequest {
  SyntheticHttpClientRequest({
    required this.method,
    required this.uri,
    required this.outcome,
    required this.onBody,
  });

  @override
  final String method;

  @override
  final Uri uri;

  final RespondOutcome outcome;

  /// Handed the request body and the final headers at close time, so the
  /// capture layer can record the event exactly as it does for real requests.
  final Future<void> Function(List<int> body, HttpHeaders headers) onBody;

  @override
  final HttpHeaders headers = SyntheticHttpHeaders(const {});

  final BytesBuilder _body = BytesBuilder(copy: false);
  final Completer<HttpClientResponse> _done = Completer<HttpClientResponse>();
  bool _closed = false;
  Object? _abortError;

  @override
  Future<HttpClientResponse> close() async {
    if (_closed) return _done.future;
    _closed = true;
    await onBody(_body.takeBytes(), headers);
    // The delay lives here, not at openUrl — see the library doc: this is the
    // span dio measures with receiveTimeout, so a long delay produces a receive
    // timeout rather than a connect timeout.
    if (outcome.delayMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: outcome.delayMs));
    }
    // A caller that gave up mid-delay gets the abort, not a late response.
    // dio's receiveTimeout aborts and then throws its own error, so whichever
    // arrives first is the one the app sees — the same race a real slow
    // response runs.
    final aborted = _abortError;
    if (aborted != null) throw aborted;

    final response = SyntheticHttpClientResponse(outcome, uri);
    if (!_done.isCompleted) _done.complete(response);
    return response;
  }

  @override
  Future<HttpClientResponse> get done => _done.future;

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {
    _abortError = exception ?? const HttpException('Request aborted');
    if (_done.isCompleted) return;
    _done.completeError(_abortError!, stackTrace);
    // Nothing is required to await `done` — dart:io's own requests behave the
    // same way. Marking it handled keeps an abort from surfacing as an
    // unhandled zone error and failing whatever test happens to be running.
    _done.future.ignore();
  }

  // ---- IOSink ----
  @override
  Encoding encoding = utf8;

  @override
  void add(List<int> data) => _body.add(data);

  @override
  void write(Object? object) => _body.add(encoding.encode('$object'));

  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) =>
      write(objects.join(separator));

  @override
  void writeCharCode(int charCode) => write(String.fromCharCode(charCode));

  @override
  void writeln([Object? object = '']) => write('$object\n');

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      _body.add(chunk);
    }
  }

  @override
  Future<void> flush() async {}

  @override
  bool bufferOutput = true;

  @override
  int contentLength = -1;

  @override
  bool followRedirects = true;

  @override
  int maxRedirects = 5;

  @override
  bool persistentConnection = true;

  @override
  List<Cookie> get cookies => const [];

  @override
  HttpConnectionInfo? get connectionInfo => null;
}

/// A standalone [HttpHeaders].
///
/// `dart:io` declares HttpHeaders abstract and ships no public concrete
/// implementation, so a fabricated request/response has to bring its own.
/// Nothing clever — case-insensitive multi-value storage plus the typed
/// accessors the interface requires.
class SyntheticHttpHeaders implements HttpHeaders {
  SyntheticHttpHeaders(Map<String, String> initial) {
    initial.forEach((name, value) => set(name, value));
  }

  final Map<String, List<String>> _store = {};

  /// Names the caller asked to keep unfolded. Tracked because the interface
  /// requires the method; synthesized traffic never has multi-value headers
  /// where folding would be observable.
  final Set<String> _unfolded = {};

  String _key(String name) => name.toLowerCase();

  @override
  bool chunkedTransferEncoding = false;

  @override
  int contentLength = -1;

  @override
  bool persistentConnection = false;

  @override
  List<String>? operator [](String name) => _store[_key(name)];

  @override
  String? value(String name) {
    final values = _store[_key(name)];
    if (values == null || values.isEmpty) return null;
    if (values.length > 1) {
      throw HttpException('More than one value for header $name');
    }
    return values.first;
  }

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {
    _store.putIfAbsent(_key(name), () => []).add('$value');
  }

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _store[_key(name)] = ['$value'];
  }

  @override
  void remove(String name, Object value) {
    _store[_key(name)]?.remove('$value');
  }

  @override
  void removeAll(String name) => _store.remove(_key(name));

  @override
  void forEach(void Function(String name, List<String> values) action) {
    _store.forEach(action);
  }

  @override
  void noFolding(String name) => _unfolded.add(_key(name));

  @override
  void clear() {
    _store.clear();
    _unfolded.clear();
    contentLength = -1;
    chunkedTransferEncoding = false;
  }

  @override
  ContentType? get contentType {
    final raw = value(HttpHeaders.contentTypeHeader);
    if (raw == null) return null;
    try {
      return ContentType.parse(raw);
    } catch (_) {
      return null;
    }
  }

  @override
  set contentType(ContentType? type) {
    if (type == null) {
      removeAll(HttpHeaders.contentTypeHeader);
    } else {
      set(HttpHeaders.contentTypeHeader, type.toString());
    }
  }

  @override
  DateTime? get date => _dateHeader(HttpHeaders.dateHeader);
  @override
  set date(DateTime? value) => _setDateHeader(HttpHeaders.dateHeader, value);

  @override
  DateTime? get expires => _dateHeader(HttpHeaders.expiresHeader);
  @override
  set expires(DateTime? value) =>
      _setDateHeader(HttpHeaders.expiresHeader, value);

  @override
  DateTime? get ifModifiedSince => _dateHeader(HttpHeaders.ifModifiedSinceHeader);
  @override
  set ifModifiedSince(DateTime? value) =>
      _setDateHeader(HttpHeaders.ifModifiedSinceHeader, value);

  @override
  String? get host => value(HttpHeaders.hostHeader);
  @override
  set host(String? value) => value == null
      ? removeAll(HttpHeaders.hostHeader)
      : set(HttpHeaders.hostHeader, value);

  @override
  int? get port => null;
  @override
  set port(int? value) {}

  DateTime? _dateHeader(String name) {
    final raw = value(name);
    if (raw == null) return null;
    try {
      return HttpDate.parse(raw);
    } catch (_) {
      return null;
    }
  }

  void _setDateHeader(String name, DateTime? value) {
    if (value == null) {
      removeAll(name);
    } else {
      set(name, HttpDate.format(value.toUtc()));
    }
  }
}

/// Reason phrases for the statuses the rule editor offers, so a synthesized
/// response reads like a real one in logs and in the tool.
String _defaultReason(int status) => switch (status) {
  200 => 'OK',
  201 => 'Created',
  204 => 'No Content',
  301 => 'Moved Permanently',
  302 => 'Found',
  304 => 'Not Modified',
  400 => 'Bad Request',
  401 => 'Unauthorized',
  403 => 'Forbidden',
  404 => 'Not Found',
  408 => 'Request Timeout',
  409 => 'Conflict',
  418 => "I'm a teapot",
  422 => 'Unprocessable Entity',
  429 => 'Too Many Requests',
  500 => 'Internal Server Error',
  502 => 'Bad Gateway',
  503 => 'Service Unavailable',
  504 => 'Gateway Timeout',
  507 => 'Insufficient Storage',
  _ => 'Status $status',
};
