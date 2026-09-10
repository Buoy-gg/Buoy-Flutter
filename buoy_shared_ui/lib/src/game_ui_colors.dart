import 'package:flutter/material.dart';

import 'macos_colors.dart';

/// Resolved values of shared-ui's `gameUIColors` (gameUIColors.ts). At runtime
/// the active theme is `macOSGameUIColors`, and `gameUIColors` is
/// `{...fallbacks, ...activeTheme}` — **the spread comes LAST on purpose**, so
/// the macOS theme wins on every key it defines and the dark-navy fallbacks
/// only apply to `defaultTheme`. Captured here as constants for the components
/// that style with gameUIColors (SearchBar, CollapsibleSection, StatsCard).
///
/// Provenance / resolution:
/// - panel      = background.card            (#1A1A1C)
/// - background = background.base            (#0A0A0C)
/// - secondary  = tertiary = text.secondary  (#A1A1A6)
/// - muted      = text.muted                 (#8E8E93)
/// - text       = text.primary               (#F5F5F7)
/// - primary    = text.primary               (#F5F5F7)
/// - border     = border.default             (#2D2D2F)
/// - success/warning/error = semantic.*
class GameUIColors {
  // `gameUIColors` is `{...fallbacks, ...macOSGameUIColors}`, and the macOS
  // snapshot WINS: `panel` is `macOSColors.background.card` and `background`
  // is `.base`. The two cyberpunk rgba fallbacks that used to sit here were
  // the pre-macOS values, and the parity sheet caught them — the search bar
  // filled #101622 where its RN twin fills #1A1A1C.
  static const panel = MacOSColors.backgroundCard;
  static const background = MacOSColors.backgroundBase;
  static const secondary = MacOSColors.textSecondary;
  static const tertiary = MacOSColors.textSecondary;
  static const muted = MacOSColors.textMuted;
  static const text = MacOSColors.textPrimary;
  // `macOSGameUIColors` defines `primary: macOSColors.text.primary`, and the
  // spread wins over the #FFFFFF fallback (see the library note).
  static const primary = MacOSColors.textPrimary;
  static const border = MacOSColors.borderDefault;
  static const success = MacOSColors.success;
  static const warning = MacOSColors.warning;
  static const error = MacOSColors.error;
}

/// Resolved values of shared-ui's `gameUIColors.diff` block (gameUIColors.ts).
/// The [TreeDiffViewer]'s dark theme reads these directly (RN
/// `gameUIColors.diff.*`). Captured as constants so the tree diff matches the RN
/// renderer byte-for-byte.
///
/// Provenance (gameUIColors.ts `diff:`):
/// - addedBackground   = rgba(74,255,159,0.1)   removedBackground = rgba(255,82,82,0.1)
/// - modifiedBackground= rgba(0,184,230,0.1)     contextBackground = rgba(255,255,255,0.02)
/// - addedText #4AFF9F  removedText #FF5252  modifiedText #00B8E6  unchangedText #B8BFC9
/// - addedWordHighlight rgba(74,255,159,0.3)  removedWordHighlight rgba(255,82,82,0.3)
/// - lineNumberBackground #0A0E1A  lineNumberText #7A8599  lineNumberBorder #1F2937
/// - markerAddedBackground rgba(74,255,159,0.2)  markerRemovedBackground rgba(255,82,82,0.2)
/// - markerModifiedBackground rgba(0,184,230,0.2)  markerText #7A8599
class GameUIDiffColors {
  static const addedBackground = Color(0x1A4AFF9F); // rgba(74,255,159,0.1)
  static const removedBackground = Color(0x1AFF5252); // rgba(255,82,82,0.1)
  static const modifiedBackground = Color(0x1A00B8E6); // rgba(0,184,230,0.1)
  static const unchangedBackground = Color(0x00000000); // transparent
  static const contextBackground = Color(0x05FFFFFF); // rgba(255,255,255,0.02)

  static const addedText = Color(0xFF4AFF9F);
  static const removedText = Color(0xFFFF5252);
  static const modifiedText = Color(0xFF00B8E6);
  static const unchangedText = Color(0xFFB8BFC9);

  static const addedWordHighlight = Color(0x4D4AFF9F); // rgba(74,255,159,0.3)
  static const removedWordHighlight = Color(0x4DFF5252); // rgba(255,82,82,0.3)

  static const lineNumberBackground = Color(0xFF0A0E1A);
  static const lineNumberText = Color(0xFF7A8599);
  static const lineNumberBorder = Color(0xFF1F2937);

  static const markerAddedBackground = Color(0x334AFF9F); // rgba(74,255,159,0.2)
  static const markerRemovedBackground = Color(0x33FF5252); // rgba(255,82,82,0.2)
  static const markerModifiedBackground = Color(0x3300B8E6); // rgba(0,184,230,0.2)
  static const markerText = Color(0xFF7A8599);
}
