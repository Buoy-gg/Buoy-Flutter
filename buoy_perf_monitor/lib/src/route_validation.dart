/// Ports packages/perf-monitor/src/perf-monitor/utils/routeValidation.ts.
///
/// Route URL parsing, sitemap pattern matching, and per-case route resolution
/// shared by the bulk-paste parser, the automation runner, the navigation
/// wrapper, and the editor UI. All pure — no Flutter, no storage, no router.
///
/// Pattern syntax follows the RN/expo-router set (`[id]`, `[[opt]]`,
/// `[...rest]`, `(group)`) AND go_router's `:id` params, so a Flutter sitemap
/// entry like `/pokemon/:id` validates the concrete `/pokemon/25`.
library;

import 'perf_types.dart';

class ParsedRoute {
  const ParsedRoute({required this.pathname, required this.search});

  /// Pathname only — leading "/", no scheme/host, no search, no hash.
  final String pathname;

  /// "k=v&k=v" query string with no leading "?". Empty when no params.
  final String search;
}

final RegExp _schemeRe = RegExp(r'^https?:\/\/[^/]+', caseSensitive: false);
final RegExp _multiSlashRe = RegExp(r'\/+');
final RegExp _groupRe = RegExp(r'\/\([^/]+\)');

/// Strip scheme+host, drop the hash, split pathname from query. Returns null
/// when the input doesn't look like a route (no leading "/" once stripped).
ParsedRoute? parseRouteInput(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return null;

  final scheme = _schemeRe.firstMatch(s);
  if (scheme != null) s = s.substring(scheme.end);
  if (s.isEmpty) return null;

  final hashIdx = s.indexOf('#');
  if (hashIdx >= 0) s = s.substring(0, hashIdx);

  final qIdx = s.indexOf('?');
  var pathname = qIdx >= 0 ? s.substring(0, qIdx) : s;
  final search = qIdx >= 0 ? s.substring(qIdx + 1) : '';

  if (!pathname.startsWith('/')) return null;

  // Collapse "//" runs to a single slash but keep the leading slash.
  pathname = pathname.replaceAll(_multiSlashRe, '/');

  return ParsedRoute(pathname: pathname, search: search);
}

/// Tolerant trailing-slash + double-slash normalization. Also strips
/// "/(group)" segments — route groups are URL-invisible, so "/(tabs)/home"
/// must match the sitemap entry "/home".
String normalizePathname(String p) {
  if (p.isEmpty) return p;
  var out = p.replaceAll(_groupRe, '');
  out = out.replaceAll(_multiSlashRe, '/');
  if (out.length > 1 && out.endsWith('/')) out = out.substring(0, out.length - 1);
  if (out.isEmpty) out = '/';
  return out;
}

String _escapeRegex(String s) =>
    s.replaceAllMapped(RegExp(r'[.*+?^${}()|[\]\\]'), (m) => '\\${m[0]}');

/// Compile a sitemap pattern into an anchored regex.
///
/// Handles `[id]` (one segment), `[[opt]]` (optional segment), `[...rest]`
/// (catch-all), `(group)` (stripped) and go_router's `:id` / `:id(regex)`.
RegExp sitemapPatternToRegex(String pattern) {
  final stripped = pattern.replaceAll(_groupRe, '');

  final body = StringBuffer();
  var i = 0;
  while (i < stripped.length) {
    final ch = stripped[i];
    if (ch == '[') {
      // Greedy to the closing "]" so "[...rest]" stays one token.
      final close = stripped.indexOf(']', i);
      if (close < 0) {
        body.write(_escapeRegex(stripped.substring(i)));
        break;
      }
      final segment = stripped.substring(i, close + 1);
      i = close + 1;
      if (RegExp(r'^\[\[\.\.\..+\]\]$').hasMatch(segment)) {
        body.write('(?:.+)?');
      } else if (RegExp(r'^\[\.\.\..+\]$').hasMatch(segment)) {
        body.write('.+');
      } else if (RegExp(r'^\[\[.+\]\]$').hasMatch(segment)) {
        body.write('(?:[^/]+)?');
      } else {
        body.write('[^/]+');
      }
    } else if (ch == ':') {
      // go_router path param — consume to the next "/" (parenthesised custom
      // regexes are treated as an opaque one-segment match).
      var j = i + 1;
      var depth = 0;
      while (j < stripped.length) {
        final c = stripped[j];
        if (c == '(') depth++;
        if (c == ')') depth--;
        if (c == '/' && depth <= 0) break;
        j++;
      }
      final token = stripped.substring(i, j);
      i = j;
      body.write(token.contains('*') ? '.+' : '[^/]+');
    } else {
      body.write(_escapeRegex(ch));
      i++;
    }
  }

  return RegExp('^$body/?\$');
}

/// 'valid' | 'unknown' | 'skipped' (RN `RouteValidationStatus`).
typedef RouteValidationStatus = String;

/// Compare a concrete pathname against the app sitemap.
///
///  - `valid`   — exact or pattern match found.
///  - `unknown` — sitemap is non-empty and nothing matches.
///  - `skipped` — sitemap is empty (routes tool not wired) — don't flag.
RouteValidationStatus validateRouteAgainstSitemap(
  String pathname,
  List<String> sitemap,
) {
  if (sitemap.isEmpty) return 'skipped';
  final normalized = normalizePathname(pathname);
  // Fast path — exact match after normalization.
  for (final entry in sitemap) {
    if (normalizePathname(entry) == normalized) return 'valid';
  }
  // Slow path — compile only the entries that carry pattern tokens.
  for (final entry in sitemap) {
    if (!entry.contains('[') && !entry.contains('(') && !entry.contains(':')) {
      continue;
    }
    try {
      if (sitemapPatternToRegex(entry).hasMatch(normalized)) return 'valid';
    } catch (_) {
      // Skip malformed sitemap entries.
    }
  }
  return 'unknown';
}

/// Resolve a case's effective navigation target. Per-case `route` wins, the
/// batch-level default fills the gap. Returns "" when neither is set so
/// callers can hard-fail with a clear error.
String resolveCaseRoute(AutomationCase c, String targetRoute) {
  final own = c.route?.trim() ?? '';
  if (own.isNotEmpty) return own;
  return targetRoute.trim();
}

/// True when the observed route represents the same screen the caller asked
/// the runner to navigate to. Tolerates trailing slashes both ways and handles
/// a pattern expectation (`/users/[id]`, `/users/:id`) vs a concrete URL.
bool pathnameMatches(String observed, String expected) {
  final a = normalizePathname(observed);
  final b = normalizePathname(expected);
  if (a == b) return true;
  if (expected.contains('[') ||
      expected.contains('(') ||
      expected.contains(':')) {
    try {
      return sitemapPatternToRegex(expected).hasMatch(a);
    } catch (_) {
      return false;
    }
  }
  return false;
}
