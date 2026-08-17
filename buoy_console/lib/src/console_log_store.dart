/// Ports packages/console/src/store/consoleLogStore.ts.
///
/// Keeps a bounded, CHRONOLOGICAL ring buffer of captured console entries,
/// modeled after Chrome DevTools' ConsoleMessage. Unlike the RN store (which
/// patches the global `console`), the Dart capture hooks live in
/// `console_capture.dart` and feed [record]; this file owns the buffer, the
/// subscriber/emit fan-out, and the preserve-log persistence.
///
/// NOTE: this is a standalone singleton, NOT a `BaseEventStore` — RN's console
/// store is likewise standalone, keeps entries oldest→newest (append to end,
/// drop oldest from front at cap), and is always-on (installed at app root, not
/// subscriber-gated). BaseEventStore is newest-first + subscriber-lifecycle,
/// which does not match, so it is deliberately not used.
library;

import 'dart:async';
import 'dart:convert';

import 'package:buoy_core/buoy_core.dart' show flushToolSyncNow;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'devtools/console_origin.dart';
import 'sanitize.dart';

/// DevTools log levels (Protocol.Log.LogEntryLevel).
typedef ConsoleLevel = String; // 'verbose' | 'info' | 'warning' | 'error'

/// Max entries retained before the oldest are dropped (RN MAX_ENTRIES).
const int kConsoleMaxEntries = 1000;

/// method → DevTools level (RN METHOD_LEVEL). Flutter only produces
/// log/debug/error, but the full map keeps filter counts + wire parity.
const Map<String, ConsoleLevel> _methodLevel = {
  'error': 'error',
  'assert': 'error',
  'warn': 'warning',
  'debug': 'verbose',
  'log': 'info',
  'info': 'info',
  'trace': 'info',
  'dir': 'info',
  'table': 'info',
  'group': 'info',
  'groupCollapsed': 'info',
  'groupEnd': 'info',
};

/// Methods whose call site we keep a stack for (RN STACK_METHODS).
const Set<String> _stackMethods = {'error', 'warn', 'trace', 'assert'};

/// method → DevTools level lookup (defaults to info).
ConsoleLevel levelForMethod(String method) => _methodLevel[method] ?? 'info';

/// One captured console entry — mirrors RN `ConsoleLogEntry`.
class ConsoleLogEntry {
  ConsoleLogEntry({
    required this.id,
    required this.method,
    required this.level,
    required this.args,
    required this.message,
    required this.timestamp,
    this.stack,
    this.origin,
    this.fatal,
  });

  /// Monotonic id, unique per captured entry.
  final int id;

  /// The console method that produced this entry (log/debug/error/…).
  final String method;

  /// DevTools level, derived from the method.
  final ConsoleLevel level;

  /// The raw arguments passed to the console method.
  final List<Object?> args;

  /// Pre-rendered single-line text (used for filtering + the simple list).
  final String message;

  /// Capture time in ms since epoch.
  final int timestamp;

  /// Captured stack (error/warn/trace only), app frames first.
  final String? stack;

  /// Where the log came from (function / call site).
  final LogOrigin? origin;

  /// True when this entry came from a global error handler (an uncaught error),
  /// not from a `print`/`debugPrint` call. The message carries a matching
  /// `[FATAL]` / `[UNCAUGHT]` prefix. MCP `get_triage` reads this field to lead
  /// with crashes.
  final bool? fatal;

  /// Serialized entry — the wire shape RN's adapter emits (args sanitized).
  Map<String, Object?> toJson() => {
        'id': id,
        'method': method,
        'level': level,
        'args': sanitizeArgs(args),
        'message': message,
        'timestamp': timestamp,
        if (stack != null) 'stack': stack,
        if (origin != null) 'origin': origin!.toJson(),
        if (fatal == true) 'fatal': true,
      };
}

/// Best-effort single-line serialization of one console argument (RN formatArg).
String _formatArg(Object? arg) {
  if (arg == null) return 'null';
  if (arg is String) return arg;
  if (arg is num || arg is bool) return arg.toString();
  if (arg is Map || arg is List) {
    try {
      return jsonEncode(arg);
    } catch (_) {
      return arg.toString();
    }
  }
  return arg.toString();
}

