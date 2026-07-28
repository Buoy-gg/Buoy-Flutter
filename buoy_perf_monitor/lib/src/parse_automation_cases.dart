/// Ports packages/perf-monitor/src/perf-monitor/utils/parseAutomationCases.ts.
///
/// Tolerant parser for bulk-pasted cases. Two input formats, sniffed by the
/// first non-whitespace character:
///
///   1. JSON array — `[{ "name": "v2", "params": { "renderer": "v2" } }]`
///   2. Line format — one case per line:
///        `baseline`
///        `v1: renderer=v1`
///        `v2 stress: renderer=v2, cards=5`
///        `/pokemon?renderer=v2&cards=5`   (URL style)
///      Empty lines and `#` / `//` comments are ignored.
///
/// Returns parsed cases (with fresh ids) plus per-line errors so the editor
/// can surface "lines 4, 7 didn't parse" without dropping the whole paste.
library;

import 'dart:convert';

import 'automation_settings.dart';
import 'compute_case_labels.dart';
import 'perf_types.dart';
import 'route_validation.dart';

class ParseCaseError {
  const ParseCaseError({
    required this.line,
    required this.reason,
    required this.raw,
  });
  final int line;
  final String reason;
  final String raw;
}

class ParseResult {
  const ParseResult({required this.cases, required this.errors});
  final List<AutomationCase> cases;
  final List<ParseCaseError> errors;
}

/// Serialize cases back into the JSON-array shape the parser round-trips
/// losslessly — the inverse of parsing. Powers the "Copy" button.
String serializeAutomationCases(List<AutomationCase> cases) {
  final out = [
    for (final c in cases)
      {
        'name': c.name,
        if (c.params.isNotEmpty) 'params': {...c.params},
        if (c.route != null && c.route!.isNotEmpty) 'route': c.route,
      },
  ];
  return const JsonEncoder.withIndent('  ').convert(out);
}

class ImportableCases {
  const ImportableCases({required this.importable, required this.droppedUnknown});
  final List<AutomationCase> importable;
  final int droppedUnknown;
}

/// Apply the sitemap gate to a parsed case list — the shared core behind both
/// the real import and the clipboard-preview count, so the button's "Paste N
/// cases" promise always matches what actually gets imported.
///
/// A case is dropped when it has a resolved route AND that route is confirmed
/// missing from a loaded sitemap ("unknown"). Cases with no resolved route and
/// every case when no sitemap is loaded ("skipped") pass through.
ImportableCases filterImportableCases(
  List<AutomationCase> cases,
  String targetRoute,
  List<String> sitemap,
) {
  final importable = <AutomationCase>[];
  var droppedUnknown = 0;
  for (final c in cases) {
    final resolved = resolveCaseRoute(c, targetRoute);
    if (resolved.isNotEmpty &&
        validateRouteAgainstSitemap(resolved, sitemap) == 'unknown') {
      droppedUnknown += 1;
      continue;
    }
    importable.add(c);
  }
  return ImportableCases(
    importable: importable,
    droppedUnknown: droppedUnknown,
  );
}

ParseResult parseAutomationCases(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    return const ParseResult(cases: [], errors: []);
  }
  final isJson = trimmed.startsWith('[') || trimmed.startsWith('{');
  var result = isJson ? _parseJson(trimmed) : _parseLines(input);
  if (!isJson) result = _pruneSignallessBareNames(result);
  _disambiguateNames(result.cases);
  return result;
}

/// A bare-name line ("A", "baseline") carries zero automation signal — on its
/// own it's indistinguishable from clipboard junk. Bare names are only trusted
/// when the SAME paste also contains a structured case (params or a route),
/// i.e. the legit "baseline + variants" matrix shape. JSON bypasses this.
ParseResult _pruneSignallessBareNames(ParseResult result) {
  if (result.cases.isEmpty) return result;
  final hasSignal = result.cases
      .any((c) => c.params.isNotEmpty || (c.route?.isNotEmpty ?? false));
  if (hasSignal) return result;
  return ParseResult(cases: const [], errors: result.errors);
}

/// URL-style pastes where every line shares a path collapse to identical case
/// names. When that happens, rewrite each colliding name to its
/// differing-params summary. Mutates in place.
void _disambiguateNames(List<AutomationCase> cases) {
  if (cases.length < 2) return;
  final counts = <String, int>{};
  for (final c in cases) {
    counts[c.name] = (counts[c.name] ?? 0) + 1;
  }
  if (!counts.values.any((n) => n > 1)) return;

  final labels = computeCaseLabels([
    for (final c in cases)
      CaseLabelInput(name: c.name, params: c.params, route: c.route),
  ]).labels;

  for (var i = 0; i < cases.length; i++) {
    if (i >= labels.length) continue;
    final newLabel = labels[i];
    if (newLabel.isEmpty) continue;
    if ((counts[cases[i].name] ?? 0) > 1) cases[i].name = newLabel;
  }
}

