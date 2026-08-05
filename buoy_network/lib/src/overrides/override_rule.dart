/// Ports packages/network/src/network/overrides/types.ts — the rule model for
/// response overrides.
///
/// Buoy's answer to Chrome DevTools' "Local Overrides", reshaped for mobile.
/// Two deliberate differences from Chrome explain the shape of this file:
///
/// 1. Chrome's rules ARE a directory tree — a body override is a file at
///    `<host>/<path>`, header overrides live in per-directory `.headers` files,
///    and its general→specific cascade exists only to hang off that nesting. We
///    have no filesystem, so rules are a flat ordered list and the FIRST enabled
///    match wins outright.
/// 2. Chrome CANNOT change a status code (`NetworkManager.ts` forces 200 the
///    moment a body is overridden) and has no latency or failure simulation.
///    Forcing a 500, a timeout or a 3s stall is the entire mobile use case, so
///    [status], [delayMs] and [OverrideRuleKind.fail] are the point.
///
/// Field names are RN's, character for character: they are persisted under the
/// same storage key and travel over the same sync protocol, so Buoy Desktop and
/// the MCP server read a Flutter rule and an RN rule with the same code.
library;

/// What a rule does when it matches.
///
/// - [respond] — synthesize a response. The request never leaves the device.
/// - [fail]    — synthesize a transport failure (offline / timeout). Also never
///               leaves the device.
/// - [delay]   — let the real request run, just late. Pure latency injection.
enum OverrideRuleKind {
  respond,
  fail,
  delay;

  static OverrideRuleKind fromJson(Object? raw) => switch (raw) {
    'fail' => OverrideRuleKind.fail,
    'delay' => OverrideRuleKind.delay,
    _ => OverrideRuleKind.respond,
  };

  String get wireName => name;
}

/// Which transport failure to fake.
///
/// On RN, `network` surfaces the way a real offline request does — fetch
/// rejects with `TypeError: Network request failed`. The Dart equivalent is a
/// `SocketException` raised from `HttpClient.openUrl`; see
/// `synthetic_response.dart` for why the raise site matters.
enum OverrideFailKind {
  network,
  timeout;

  static OverrideFailKind fromJson(Object? raw) =>
      raw == 'timeout' ? OverrideFailKind.timeout : OverrideFailKind.network;

  String get wireName => name;
}

/// Status codes a synthesized response may use.
///
/// The bound is inherited from RN rather than required by Dart: whatwg-fetch's
/// `Response` constructor throws outside [200, 599], so an RN rule set to 0
/// would crash the app's own fetch. Dart's `HttpClientResponse.statusCode` is
/// just an int and would tolerate anything — but a rule authored on the desktop
/// dashboard can be pushed to either runtime, so the same clamp applies here.
/// Use [OverrideRuleKind.fail] for connection-level failures.
const int statusMin = 200;
const int statusMax = 599;

/// Bounds the persisted list so a runaway UI can't fill storage.
const int maxOverrideRules = 50;

/// A single override rule.
class OverrideRule {
  OverrideRule({
    required this.id,
    required this.enabled,
    required this.urlPattern,
    required this.kind,
    this.name,
    this.methods,
    this.status,
    this.statusText,
    this.headers,
    this.body,
    this.failKind,
    this.delayMs,
    this.times,
    this.alternate = false,
    this.hits = 0,
    this.seen = 0,
    required this.createdAt,
    this.bodyOmitted = false,
  });

  final String id;
  bool enabled;

  /// Display label. Falls back to [urlPattern] when absent.
  String? name;

  /// Glob matched against the FULL request URL, query string included.
  ///
  /// `*` is the only wildcard and the match is anchored, exactly like Chrome's
  /// `applyTo` patterns — see `escapeRegex` in `match_rule.dart`.
  String urlPattern;

  /// Uppercase methods. Null or empty means "any method".
  List<String>? methods;

  OverrideRuleKind kind;

  /// `respond` only. Clamped to [statusMin]..[statusMax]. Defaults to 200.
  int? status;

  /// `respond` only. Cosmetic on RN (its XMLHttpRequest has no statusText
  /// field); on Dart it becomes the response's real `reasonPhrase`.
  String? statusText;

  /// `respond` only. A `content-type` is inferred from the body when omitted.
  Map<String, String>? headers;

