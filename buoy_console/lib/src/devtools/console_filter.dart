/// Ports packages/console/src/devtools/consoleFilter.ts.
///
/// - Level mask: 4 levels (verbose/info/warning/error); "Default" = all but
///   verbose.
/// - Text filter: space-separated tokens, AND-combined. Each token may be a
///   plain substring, a `/regex/`, or `key:value`, and a leading `-` negates it.
///   Captured entries have no url/source/context fields, so keyed tokens degrade
///   to a substring test against the rendered message.
library;

import '../console_log_store.dart';

/// The four DevTools levels, in menu order.
const List<String> levelOrder = ['verbose', 'info', 'warning', 'error'];

const Map<String, String> levelLabel = {
  'verbose': 'Verbose',
  'info': 'Info',
  'warning': 'Warnings',
  'error': 'Errors',
};

/// A per-level visibility mask (RN LevelsMask).
class LevelsMask {
  const LevelsMask({
    required this.verbose,
    required this.info,
    required this.warning,
    required this.error,
  });

  final bool verbose;
  final bool info;
  final bool warning;
  final bool error;

  bool operator [](String level) {
    switch (level) {
      case 'verbose':
        return verbose;
      case 'info':
        return info;
      case 'warning':
        return warning;
      case 'error':
        return error;
      default:
        return false;
    }
  }

  LevelsMask toggled(String level) => LevelsMask(
        verbose: level == 'verbose' ? !verbose : verbose,
        info: level == 'info' ? !info : info,
        warning: level == 'warning' ? !warning : warning,
        error: level == 'error' ? !error : error,
      );

  bool sameAs(LevelsMask o) =>
      verbose == o.verbose &&
      info == o.info &&
      warning == o.warning &&
      error == o.error;
}

const LevelsMask allLevels =
    LevelsMask(verbose: true, info: true, warning: true, error: true);

/// "Default levels": everything except Verbose.
const LevelsMask defaultLevels =
    LevelsMask(verbose: false, info: true, warning: true, error: true);

/// One parsed filter token.
class ParsedFilter {
  const ParsedFilter({this.key, this.text, this.regex, required this.negative});
  final String? key;
  final String? text;
  final RegExp? regex;
  final bool negative;
}

final RegExp _keyValueRe = RegExp(r'^([\w-]+):(.+)$');
final RegExp _regexpRe = RegExp(r'^/(.+)/$');

/// Parse a filter query string into AND-combined parsed filters.
List<ParsedFilter> parseFilterQuery(String query) {
  final filters = <ParsedFilter>[];
  for (final rawToken in query.split(RegExp(r'\s+'))) {
    if (rawToken.isEmpty) continue;
    var token = rawToken;
    var negative = false;
    if (token.startsWith('-') && token.length > 1) {
      negative = true;
      token = token.substring(1);
    }

    final kv = _keyValueRe.firstMatch(token);
    if (kv != null) {
      filters.add(ParsedFilter(
        key: kv.group(1)!.toLowerCase(),
        text: kv.group(2),
        negative: negative,
      ));
      continue;
    }
    final rx = _regexpRe.firstMatch(token);
    if (rx != null) {
      try {
        filters.add(ParsedFilter(
          regex: RegExp(rx.group(1)!, caseSensitive: false, multiLine: true),
          negative: negative,
        ));
        continue;
      } catch (_) {
        // Invalid regex falls back to literal text (DevTools does the same).
      }
    }
    filters.add(ParsedFilter(text: token, negative: negative));
  }
  return filters;
}

bool _textMatches(ConsoleLogEntry entry, String text) =>
    entry.message.toLowerCase().contains(text.toLowerCase());

bool _applyFilters(ConsoleLogEntry entry, List<ParsedFilter> parsed) {
  for (final filter in parsed) {
    if (filter.regex != null) {
      if (filter.regex!.hasMatch(entry.message) == filter.negative) return false;
    } else if (filter.text != null) {
      if (_textMatches(entry, filter.text!) == filter.negative) return false;
    }
  }
  return true;
}

/// DevTools ConsoleFilter.shouldBeVisible, adapted to our entry model.
bool shouldBeVisible(
  ConsoleLogEntry entry,
  LevelsMask levelsMask,
  List<ParsedFilter> parsed,
) {
  // Group-end markers are control rows, never filtered out (handled by the view).
  if (entry.method == 'groupEnd') return true;
  if (!levelsMask[entry.level]) return false;
  return _applyFilters(entry, parsed);
}

/// The summary shown on the level menu button (RN updateLevelMenuButtonText).
String levelMenuSummary(LevelsMask mask) {
  if (mask.sameAs(allLevels)) return 'All levels';
  if (mask.sameAs(defaultLevels)) return 'Default levels';
  final enabled = levelOrder.where((l) => mask[l]).toList();
  if (enabled.isEmpty) return 'Hide all';
  if (enabled.length == 1) return '${levelLabel[enabled.first]} only';
  return 'Custom levels';
}