ParseResult _parseJson(String input) {
  final errors = <ParseCaseError>[];
  Object? parsed;
  try {
    parsed = jsonDecode(input);
  } catch (err) {
    errors.add(ParseCaseError(
      line: 1,
      reason: 'invalid JSON',
      raw: input.length > 80 ? input.substring(0, 80) : input,
    ));
    return ParseResult(cases: const [], errors: errors);
  }

  // Accept either an array of cases or a single case object.
  final rawCases = parsed is List ? parsed : [parsed];
  final cases = <AutomationCase>[];
  for (var i = 0; i < rawCases.length; i++) {
    final raw = rawCases[i];
    if (raw is! Map) {
      errors.add(ParseCaseError(
        line: i + 1,
        reason: 'expected an object with a name field',
        raw: jsonEncode(raw),
      ));
      continue;
    }
    final obj = raw.cast<String, Object?>();
    final params = <String, String>{};
    final rawParams = obj['params'];
    if (rawParams is Map) {
      for (final e in rawParams.entries) {
        final k = e.key.toString();
        if (k.isEmpty) continue;
        params[k] = e.value == null ? '' : '${e.value}';
      }
    }

    // Optional route — accepts a full URL or a pathname; merges any embedded
    // search-string params so an AI can paste either shape.
    String? routeOverride;
    final rawRoute = obj['route'];
    if (rawRoute is String && rawRoute.trim().isNotEmpty) {
      final parsedRoute = parseRouteInput(rawRoute);
      if (parsedRoute != null) {
        routeOverride = parsedRoute.pathname;
        if (parsedRoute.search.isNotEmpty) {
          for (final entry in _decodeQuery(parsedRoute.search)) {
            params.putIfAbsent(entry.key, () => entry.value);
          }
        }
      }
    }

    final rawName = obj['name'];
    final explicitName =
        rawName is String && rawName.trim().isNotEmpty ? rawName.trim() : '';
    final name = explicitName.isNotEmpty
        ? explicitName
        : _autoNameFor(routeOverride, params, cases.length);

    final c = createBlankCase(name);
    c.params = params;
    if (routeOverride != null) c.route = routeOverride;
    cases.add(c);
  }
  return ParseResult(cases: cases, errors: errors);
}

ParseResult _parseLines(String input) {
  final cases = <AutomationCase>[];
  final errors = <ParseCaseError>[];
  final lines = _rejoinWrappedUrls(input.split(RegExp(r'\r?\n')));

  for (var i = 0; i < lines.length; i++) {
    final raw = lines[i];
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#') || line.startsWith('//')) continue;

    final parsed = _parseLine(line);
    if (parsed.error != null) {
      errors.add(ParseCaseError(line: i + 1, reason: parsed.error!, raw: raw));
      continue;
    }
    cases.add(parsed.value!);
  }

  return ParseResult(cases: cases, errors: errors);
}

/// A single URL-query fragment split off when a viewer wrapped a long URL —
/// `ale=0.5`, `=true&next=v`. Looks like `key=value` with no `/ ? :` or
/// interior whitespace, and always belongs glued back onto the previous URL.
final RegExp _urlFragmentRe =
    RegExp(r'^[A-Za-z0-9_-]*=[^/?:\s]+(?:&[A-Za-z0-9_-]+=[^/?:\s]*)*$');

final RegExp _httpRe = RegExp(r'^https?:\/\/', caseSensitive: false);

/// Repair URL lines the user's terminal / markdown viewer wrapped mid-string
/// (RN `rejoinWrappedUrls`). Concatenates with no whitespace — valid query
/// strings never contain spaces.
List<String> _rejoinWrappedUrls(List<String> lines) {
  final out = <String>[];
  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty) {
      out.add(raw);
      continue;
    }
    final looksLikeFragment = _urlFragmentRe.hasMatch(line);
    final isStandalone = line.startsWith('/') ||
        _httpRe.hasMatch(line) ||
        line.startsWith('#') ||
        line.startsWith('//') ||
        (!looksLikeFragment &&
            (line.contains('?') ||
                line.contains(':') ||
                RegExp(r'\s').hasMatch(line)));
    if (isStandalone) {
      out.add(raw);
      continue;
    }

    // Walk backwards to the most-recent URL line to merge into.
    var mergeIdx = -1;
    for (var i = out.length - 1; i >= 0; i--) {
      final prev = out[i].trim();
      if (prev.isEmpty) continue;
      if (prev.startsWith('#') || prev.startsWith('//')) break;
      if (prev.startsWith('/') || _httpRe.hasMatch(prev)) {
        mergeIdx = i;
        break;
      }
      break;
    }
    if (mergeIdx >= 0) {
      out[mergeIdx] = out[mergeIdx].trimRight() + line;
      continue;
    }
    out.add(raw);
  }
  return out;
}

