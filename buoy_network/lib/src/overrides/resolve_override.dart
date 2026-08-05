/// Ports packages/network/src/network/overrides/resolveOverride.ts — the whole
/// "is this request overridden" decision, in one pure function.
///
/// Pure on purpose: this is the piece worth unit-testing, and it runs inside
/// every HTTP request the app makes, so it must be cheap, total, and incapable
/// of throwing. Everything that could surprise (defaults, clamping,
/// content-type inference) is resolved HERE, so the interceptor never makes a
/// decision — it just performs the outcome.
library;

import 'dart:convert';

import 'match_rule.dart';
import 'override_rule.dart';

/// Traffic that must never be overridden, whatever the user's rules say.
///
/// A `*` pattern is a completely reasonable thing for a developer to write
/// ("break everything and see what the app does"), and without this it would
/// also break Buoy's own licence checks — turning "I tested an error state"
/// into "the dev tools stopped working and I don't know why". Broker and
/// app-registered noise is already excluded upstream by `_isIgnoredUrl` in
/// `network_capture.dart`.
final List<RegExp> _neverOverride = [
  RegExp(r'(^|\.)keygen\.sh', caseSensitive: false),
];

bool _isProtectedUrl(String url) =>
    _neverOverride.any((pattern) => pattern.hasMatch(url));

/// Guess a `content-type` when the rule didn't set one.
///
/// Getting this wrong is not cosmetic: dio's default transformer decodes by
/// content-type, so a JSON body labelled `text/plain` reaches the app as a
/// String where it expected a Map — and the override looks broken rather than
/// the header looking wrong.
String inferContentType(String body) {
  final trimmed = body.trim();
  if (trimmed.isEmpty) return 'text/plain; charset=utf-8';
  if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
    try {
      jsonDecode(trimmed);
      return 'application/json';
    } catch (_) {
      // Looks like JSON, isn't. Fall through — mislabelling it would be worse.
    }
  }
  return 'text/plain; charset=utf-8';
}

bool _hasHeader(Map<String, String> headers, String name) {
  final wanted = name.toLowerCase();
  return headers.keys.any((key) => key.toLowerCase() == wanted);
}

/// Normalize a matched rule into the exact instructions the interceptor needs.
OverrideOutcome toOutcome(OverrideRule rule) {
  final delayMs = (rule.delayMs ?? 0) < 0 ? 0 : (rule.delayMs ?? 0);

  switch (rule.kind) {
    case OverrideRuleKind.delay:
      return DelayOutcome(rule: rule, delayMs: delayMs);
    case OverrideRuleKind.fail:
      return FailOutcome(
        rule: rule,
        delayMs: delayMs,
        failKind: rule.failKind ?? OverrideFailKind.network,
      );
    case OverrideRuleKind.respond:
      final body = rule.body ?? '';
      final headers = <String, String>{...?rule.headers};
      if (!_hasHeader(headers, 'content-type')) {
        headers['content-type'] = inferContentType(body);
      }
      final raw = rule.status ?? 200;
      return RespondOutcome(
        rule: rule,
        delayMs: delayMs,
        // Clamped, not rejected. Dart would tolerate any int, but a rule
        // authored on the dashboard can be pushed to an RN app too, where
        // whatwg-fetch THROWS outside [200, 599] — so one clamp, both runtimes.
        status: raw < statusMin
            ? statusMin
            : (raw > statusMax ? statusMax : raw),
        statusText: rule.statusText ?? '',
        headers: headers,
        body: body,
      );
  }
}

/// A rule that has burned through its `times` budget no longer applies.
bool isSpent(OverrideRule rule) =>
    rule.times != null && rule.hits >= rule.times!;

/// Is this rule in a phase where it should actually fire?
///
/// Only `alternate` can answer no. It reads the CURRENT `seen` count, before
/// this match is recorded, so an untouched rule (`seen == 0`) lets the first
/// request through and overrides the second.
bool shouldApply(OverrideRule rule) {
  if (!rule.alternate) return true;
  return rule.seen % 2 == 1;
}

/// The first enabled rule whose pattern covers this request, phase ignored.
///
/// Separate from [resolveOverride] because an alternating rule has to advance
/// its phase on the requests it deliberately skips — the caller needs the rule
/// back even when the answer is "not this time".
OverrideRule? findMatchingRule(
  String url,
  String method,
  List<OverrideRule> rules,
) {
  if (rules.isEmpty) return null;
  // Chrome skips OPTIONS too (`NetworkPersistenceManager.ts:953`). A faked
  // preflight fails CORS in a way that looks nothing like the rule you wrote.
  if (method.toUpperCase() == 'OPTIONS') return null;
  if (_isProtectedUrl(url)) return null;

  for (final rule in rules) {
    if (!rule.enabled) continue;
    if (isSpent(rule)) continue;
    if (!ruleMatches(rule, url, method)) continue;
    return rule;
  }
  return null;
}

/// First ENABLED matching rule wins outright — no merging across rules.
///
/// Chrome cascades header overrides from the most general path segment to the
/// most specific, but that only exists because its rules are directory-nested
/// files. A flat list with a cascade would be a rule whose effect you cannot
/// see by reading it, which is the wrong trade on a phone screen.
OverrideOutcome? resolveOverride(
  String url,
  String method,
  List<OverrideRule> rules,
) {
  final rule = findMatchingRule(url, method, rules);
  if (rule == null || !shouldApply(rule)) return null;
  return toOutcome(rule);
}
