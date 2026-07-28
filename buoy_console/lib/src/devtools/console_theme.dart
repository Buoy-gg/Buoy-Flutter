/// Ports packages/console/src/devtools/theme.ts.
///
/// The active dark console palette, matched to Buoy's shared `macOSColors`
/// tokens and contrast-tuned per WCAG AA. Only the dark theme ships (RN's
/// `consoleTheme = darkTheme`); the light values are omitted (kept for a future
/// toggle in RN, unused here).
library;

import 'package:flutter/painting.dart';

/// Monospace font family (RN Platform.select default on native).
const String monoFont = 'monospace';

/// Dark theme — matched to macOSColors, contrast-tuned (RN darkTheme).
class ConsoleTheme {
  static const baseContainer = Color(0xFF0A0A0C); // background.base
  static const surfaceError = Color(0x26FF453A); // rgba(255,69,58,0.15)
  static const surfaceYellow = Color(0x21FFEB3B); // rgba(255,235,59,0.13)
  static const divider = Color(0xFF3A3A40);
  static const inputBackground = Color(0xFF26262A);
  static const menuBackground = Color(0xFF1A1A1C);
  static const onSurface = Color(0xFFF5F5F7);
  static const onSurfaceYellow = Color(0xFFFFE9A3);
  static const onErrorContainer = Color(0xFFFFB4AB);
  static const tokenSubtle = Color(0xFFA1A1A6);
  static const primary = Color(0xFF40CCFF); // links
  static const valueNumber = Color(0xFFFF9F1C); // number + boolean
  static const valueString = Color(0xFF7EE787); // string/regexp/symbol
  static const valueBigint = Color(0xFFA1A1A6);
  static const valueNode = Color(0xFFF5F5F7);
  static const valueNullish = Color(0xFF8E8E93);
  static const valuePreview = Color(0xFFA1A1A6);
}

/// ANSI 16-color palette (dark), from RN `ansiColors` / consoleView.css.
const Map<String, Color> ansiColors = {
  'black': Color(0xFF000000),
  'red': Color(0xFFED4E4C),
  'green': Color(0xFF01C801),
  'yellow': Color(0xFFD2C057),
  'blue': Color(0xFF2774F0),
  'magenta': Color(0xFFA142F4),
  'cyan': Color(0xFF12B5CB),
  'gray': Color(0xFFCFD0D0),
  'darkgray': Color(0xFF898989),
  'lightred': Color(0xFFF28B82),
  'lightgreen': Color(0xFFA1F7B5),
  'lightyellow': Color(0xFFDDFB55),
  'lightblue': Color(0xFF669DF6),
  'lightmagenta': Color(0xFFD670D6),
  'lightcyan': Color(0xFF84F0FF),
  'white': Color(0xFFFFFFFF),
};

/// Per-level row styling (RN levelStyles). [icon] is 'warning' | 'error' | null.
class LevelStyle {
  const LevelStyle({this.background, required this.text, this.icon});
  final Color? background;
  final Color text;
  final String? icon;
}

const Map<String, LevelStyle> levelStyles = {
  'verbose': LevelStyle(text: ConsoleTheme.tokenSubtle),
  'info': LevelStyle(text: ConsoleTheme.onSurface),
  'warning': LevelStyle(
    background: ConsoleTheme.surfaceYellow,
    text: ConsoleTheme.onSurfaceYellow,
    icon: 'warning',
  ),
  'error': LevelStyle(
    background: ConsoleTheme.surfaceError,
    text: ConsoleTheme.onErrorContainer,
    icon: 'error',
  ),
};