class _LineResult {
  const _LineResult.ok(this.value) : error = null;
  const _LineResult.err(this.error) : value = null;
  final AutomationCase? value;
  final String? error;
}

_LineResult _parseLine(String line) {
  // Full URL: starts with "/" or "http(s)://". Sniffed BEFORE the older
  // "name?k=v" branch so a path containing "?" lands in the right bucket.
  if (line.startsWith('/') || _httpRe.hasMatch(line)) {
    final parsed = parseRouteInput(line);
    if (parsed != null) {
      final params = <String, String>{};
      if (parsed.search.isNotEmpty) {
        for (final entry in _decodeQuery(parsed.search)) {
          params[entry.key] = entry.value;
        }
      }
      final c = createBlankCase(_autoNameFor(parsed.pathname, params, 0));
      c.params = params;
      c.route = parsed.pathname;
      return _LineResult.ok(c);
    }
    // parseRouteInput rejected it — fall through to the legacy parsers.
  }

  // URL-style: "name?key=value&key=value"
  final qIdx = line.indexOf('?');
  if (qIdx >= 0) {
    final rawName = line.substring(0, qIdx).trim();
    final name = rawName.isEmpty ? 'case' : rawName;
    final params = <String, String>{};
    for (final entry in _decodeQuery(line.substring(qIdx + 1))) {
      params[entry.key] = entry.value;
    }
    // Reject lines that decode to all-empty values (report-markdown dump
    // fragments like `?route=&count=&engine=`) — zero signal, and they balloon
    // the case count when a user pastes an over-broad selection.
    if (params.isNotEmpty && params.values.every((v) => v.isEmpty)) {
      return const _LineResult.err(
        'all params empty — looks like a report-dump fragment, not a case URL',
      );
    }
    final c = createBlankCase(name);
    c.params = params;
    return _LineResult.ok(c);
  }

  // Colon-delimited: "name: key=value, key=value"
  final colonIdx = line.indexOf(':');
  if (colonIdx < 0) {
    // Bare name. Reject lines that look like wrapped URL fragments — those
    // mean `_rejoinWrappedUrls` missed a wrap and we'd inflate the matrix.
    if (_urlFragmentRe.hasMatch(line)) {
      return const _LineResult.err(
        'looks like a wrapped URL fragment — paste the URL on one line',
      );
    }
    return _LineResult.ok(createBlankCase(line));
  }
  final rawName = line.substring(0, colonIdx).trim();
  final name = rawName.isEmpty ? 'case' : rawName;
  final rest = line.substring(colonIdx + 1).trim();
  final params = <String, String>{};
  if (rest.isNotEmpty) {
    for (final piece in _splitParams(rest)) {
      final eq = piece.indexOf('=');
      if (eq < 0) return _LineResult.err('expected key=value, got "$piece"');
      final k = piece.substring(0, eq).trim();
      final v = piece.substring(eq + 1).trim();
      if (k.isEmpty) return _LineResult.err('empty param key in "$piece"');
      params[k] = v;
    }
  }
  final c = createBlankCase(name);
  c.params = params;
  return _LineResult.ok(c);
}

/// Split on commas OR semicolons, tolerating values with spaces.
List<String> _splitParams(String input) => [
      for (final s in input.split(RegExp(r'[,;]')))
        if (s.trim().isNotEmpty) s.trim(),
    ];

/// Yield [key, value] pairs from a "k=v&k=v" query string.
Iterable<MapEntry<String, String>> _decodeQuery(String query) sync* {
  for (final piece in query.split('&')) {
    if (piece.isEmpty) continue;
    final eq = piece.indexOf('=');
    String k;
    String v;
    try {
      if (eq < 0) {
        k = Uri.decodeComponent(piece.trim());
        v = '';
      } else {
        k = Uri.decodeComponent(piece.substring(0, eq).trim());
        v = Uri.decodeComponent(piece.substring(eq + 1).trim());
      }
    } catch (_) {
      continue;
    }
    if (k.isEmpty) continue;
    yield MapEntry(k, v);
  }
}

/// Auto-derive a case display name when none was provided. Prefers the params
/// summary, then the pathname, then a numeric fallback.
String _autoNameFor(String? route, Map<String, String> params, int idx) {
  final formatted = formatParams(params);
  if (formatted.isNotEmpty) return formatted;
  if (route != null && route.isNotEmpty) return route;
  return 'case ${idx + 1}';
}
