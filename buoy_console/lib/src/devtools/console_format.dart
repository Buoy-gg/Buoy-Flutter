/// Ports packages/console/src/devtools/consoleFormat.ts.
///
/// The WHATWG console Formatter: %s/%d/%i/%f/%o/%O/%c/%_ substitutions plus ANSI
/// SGR (\x1B[…m) styling. Where DevTools works over V8 RemoteObjects we work over
/// raw Dart values; the substitution/ANSI logic is otherwise 1:1.
///
/// Output is a flat list of tokens the row renderer consumes:
///  - [StringToken]: text, optionally styled by %c / ANSI.
///  - [ValueToken]: an object/list substitution (%o/%O) or a trailing
///    non-string argument.
library;

import 'dart:convert';

import 'package:flutter/painting.dart';

import 'console_theme.dart';

/// One rendered token.
abstract class FormatToken {
  const FormatToken();
}

class StringToken extends FormatToken {
  const StringToken(this.value, {this.style});
  final String value;
  final TextStyle? style;
}

class ValueToken extends FormatToken {
  const ValueToken(this.value, {required this.generic});
  final Object? value;

  /// %O forces the generic (non-preview) object tree.
  final bool generic;
}

// VGA color palette (matches RN ANSI_COLORS / ANSI_BRIGHT_COLORS).
const _ansiColorNames = [
  'black',
  'red',
  'green',
  'yellow',
  'blue',
  'magenta',
  'cyan',
  'gray',
];
const _ansiBrightNames = [
  'darkgray',
  'lightred',
  'lightgreen',
  'lightyellow',
  'lightblue',
  'lightmagenta',
  'lightcyan',
  'white',
];

