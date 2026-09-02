/// Ports packages/shared/src/ui/night/nightTheme.ts — the "Night" design
/// tokens: the Everlights surface language every Buoy tool renders in since
/// the suite-wide theme move (Aug 2026).
///
/// A near-black, smooth, borderless-feeling system built to sit ON TOP of the
/// shared tool background: one `#050505` sheet the field shows through,
/// `#0C0C0C` cards with hairline `#1A1A1C` borders, `#161618` rows inside
/// them, uppercase section labels OUTSIDE the cards, and a single green accent
/// that takes dark ink.
///
/// Values are lifted 1:1 from RN, which lifted them 1:1 from the Everlights
/// app's `constants/theme.ts` — that app is the design reference, so when in
/// doubt match it, don't invent.
///
/// THE ACCENT IS ONE SEAM: everything green reads `NightColor.accent*`.
/// The family is Buoy's brand green (#20C997). Swapping it is a seven-line
/// change here and nowhere else. `onAccent` stays black — this green wants
/// dark ink.
///
/// Lives in buoy_core (not buoy_shared_ui) because `JsModal`'s night chrome
/// needs it and nothing below core may depend on shared_ui; shared_ui
/// re-exports it so tools import from their usual barrel — the same
/// arrangement as the icon set and the wire-budget guards.
library;

import 'dart:ui' show Color;

/// RN `night.color`. `rgba(255,255,255,0.08)`-style values are `Color.fromRGBO`
/// with the same alpha, so they composite identically over the sheet.
abstract final class NightColor {

  /// The sheet itself — also the inset track of a segmented control.
  static const Color bg = Color(0xFF050505);

  /// A card.
  static const Color surface = Color(0xFF0C0C0C);

  /// A row or control inside a card.
  static const Color surfaceElevated = Color(0xFF161618);

  /// Hairline card border.
  static const Color border = Color(0xFF1A1A1C);

  /// Hairline between rows inside a card.
  static const Color separator = Color.fromRGBO(255, 255, 255, 0.08);

  /// Neutral fills, lightest → strongest.
  static const Color fill = Color.fromRGBO(255, 255, 255, 0.06);
  static const Color fillSecondary = Color.fromRGBO(255, 255, 255, 0.08);
  static const Color fillTertiary = Color.fromRGBO(255, 255, 255, 0.12);

  /// Chip resting fill — dark glass, readable over the star field.
  static const Color buttonSurface = Color.fromRGBO(8, 10, 14, 0.85);

  /// Secondary/destructive button plate.
  static const Color button = Color(0xFF1C1C1C);
  static const Color buttonPressed = Color(0xFF2C2C2E);

  static const Color text = Color(0xFFECEDEE);
  static const Color textSecondary = Color(0xFF9BA1A6);
  static const Color textTertiary = Color(0xFF636366);

  /// Drag handles, input placeholders.
  static const Color placeholder = Color.fromRGBO(255, 255, 255, 0.30);

  /// The one accent (Buoy brand green). See the library note — one seam.
  static const Color accent = Color(0xFF20C997);
  static const Color accentPressed = Color(0xFF1BAB80);
  static const Color accentSoft = Color.fromRGBO(32, 201, 151, 0.12);
  static const Color accentFill = Color.fromRGBO(32, 201, 151, 0.18);
  static const Color accentBorder = Color.fromRGBO(32, 201, 151, 0.20);
  static const Color accentBorderStrong = Color.fromRGBO(32, 201, 151, 0.35);

  /// Ink on a filled accent surface — the accent takes DARK ink.
  static const Color onAccent = Color(0xFF000000);

  static const Color danger = Color(0xFFFF3B30);
  static const Color dangerSoft = Color.fromRGBO(255, 59, 48, 0.10);
  static const Color warning = Color(0xFFFF8329);
  static const Color warningSoft = Color.fromRGBO(255, 131, 41, 0.12);
  static const Color info = Color(0xFF1E6DFF);
  static const Color infoSoft = Color.fromRGBO(30, 109, 255, 0.12);

  /// Switch thumb at rest (Everlights moon gray).
  static const Color knob = Color(0xFFD4D8DC);
}

/// RN `night.radius`.
abstract final class NightRadius {

  /// Sheets and dialogs.
  static const double sheet = 16;

  /// Cards.
  static const double card = 14;

  /// Inputs and code blocks.
  static const double input = 12;

  /// Rows and inner controls; also the segmented-control track.
  static const double row = 10;

  /// Segment thumb inside a radius-10 track.
  static const double segment = 8;

  /// Small badges.
  static const double badge = 6;

  /// Zone-style chips.
  static const double chip = 20;

  /// Fully rounded pills (buttons use height/2 instead).
  static const double pill = 999;
}

/// RN `night.font` — sizes in logical px, same as RN's.
abstract final class NightFont {

  /// Sheet/modal titles.
  static const double title = 17;

  /// Row labels and values.
  static const double row = 15;

  /// Body copy, chip labels.
  static const double body = 14;

  /// Segmented-control labels, captions, footnotes.
  static const double caption = 13;

  /// Uppercase section labels.
  static const double label = 12;

  /// Uppercase micro labels (START/END style).
  static const double micro = 11;
}

/// RN `night` — read as `NightColor.bg`, `NightRadius.sheet`, `NightFont.row`,
/// `Night.gutter`. Split into flat static-const classes (not `night.color.x`
/// on one object) so every token is a compile-time constant and can feed
/// `const` widgets, maps and switch constants.
abstract final class Night {

  /// Screen/sheet horizontal margin.
  static const double gutter = 16;

  /// Section labels sit 4pt in from the card edge.
  static const double labelInset = 4;

  /// Vertical rhythm between labeled card groups.
  static const double groupGap = 24;

  /// Card interior padding.
  static const double cardPad = 14;

  /// Row padding inside an edge-to-edge card.
  static const double rowPadH = 16;
  static const double rowPadV = 14;

  /// Section labels track wide open, Everlights-style (RN
  /// `NIGHT_LABEL_TRACKING`, a `letterSpacing`).
  static const double labelTracking = 0.8;
}

/// RN's `color + "55"` alpha-byte idiom: append a hex alpha to an opaque
/// colour. `NightColor.accent.withAlphaByte(0x55)`.
extension NightAlpha on Color {
  Color withAlphaByte(int alpha) => withAlpha(alpha);
}