  /// `respond` only. Raw text; JSON is just JSON-shaped text.
  String? body;

  /// `fail` only. Defaults to [OverrideFailKind.network].
  OverrideFailKind? failKind;

  /// Latency before the outcome, in ms. Applies to all three kinds.
  int? delayMs;

  /// Auto-disable after N matches; null means "forever".
  ///
  /// A throwaway rule ("make the next save fail") should retire itself. A rule
  /// that silently breaks the app tomorrow is this feature's main footgun.
  int? times;

  /// Apply to every OTHER matching request instead of every one.
  ///
  /// For the failure that isn't total: a flaky endpoint, a retry that should
  /// succeed on the second attempt, a token refresh that only fires after one
  /// 401. Those paths are where retry logic is usually wrong.
  bool alternate;

  /// Times this rule was APPLIED. Runtime-only counter; not persisted.
  int hits;

  /// Times this rule MATCHED, whether or not it applied. Runtime-only.
  ///
  /// Distinct from [hits] because [alternate] needs to advance its phase on the
  /// requests it deliberately lets through — counting only applications would
  /// leave it stuck in the off phase forever.
  int seen;

  final int createdAt;

  /// WIRE-ONLY: this rule's [body] was too big to ride the sync snapshot and
  /// was left out of it. Never persisted, never set on the device's own copy.
  ///
  /// A rule seeded from a real request holds that request's whole response —
  /// half a megabyte is normal — and the snapshot goes out several times a
  /// second while traffic flows. Remote surfaces fetch the real body with
  /// `getOverrideRuleBody` when the user actually opens the rule. The flag also
  /// protects the body on save: a dashboard editing a rule it never received
  /// the body for sends this back, and the device keeps what it has.
  bool bodyOmitted;

  OverrideRule copyWith({
    bool? enabled,
    Object? name = _unset,
    String? urlPattern,
    Object? methods = _unset,
    OverrideRuleKind? kind,
    Object? status = _unset,
    Object? statusText = _unset,
    Object? headers = _unset,
    Object? body = _unset,
    Object? failKind = _unset,
    Object? delayMs = _unset,
    Object? times = _unset,
    bool? alternate,
    int? hits,
    int? seen,
    bool? bodyOmitted,
  }) {
    return OverrideRule(
      id: id,
      enabled: enabled ?? this.enabled,
      name: name == _unset ? this.name : name as String?,
      urlPattern: urlPattern ?? this.urlPattern,
      methods: methods == _unset ? this.methods : methods as List<String>?,
      kind: kind ?? this.kind,
      status: status == _unset ? this.status : status as int?,
      statusText: statusText == _unset
          ? this.statusText
          : statusText as String?,
      headers: headers == _unset
          ? this.headers
          : headers as Map<String, String>?,
      body: body == _unset ? this.body : body as String?,
      failKind: failKind == _unset
          ? this.failKind
          : failKind as OverrideFailKind?,
      delayMs: delayMs == _unset ? this.delayMs : delayMs as int?,
      times: times == _unset ? this.times : times as int?,
      alternate: alternate ?? this.alternate,
      hits: hits ?? this.hits,
      seen: seen ?? this.seen,
      createdAt: createdAt,
      bodyOmitted: bodyOmitted ?? this.bodyOmitted,
    );
  }

  /// The wire/storage shape. Keys and omission rules match RN's rule objects so
  /// the desktop and MCP read both runtimes identically.
  ///
  /// [omitBody] drops an oversized body and flags it, for snapshots.
  Map<String, Object?> toJson({bool omitBody = false}) => {
    'id': id,
    'enabled': enabled,
    if (name != null) 'name': name,
    'urlPattern': urlPattern,
    if (methods != null && methods!.isNotEmpty) 'methods': methods,
    'kind': kind.wireName,
    if (status != null) 'status': status,
    if (statusText != null) 'statusText': statusText,
    if (headers != null && headers!.isNotEmpty) 'headers': headers,
    if (!omitBody && body != null) 'body': body,
    if (failKind != null) 'failKind': failKind!.wireName,
    if (delayMs != null) 'delayMs': delayMs,
    'times': times,
    'alternate': alternate,
    'hits': hits,
    'seen': seen,
    'createdAt': createdAt,
    if (omitBody) 'bodyOmitted': true,
  };