/// A console arg's `description` (string form) — RN RemoteObject.description.
String _description(Object? arg) {
  if (arg is String) return arg;
  if (arg == null) return 'null';
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

// \x1B is the ANSI escape (ESC). Matches a %-specifier OR an SGR sequence.
final RegExp _formatRe = RegExp(r'%([%_Oocsdfi])|\x1B\[([\d;]*)m');

/// Does the first arg actually need the substitution engine?
bool _hasFormatting(String fmt) => _formatRe.hasMatch(fmt);

/// Convert a CSS declaration string (from %c or ANSI) into a TextStyle.
TextStyle? _cssToTextStyle(String css) {
  Color? color;
  Color? backgroundColor;
  FontWeight? fontWeight;
  FontStyle? fontStyle;
  double? fontSize;
  TextDecoration? decoration;
  var any = false;

  for (final decl in css.split(';')) {
    final idx = decl.indexOf(':');
    if (idx == -1) continue;
    final prop = decl.substring(0, idx).trim().toLowerCase();
    var value = decl.substring(idx + 1).trim();
    if (value.isEmpty) continue;

    // Resolve DevTools ANSI color vars to concrete colors.
    final varMatch = RegExp(r'var\(--console-color-([a-z]+)\)').firstMatch(value);
    final resolvedColor =
        varMatch != null ? ansiColors[varMatch.group(1)] : _parseCssColor(value);

    switch (prop) {
      case 'color':
        color = resolvedColor;
        any = true;
        break;
      case 'background-color':
      case 'background':
        backgroundColor = resolvedColor;
        any = true;
        break;
      case 'font-weight':
        fontWeight = value == 'lighter'
            ? FontWeight.w300
            : value == 'bold'
                ? FontWeight.bold
                : _weightFromString(value);
        any = true;
        break;
      case 'font-style':
        if (value == 'italic') {
          fontStyle = FontStyle.italic;
          any = true;
        }
        break;
      case 'font-size':
        final n = double.tryParse(value.replaceAll(RegExp(r'[^0-9.]'), ''));
        if (n != null) {
          fontSize = n;
          any = true;
        }
        break;
      case 'text-decoration':
      case 'text-decoration-line':
        final under = value.contains('underline');
        final strike = value.contains('line-through');
        if (under && strike) {
          decoration = TextDecoration.combine(
              [TextDecoration.underline, TextDecoration.lineThrough]);
        } else if (under) {
          decoration = TextDecoration.underline;
        } else if (strike) {
          decoration = TextDecoration.lineThrough;
        }
        any = true;
        break;
      default:
        break;
    }
  }
  if (!any) return null;
  return TextStyle(
    color: color,
    backgroundColor: backgroundColor,
    fontWeight: fontWeight,
    fontStyle: fontStyle,
    fontSize: fontSize,
    decoration: decoration,
  );
}

FontWeight? _weightFromString(String v) {
  final n = int.tryParse(v);
  if (n == null) return null;
  const map = {
    100: FontWeight.w100,
    200: FontWeight.w200,
    300: FontWeight.w300,
    400: FontWeight.w400,
    500: FontWeight.w500,
    600: FontWeight.w600,
    700: FontWeight.w700,
    800: FontWeight.w800,
    900: FontWeight.w900,
  };
  return map[n];
}

/// Best-effort CSS color → Color (rgb(...)/#hex). Unknown → null.
Color? _parseCssColor(String value) {
  final rgb = RegExp(r'rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)').firstMatch(value);
  if (rgb != null) {
    return Color.fromARGB(
      255,
      int.parse(rgb.group(1)!),
      int.parse(rgb.group(2)!),
      int.parse(rgb.group(3)!),
    );
  }
  final hex = RegExp(r'^#([0-9a-fA-F]{6})$').firstMatch(value);
  if (hex != null) {
    return Color(int.parse('FF${hex.group(1)}', radix: 16));
  }
  return null;
}

/// Apply one ANSI SGR sequence to the running style map (RN algorithm).
void _applyAnsi(List<int> codes, Map<String, String> currentStyle) {
  void addTextDecoration(String value) {
    final td = currentStyle['text-decoration'] ?? '';
    if (!td.contains(value)) currentStyle['text-decoration'] = '$td $value';
  }

  void removeTextDecoration(String value) {
    final td = currentStyle['text-decoration']?.replaceAll(' $value', '');
    if (td != null && td.isNotEmpty) {
      currentStyle['text-decoration'] = td;
    } else {
      currentStyle.remove('text-decoration');
    }
  }

  final queue = List<int>.from(codes);
  while (queue.isNotEmpty) {
    final code = queue.removeAt(0);
    switch (code) {
      case 0:
        currentStyle.clear();
        break;
      case 1:
        currentStyle['font-weight'] = 'bold';
        break;
      case 2:
        currentStyle['font-weight'] = 'lighter';
        break;
      case 3:
        currentStyle['font-style'] = 'italic';
        break;
      case 4:
        addTextDecoration('underline');
        break;
      case 9:
        addTextDecoration('line-through');
        break;
      case 22:
        currentStyle.remove('font-weight');
        break;
      case 23:
        currentStyle.remove('font-style');
        break;
      case 24:
        removeTextDecoration('underline');
        break;
      case 29:
        removeTextDecoration('line-through');
        break;
      case 38:
      case 48:
        if (queue.isNotEmpty && queue.removeAt(0) == 2) {
          final r = queue.isNotEmpty ? queue.removeAt(0) : 0;
          final g = queue.isNotEmpty ? queue.removeAt(0) : 0;
          final b = queue.isNotEmpty ? queue.removeAt(0) : 0;
          currentStyle[code == 38 ? 'color' : 'background-color'] =
              'rgb($r,$g,$b)';
        }
        break;
      case 39:
      case 49:
        currentStyle.remove(code == 39 ? 'color' : 'background-color');
        break;
      default:
        String? color;
        if (code - 30 >= 0 && code - 30 < _ansiColorNames.length) {
          color = _ansiColorNames[code - 30];
        } else if (code - 90 >= 0 && code - 90 < _ansiBrightNames.length) {
          color = _ansiBrightNames[code - 90];
        }
        if (color != null) {
          currentStyle['color'] = 'var(--console-color-$color)';
        } else {
          String? bg;
          if (code - 40 >= 0 && code - 40 < _ansiColorNames.length) {
            bg = _ansiColorNames[code - 40];
          } else if (code - 100 >= 0 && code - 100 < _ansiBrightNames.length) {
            bg = _ansiBrightNames[code - 100];
          }
          if (bg != null) {
            currentStyle['background-color'] = 'var(--console-color-$bg)';
          }
        }
        break;
    }
  }
}

class _SubResult {
  const _SubResult(this.tokens, this.rest);
  final List<FormatToken> tokens;
  final List<Object?> rest;
}

/// Run the substitution engine over a format string + its args.
_SubResult _formatWithSubstitutions(String fmtIn, List<Object?> args) {
  var fmt = fmtIn;
  final tokens = <FormatToken>[];
  final currentStyle = <String, String>{};
  TextStyle? cssStyle;

  void pushString(String value) {
    if (value.isEmpty) return;
    if (tokens.isNotEmpty && tokens.last is StringToken) {
      final last = tokens.last as StringToken;
      if (last.style == cssStyle) {
        tokens[tokens.length - 1] =
            StringToken(last.value + value, style: cssStyle);
        return;
      }
    }
    tokens.add(StringToken(value, style: cssStyle));
  }

  var argIndex = 0;
  for (var match = _formatRe.firstMatch(fmt);
      match != null;
      match = _formatRe.firstMatch(fmt)) {
    pushString(fmt.substring(0, match.start));
    Object? substitution;
    final specifier = match.group(1);
    switch (specifier) {
      case '%':
        pushString('%');
        substitution = '';
        break;
      case 's':
        if (argIndex < args.length) {
          substitution = _description(args[argIndex++]);
        }
        break;
      case 'c':
        if (argIndex < args.length) {
          cssStyle = _cssToTextStyle(_description(args[argIndex++]));
          substitution = '';
        }
        break;
      case 'o':
      case 'O':
        if (argIndex < args.length) {
          tokens.add(ValueToken(args[argIndex++], generic: specifier == 'O'));
          substitution = '';
        }
        break;
      case '_':
        if (argIndex < args.length) {
          argIndex++;
          substitution = '';
        }
        break;
      case 'd':
      case 'f':
      case 'i':
        if (argIndex < args.length) {
          final v = args[argIndex++];
          num n = v is num ? v : double.nan;
          if (specifier != 'f' && !n.isNaN) n = n.floor();
          substitution = n.isNaN ? 'NaN' : n.toString();
        }
        break;
      case null:
        // ANSI SGR sequence.
        final codes = (match.group(2)?.isNotEmpty == true
                ? match.group(2)!.split(';')
                : ['0'])
            .map((c) => c.isEmpty ? 0 : int.tryParse(c) ?? 0)
            .toList();
        _applyAnsi(codes, currentStyle);
        final css = currentStyle.entries
            .map((e) => '${e.key}:${e.value.trimLeft()}')
            .join(';');
        cssStyle = _cssToTextStyle(css);
        substitution = '';
        break;
    }
    if (substitution == null) {
      pushString(match.group(0)!);
      substitution = '';
    }
    fmt = '$substitution${fmt.substring(match.end)}';
  }
  pushString(fmt);
  return _SubResult(tokens, args.sublist(argIndex.clamp(0, args.length)));
}

/// Format a console call's arguments into renderable tokens (RN
/// formatConsoleMessage): if the first arg is a format string it drives
/// substitution, then any leftover args are appended (space-separated).
List<FormatToken> formatConsoleMessage(List<Object?> args) {
  if (args.isEmpty) return const [];

  var tokens = <FormatToken>[];
  var rest = args;

  final first = args.first;
  if (first is String && _hasFormatting(first)) {
    final result = _formatWithSubstitutions(first, args.sublist(1));
    tokens = result.tokens;
    rest = result.rest;
  }

  for (final arg in rest) {
    if (tokens.isNotEmpty) tokens.add(const StringToken(' '));
    if (arg is String) {
      tokens.add(StringToken(arg));
    } else {
      tokens.add(ValueToken(arg, generic: false));
    }
  }

  return tokens;
}