String _formatArgs(List<Object?> args) => args.map(_formatArg).join(' ');

/// Normalize a crash headline so the same error reported through two different
/// seams produces the same key. Flutter's `FlutterErrorDetails.exceptionAsString`
/// and a raw `error.toString()` of the same exception can differ by an already-
/// applied type prefix, which would defeat de-duplication entirely.
String _fatalHeadline(Object? error) {
  final body = _formatArg(error).trim();
  final name = error?.runtimeType.toString();
  if (name == null || name.isEmpty) return body;
  if (body.startsWith('$name: ')) return body;
  // Only prefix when it adds information — a String error is its own headline.
  return error is String ? body : '$name: $body';
}

/// Two independent seams report the same crash on some setups (a zone handler
/// and `PlatformDispatcher.onError` can both see it). Suppress a repeat of the
/// same headline within this window so a crash reads as ONE entry.
const Duration _fatalDedupeWindow = Duration(milliseconds: 2000);

/// Floor between opportunistic flushes, so an error storm can't flood the
/// socket.
const Duration _flushMinInterval = Duration(milliseconds: 150);

/// Drop this package's own frames from a raw stack so the displayed trace starts
/// at app code (RN cleanStack drops the Error header + interceptor frames).
String? _cleanStack(StackTrace? raw) {
  if (raw == null) return null;
  final lines = raw
      .toString()
      .split('\n')
      .where((l) => l.trim().isNotEmpty && !l.contains('buoy_console'))
      .toList();
  return lines.isEmpty ? null : lines.join('\n');
}

/// A change/clear/preserve listener callback.
typedef ConsoleListener = void Function();

/// The console capture store singleton.
class ConsoleLogStore {
  ConsoleLogStore._();
  static final ConsoleLogStore instance = ConsoleLogStore._();

  List<ConsoleLogEntry> _entries = <ConsoleLogEntry>[];
  int _nextId = 1;

  final Set<ConsoleListener> _listeners = {};
  final Set<ConsoleListener> _clearListeners = {};

  // ── Emit (frame-coalesced) ──────────────────────────────────────────────
  // Console traffic is bursty; coalesce a synchronous burst into one
  // notification (RN uses requestAnimationFrame; a guarded microtask coalesces
  // the same-turn burst in Dart).
  bool _emitScheduled = false;
  void _emit() {
    if (_emitScheduled) return;
    _emitScheduled = true;
    scheduleMicrotask(() {
      _emitScheduled = false;
      for (final listener in List.of(_listeners)) {
        listener();
      }
    });
  }

  // ── Capture ─────────────────────────────────────────────────────────────

  /// Record a captured console call. [rawStack] is the caller's stack (used for
  /// origin attribution + the error/warn trace). Called by the capture hooks.
  void record(
    String method,
    List<Object?> args, {
    StackTrace? rawStack,
    StackTrace? errorStack,
  }) {
    final origin = parseOrigin(rawStack);
    final keepStack = _stackMethods.contains(method);
    final entry = ConsoleLogEntry(
      id: _nextId++,
      method: method,
      level: levelForMethod(method),
      args: args,
      message: _formatArgs(args),
      timestamp: DateTime.now().millisecondsSinceEpoch,
      stack: keepStack ? _cleanStack(errorStack ?? rawStack) : null,
      origin: origin,
    );
    _append(entry);
    _emit();
    _scheduleSave();
    // Errors are the entries most likely to be the last thing an app ever logs,
    // so they get pushed to any dashboard immediately instead of waiting on the
    // throttle a dying app will never run. Rate-limited; ordinary logs still
    // ride the normal throttled path.
    if (entry.level == 'error') _flushConsoleSyncNow();
  }

  void _append(ConsoleLogEntry entry) {
    _entries = _entries.length >= kConsoleMaxEntries
        ? [..._entries.sublist(_entries.length - kConsoleMaxEntries + 1), entry]
        : [..._entries, entry];
  }

