/// Ports packages/network/src/network/overrides/matchRule.ts — glob matching
/// for override rules, itself a faithful port of Chrome DevTools'.
///
/// Ported rather than reinvented on purpose: `*` globs are the syntax
/// developers already have in their fingers from Chrome's "Override headers"
/// `applyTo` field, and a pattern that behaves differently here than it does in
/// the browser — or differently on Flutter than on React Native — would be a
/// quiet trap.
///
/// Original: `NetworkPersistenceManager.ts:1051` + `StringUtilities.ts:9`.
library;

import 'override_rule.dart';

/// Chrome's escape set, character for character.
///
/// `*` is deliberately ABSENT — it survives escaping so it can become `.*`
/// below. Everything else that means something to a regex is neutered.
///
/// RN's string is `"[]{}()\\.^$+|-,?"`, which in a JS source file is the ten
/// characters `[ ] { } ( ) \ . ^ $` plus `+ | - , ?` — the backslash is escaped
/// there, so it is one character. Dart's raw string spells the same set.
const String _specialCharacters = r'[]{}()\.^$+|-,?';

/// Escape a glob into regex source: neutralize regex metacharacters, then
/// promote `*` to `.*`.
String escapeRegex(String pattern) {
  final buffer = StringBuffer();
  for (var i = 0; i < pattern.length; i++) {
    final char = pattern[i];
    if (_specialCharacters.contains(char)) buffer.write(r'\');
    buffer.write(char);
  }
  return buffer.toString().split('*').join('.*');
}

/// Compiled patterns, cached by source.
///
/// [resolveOverride] runs on EVERY request the app makes, against every rule.
/// Recompiling a RegExp per request per rule is pure waste in the one place
/// this feature is allowed to cost nothing.
final Map<String, RegExp> _compiled = {};

RegExp compilePattern(String pattern) {
  final cached = _compiled[pattern];
  if (cached != null) return cached;
  // Anchored, like Chrome's `^${...}$` — a pattern describes the whole URL, so
  // `pokeapi.co` matches nothing and `*pokeapi.co*` matches everything on that
  // host. Predictable beats clever; the rule editor writes full URLs for you.
  final regex = RegExp('^${escapeRegex(pattern)}\$');
  // Unbounded growth isn't possible in practice (patterns come from a capped
  // rule list), but a user editing a pattern character by character churns
  // entries, so keep the cache from becoming a leak.
  if (_compiled.length > 200) _compiled.clear();
  _compiled[pattern] = regex;
  return regex;
}

/// Does this rule apply to this request? Ignores `enabled` — callers check it.
bool ruleMatches(OverrideRule rule, String url, String method) {
  final methods = rule.methods;
  if (methods != null && methods.isNotEmpty) {
    if (!methods.contains(method.toUpperCase())) return false;
  }
  try {
    return compilePattern(rule.urlPattern).hasMatch(url);
  } catch (_) {
    // A pattern that can't compile matches nothing rather than throwing inside
    // the app's own request path. The rule editor validates; this is the
    // backstop.
    return false;
  }
}
