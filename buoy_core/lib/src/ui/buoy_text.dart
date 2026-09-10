import 'package:flutter/material.dart';

/// The React Native text baseline, for everything Buoy draws.
///
/// RN's `<Text>` has NO line-height multiplier unless the style gives one: the
/// line box is the font's own ascent + descent (≈1.2 em for the system font).
/// Material puts a `height` on almost every text-theme entry — 1.43 on
/// `bodyMedium`, 1.5 on `bodyLarge` — and every `Material` widget installs
/// `bodyMedium` as the ambient `DefaultTextStyle` while every `TextField`
/// merges its own style onto `bodyLarge`. A Buoy widget inside a modal
/// therefore inherited leading React Native never had.
///
/// The cross-framework parity sheet measured both: a 12 pt method badge came
/// out 25 pt tall against RN's 22.3, and the search bar 39 pt against 35 — the
/// same +2.7 / +4 rode into every badge, row, card and input.
///
/// Wrap a Buoy surface in this (JsModal does it for every tool) and text sizes
/// the way it does on RN. Widgets keep setting their own `fontSize`/`color`;
/// this only decides what they inherit.
class BuoyTextBaseline extends StatelessWidget {
  const BuoyTextBaseline({super.key, required this.child});

  final Widget child;

  /// The same style with no `height`. `copyWith(height: null)` cannot express
  /// this — a null argument means "leave it alone" — so the style is rebuilt.
  static TextStyle? _noLeading(TextStyle? s) => s == null
      ? null
      : TextStyle(
          color: s.color,
          backgroundColor: s.backgroundColor,
          fontSize: s.fontSize,
          fontWeight: s.fontWeight,
          fontStyle: s.fontStyle,
          letterSpacing: s.letterSpacing,
          wordSpacing: s.wordSpacing,
          textBaseline: s.textBaseline,
          leadingDistribution: s.leadingDistribution,
          fontFamily: s.fontFamily,
          fontFamilyFallback: s.fontFamilyFallback,
          decoration: s.decoration,
          decorationColor: s.decorationColor,
          decorationStyle: s.decorationStyle,
          decorationThickness: s.decorationThickness,
        );

  static TextTheme _flatten(TextTheme t) => TextTheme(
    displayLarge: _noLeading(t.displayLarge),
    displayMedium: _noLeading(t.displayMedium),
    displaySmall: _noLeading(t.displaySmall),
    headlineLarge: _noLeading(t.headlineLarge),
    headlineMedium: _noLeading(t.headlineMedium),
    headlineSmall: _noLeading(t.headlineSmall),
    titleLarge: _noLeading(t.titleLarge),
    titleMedium: _noLeading(t.titleMedium),
    titleSmall: _noLeading(t.titleSmall),
    bodyLarge: _noLeading(t.bodyLarge),
    bodyMedium: _noLeading(t.bodyMedium),
    bodySmall: _noLeading(t.bodySmall),
    labelLarge: _noLeading(t.labelLarge),
    labelMedium: _noLeading(t.labelMedium),
    labelSmall: _noLeading(t.labelSmall),
  );

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Theme(
      // Inputs read the THEME, not the ambient DefaultTextStyle.
      data: theme.copyWith(textTheme: _flatten(theme.textTheme)),
      child: DefaultTextStyle(
        // A FRESH style, not a merge, for the same reason as [_noLeading].
        // RN's default size on iOS is 14.
        style: const TextStyle(
          color: Color(0xFFFFFFFF),
          fontSize: 14,
          fontWeight: FontWeight.w400,
          decoration: TextDecoration.none,
        ),
        child: child,
      ),
    );
  }
}

/// The system font's own line height, as a multiple of the font size — what a
/// `Text`/`<Text>` with no `height` is laid out at on both frameworks.
///
/// Measured once, not hardcoded: it is a property of the platform's font, and
/// writing 1.19 here would be a number nobody could re-derive.
double get buoyNaturalLineHeight => _naturalLineHeight ??= _measureLineHeight();
double? _naturalLineHeight;

double _measureLineHeight() {
  const double probe = 100;
  final TextPainter painter = TextPainter(
    text: const TextSpan(text: 'Ag', style: TextStyle(fontSize: probe)),
    textDirection: TextDirection.ltr,
  )..layout();
  final double h = painter.height / probe;
  painter.dispose();
  return h;
}

/// The line box RN gives a `<TextInput>`, as a `TextStyle.height`.
///
/// A `TextField` resolves its style against `theme.textTheme.bodyLarge`, whose
/// Material 3 value carries `height: 1.5`, and a MERGE CANNOT UN-SET a height —
/// not through [BuoyTextBaseline]'s flattened theme (the field re-reads
/// `bodyLarge` itself) and not through `strutStyle`, which the input decorator
/// does not measure. The only lever left is to say the number outright, and
/// [buoyNaturalLineHeight] is that number without inventing it. Without this
/// the parity sheet's search bar came out 39 pt tall against RN's 35.
///
/// ```dart
/// style: TextStyle(fontSize: 14, height: buoyInputLineHeight)
/// ```
double get buoyInputLineHeight => buoyNaturalLineHeight;