  /// Record an uncaught error from one of the global error handlers.
  ///
  /// [label] is the tag that leads BOTH the args and the pre-rendered message:
  /// the DevTools-style row renders from args, so this is what makes the tag
  /// visible in the UI — exactly like `print('[FATAL]', err)`.
  ///
  /// [fatal] marks the entry as coming from a global handler rather than a
  /// print call. `[RENDER ERROR]` deliberately does NOT set it: Flutter fires
  /// `FlutterError.onError` for a build error that `ErrorWidget` then recovers
  /// from, with no way here to tell that apart from a real crash — and claiming
  /// a healthy app crashed is worse than under-claiming. The stack, which is
  /// the useful part, is reported either way.
  void recordFatal(
    String label,
    Object? error, {
    StackTrace? stack,
    bool fatal = true,
  }) {
    final headline = _fatalHeadline(error);
    final duplicate = _isDuplicateFatal('$label $headline');
    final entry = ConsoleLogEntry(
      id: _nextId++,
      method: 'error',
      level: 'error',
      args: [label, error],
      message: '$label $headline',
      timestamp: DateTime.now().millisecondsSinceEpoch,
      // The error's OWN stack — the crash site, not this handler's call site.
      stack: _cleanStack(stack),
      fatal: fatal ? true : null,
    );
    _append(entry);
    _emit();
    _scheduleSave();
    // A repeat within the dedupe window is still RECORDED (two crashes are two
    // crashes); it just doesn't earn another forced push to the dashboard.
    if (!duplicate) _flushConsoleSyncNow(force: true);
  }

  String _lastFatalKey = '';
  int _lastFatalAt = 0;