  /// Rehydrate from storage or the wire. Total by construction — a malformed
  /// entry becomes a sane rule rather than throwing, because this runs at app
  /// start and a parse failure would take the whole tool down with it.
  static OverrideRule? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final pattern = raw['urlPattern'];
    if (pattern is! String || pattern.trim().isEmpty) return null;
    final id = raw['id'];
    if (id is! String || id.isEmpty) return null;

    return OverrideRule(
      id: id,
      enabled: raw['enabled'] != false,
      name: raw['name'] is String ? raw['name'] as String : null,
      urlPattern: pattern.trim(),
      methods: _stringList(raw['methods']),
      kind: OverrideRuleKind.fromJson(raw['kind']),
      status: raw['status'] is num ? (raw['status'] as num).toInt() : null,
      statusText: raw['statusText'] is String
          ? raw['statusText'] as String
          : null,
      headers: _stringMap(raw['headers']),
      body: raw['body'] is String ? raw['body'] as String : null,
      failKind: raw['failKind'] == null
          ? null
          : OverrideFailKind.fromJson(raw['failKind']),
      delayMs: raw['delayMs'] is num ? (raw['delayMs'] as num).toInt() : null,
      times: raw['times'] is num ? (raw['times'] as num).toInt() : null,
      alternate: raw['alternate'] == true,
      hits: raw['hits'] is num ? (raw['hits'] as num).toInt() : 0,
      seen: raw['seen'] is num ? (raw['seen'] as num).toInt() : 0,
      createdAt: raw['createdAt'] is num
          ? (raw['createdAt'] as num).toInt()
          : DateTime.now().millisecondsSinceEpoch,
      bodyOmitted: raw['bodyOmitted'] == true,
    );
  }

  static List<String>? _stringList(Object? raw) {
    if (raw is! List) return null;
    final out = [
      for (final entry in raw)
        if (entry is String) entry.toUpperCase(),
    ];
    return out.isEmpty ? null : out;
  }

  static Map<String, String>? _stringMap(Object? raw) {
    if (raw is! Map) return null;
    final out = <String, String>{
      for (final entry in raw.entries)
        if (entry.value != null) entry.key.toString(): entry.value.toString(),
    };
    return out.isEmpty ? null : out;
  }
}

/// Sentinel so [OverrideRule.copyWith] can tell "not passed" from "set to null"
/// — every nullable field here is legitimately clearable.
const Object _unset = Object();

/// The instructions the interceptor performs, with every default, clamp and
/// inference already resolved. See `resolve_override.dart`.
sealed class OverrideOutcome {
  const OverrideOutcome({required this.rule, required this.delayMs});
  final OverrideRule rule;
  final int delayMs;
}

class RespondOutcome extends OverrideOutcome {
  const RespondOutcome({
    required super.rule,
    required super.delayMs,
    required this.status,
    required this.statusText,
    required this.headers,
    required this.body,
  });
  final int status;
  final String statusText;
  final Map<String, String> headers;
  final String body;
}

class FailOutcome extends OverrideOutcome {
  const FailOutcome({
    required super.rule,
    required super.delayMs,
    required this.failKind,
  });
  final OverrideFailKind failKind;
}

class DelayOutcome extends OverrideOutcome {
  const DelayOutcome({required super.rule, required super.delayMs});
}

/// The marker stamped onto a captured event so the UI can badge it. Mirrors
/// RN's `NetworkEvent.override`.
class NetworkOverrideMark {
  const NetworkOverrideMark({
    required this.ruleId,
    required this.kind,
    this.ruleName,
    this.delayMs,
  });

  final String ruleId;
  final OverrideRuleKind kind;
  final String? ruleName;
  final int? delayMs;

  Map<String, Object?> toJson() => {
    'ruleId': ruleId,
    'kind': kind.wireName,
    if (ruleName != null) 'ruleName': ruleName,
    if (delayMs != null && delayMs! > 0) 'delayMs': delayMs,
  };

  static NetworkOverrideMark forOutcome(OverrideOutcome outcome) =>
      NetworkOverrideMark(
        ruleId: outcome.rule.id,
        kind: outcome.rule.kind,
        ruleName: outcome.rule.name,
        delayMs: outcome.delayMs,
      );
}