  /// Has this crash already been recorded moments ago?
  ///
  /// Only ever used to suppress a duplicate PUSH to the dashboard — never to
  /// drop an entry. Two different widgets crashing with the same message inside
  /// the window are two crashes, and a tool whose pitch is "the app's last
  /// words" must not silently throw one away.
  bool _isDuplicateFatal(String key) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (key == _lastFatalKey &&
        now - _lastFatalAt < _fatalDedupeWindow.inMilliseconds) {
      return true;
    }
    _lastFatalKey = key;
    _lastFatalAt = now;
    return false;
  }

  int _lastFlushAt = 0;

  /// Clear the crash de-dupe and flush rate-limit state. The store is a
  /// singleton, so without this one test's fatal silently rate-limits the
  /// next one's push and the assertion fails for the wrong reason.
  @visibleForTesting
  void resetFlushStateForTest() {
    _lastFatalKey = '';
    _lastFatalAt = 0;
    _lastFlushAt = 0;
  }

  /// Push the console snapshot through the sync bridge NOW, bypassing its
  /// 200ms throttle — the throttle a crashing app never gets to run.
  void _flushConsoleSyncNow({bool force = false}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    // A fatal is the app's last word — it always goes out, rate limit or not.
    if (!force && now - _lastFlushAt < _flushMinInterval.inMilliseconds) return;
    _lastFlushAt = now;
    // Best-effort: a crash path must never crash.
    flushToolSyncNow('console');
  }

  // ── Subscription ────────────────────────────────────────────────────────

  /// Subscribe to changes. Returns an unsubscribe function.
  void Function() subscribe(ConsoleListener listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  /// Current snapshot (chronological, oldest → newest).
  List<ConsoleLogEntry> get entries => _entries;

  /// Clear all captured entries; fires clear listeners.
  void clearEntries() {
    for (final listener in List.of(_clearListeners)) {
      listener();
    }
    unawaited(_clearSavedBuffer());
    if (_entries.isEmpty) return;
    _entries = <ConsoleLogEntry>[];
    _emit();
  }

  /// Register a listener fired when [clearEntries] runs (dashboard forwards a
  /// clear to the device). Returns an unsubscribe function.
  void Function() onClear(ConsoleListener listener) {
    _clearListeners.add(listener);
    return () => _clearListeners.remove(listener);
  }

  // ── Remote-mirror mode (desktop dashboard) ────────────────────────────────

  /// Replace the whole entry list from a remote snapshot (desktop mirror mode).
  void replaceEntries(List<ConsoleLogEntry> next) {
    _entries = next.length > kConsoleMaxEntries
        ? next.sublist(next.length - kConsoleMaxEntries)
        : next;
    _emit();
  }

  // ── Preserve log (persist across reload) ──────────────────────────────────
  // Default OFF: the buffer is in-memory only, so a reload starts fresh. When
  // ON, the buffer is saved to storage (debounced) and restored on next launch.

  static const String _preserveKey = '@react_buoy_console_preserve';
  static const String _bufferKey = '@react_buoy_console_buffer';
  static const Duration _saveDebounce = Duration(milliseconds: 600);

  bool _preserveLog = false;
  bool _persistenceReady = false;
  final Set<ConsoleListener> _preserveListeners = {};
  Timer? _saveTimer;

  bool get preserveLog => _preserveLog;

  void _emitPreserve() {
    for (final listener in List.of(_preserveListeners)) {
      listener();
    }
  }

  /// Subscribe to preserve-log changes. Returns an unsubscribe function.
  void Function() subscribePreserveLog(ConsoleListener listener) {
    _preserveListeners.add(listener);
    return () => _preserveListeners.remove(listener);
  }

  void _scheduleSave() {
    if (!_preserveLog) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDebounce, _saveBuffer);
  }

  Future<void> _saveBuffer() async {
    _saveTimer = null;
    if (!_preserveLog) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final serializable = [for (final e in _entries) e.toJson()];
      await prefs.setString(_bufferKey, jsonEncode(serializable));
    } catch (_) {
      // Storage unavailable — preserve is best-effort.
    }
  }

  Future<void> _clearSavedBuffer() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_bufferKey);
    } catch (_) {
      // ignore
    }
  }

  /// Load the persisted preserve-log flag and, if enabled, restore the saved
  /// buffer; otherwise drop any stale buffer. Idempotent.
  Future<void> initPersistence() async {
    if (_persistenceReady) return;
    _persistenceReady = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _preserveLog = prefs.getString(_preserveKey) == 'true';
      _emitPreserve();

      if (!_preserveLog) {
        await prefs.remove(_bufferKey);
        return;
      }
      final raw = prefs.getString(_bufferKey);
      if (raw != null && raw.isNotEmpty) {
        final saved = jsonDecode(raw);
        if (saved is List && saved.isNotEmpty) {
          final restored = <ConsoleLogEntry>[];
          for (final item in saved) {
            if (item is Map) restored.add(_entryFromJson(item));
          }
          // Prepend restored entries before anything captured this session.
          _entries = [...restored, ..._entries];
          if (_entries.length > kConsoleMaxEntries) {
            _entries = _entries.sublist(_entries.length - kConsoleMaxEntries);
          }
          var maxId = _nextId - 1;
          for (final e in restored) {
            if (e.id > maxId) maxId = e.id;
          }
          _nextId = maxId + 1;
          _emit();
        }
      }
    } catch (_) {
      _preserveLog = false;
    }
  }

  /// Toggle preserve-log. Persists the flag; saves or drops the buffer.
  void setPreserveLog(bool next) {
    if (_preserveLog == next) return;
    _preserveLog = next;
    _emitPreserve();
    SharedPreferences.getInstance()
        .then((p) => p.setString(_preserveKey, next.toString()))
        .catchError((_) => false);
    if (next) {
      unawaited(_saveBuffer());
    } else {
      unawaited(_clearSavedBuffer());
    }
  }

  ConsoleLogEntry _entryFromJson(Map<Object?, Object?> json) {
    final originJson = json['origin'];
    return ConsoleLogEntry(
      id: (json['id'] as num?)?.toInt() ?? _nextId++,
      method: json['method'] as String? ?? 'log',
      level: json['level'] as String? ?? 'info',
      args: (json['args'] as List?)?.cast<Object?>() ?? const [],
      message: json['message'] as String? ?? '',
      timestamp: (json['timestamp'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
      stack: json['stack'] as String?,
      origin: originJson is Map
          ? LogOrigin(
              component: originJson['component'] as String?,
              functionName: originJson['functionName'] as String?,
              callSite: originJson['callSite'] as String?,
              file: originJson['file'] as String?,
              line: (originJson['line'] as num?)?.toInt(),
            )
          : null,
    );
  }

  /// Test hook: reset all state (buffer, ids, preserve flag).
  @visibleForTesting
  void resetForTest() {
    _entries = <ConsoleLogEntry>[];
    _nextId = 1;
    _preserveLog = false;
    _persistenceReady = false;
    _saveTimer?.cancel();
    _saveTimer = null;
    _emitScheduled = false;
  }
}
