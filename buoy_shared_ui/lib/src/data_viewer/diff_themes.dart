/// Ports packages/shared/src/dataViewer/diffThemes.ts — theme definitions for
/// the [SplitDiffViewer]. Both the light "Git Classic" and dark "Dev Tools
/// Default" (Buoy brand) themes, captured hex-for-hex.
library;

import 'package:flutter/widgets.dart';

/// RN `DiffTheme` — the full color set the split diff renders with.
class DiffTheme {
  const DiffTheme({
    required this.name,
    required this.description,
    required this.background,
    required this.panelBackground,
    required this.headerBackground,
    required this.addedBackground,
    required this.removedBackground,
    required this.modifiedBackground,
    required this.unchangedBackground,
    required this.contextBackground,
    required this.addedText,
    required this.removedText,
    required this.modifiedText,
    required this.unchangedText,
    required this.addedWordHighlight,
    required this.removedWordHighlight,
    required this.lineNumberBackground,
    required this.lineNumberText,
    required this.lineNumberBorder,
    required this.markerAddedBackground,
    required this.markerRemovedBackground,
    required this.markerModifiedBackground,
    required this.markerText,
    required this.borderColor,
    required this.dividerColor,
    required this.summaryBackground,
    required this.summaryAddedText,
    required this.summaryRemovedText,
    required this.summaryModifiedText,
    required this.emptyStateText,
    required this.separatorBackground,
    required this.separatorText,
    this.accentColor,
  });

  final String name;
  final String description;
  final Color background;
  final Color panelBackground;
  final Color headerBackground;
  final Color addedBackground;
  final Color removedBackground;
  final Color modifiedBackground;
  final Color unchangedBackground;
  final Color contextBackground;
  final Color addedText;
  final Color removedText;
  final Color modifiedText;
  final Color unchangedText;
  final Color addedWordHighlight;
  final Color removedWordHighlight;
  final Color lineNumberBackground;
  final Color lineNumberText;
  final Color lineNumberBorder;
  final Color markerAddedBackground;
  final Color markerRemovedBackground;
  final Color markerModifiedBackground;
  final Color markerText;
  final Color borderColor;
  final Color dividerColor;
  final Color summaryBackground;
  final Color summaryAddedText;
  final Color summaryRemovedText;
  final Color summaryModifiedText;
  final Color emptyStateText;
  final Color separatorBackground;
  final Color separatorText;
  final Color? accentColor;
}

/// Git Classic — traditional light Git diff colors.
const gitClassicTheme = DiffTheme(
  name: 'Git Classic',
  description: 'Traditional Git diff colors - simple and familiar',
  background: Color(0xFFFFFFFF),
  panelBackground: Color(0xFFF8F8F8),
  headerBackground: Color(0xFFF0F0F0),
  addedBackground: Color(0xFFE6FFED),
  removedBackground: Color(0xFFFFEEF0),
  modifiedBackground: Color(0xFFFFF5DD),
  unchangedBackground: Color(0x00000000),
  contextBackground: Color(0xFFFAFAFA),
  addedText: Color(0xFF22863A),
  removedText: Color(0xFFCB2431),
  modifiedText: Color(0xFFB08800),
  unchangedText: Color(0xFF24292E),
  addedWordHighlight: Color(0xFFACF2BD),
  removedWordHighlight: Color(0xFFFDB8C0),
  lineNumberBackground: Color(0xFFF6F8FA),
  lineNumberText: Color(0xFF959DA5),
  lineNumberBorder: Color(0xFFE1E4E8),
  markerAddedBackground: Color(0xFFCDFFD8),
  markerRemovedBackground: Color(0xFFFFDCE0),
  markerModifiedBackground: Color(0xFFFFF5B1),
  markerText: Color(0xFF666666),
  borderColor: Color(0xFFE1E4E8),
  dividerColor: Color(0xFFE1E4E8),
  summaryBackground: Color(0xFFF6F8FA),
  summaryAddedText: Color(0xFF28A745),
  summaryRemovedText: Color(0xFFD73A49),
  summaryModifiedText: Color(0xFF0366D6),
  emptyStateText: Color(0xFF586069),
  separatorBackground: Color(0xFFF6F8FA),
  separatorText: Color(0xFF586069),
);

/// Dev Tools Default — dark theme in Buoy brand colors (added teal, removed red,
/// modified purple). The default theme the state tools' diff uses.
const devToolsDefaultTheme = DiffTheme(
  name: 'Dev Tools Default',
  description: 'Clean dark theme with Buoy brand colors',
  background: Color(0xFF121212),
  panelBackground: Color(0xFF1A1A1A),
  headerBackground: Color(0xFF1A1A1A),
  addedBackground: Color(0x1F20C997), // rgba(32,201,151,0.12)
  removedBackground: Color(0x1FEF4444), // rgba(239,68,68,0.12)
  modifiedBackground: Color(0x1F9B70E0), // rgba(155,112,224,0.12)
  unchangedBackground: Color(0x00000000),
  contextBackground: Color(0x05FFFFFF), // rgba(255,255,255,0.02)
  addedText: Color(0xFF20C997),
  removedText: Color(0xFFEF4444),
  modifiedText: Color(0xFF9B70E0),
  unchangedText: Color(0xFFE0E0E0),
  addedWordHighlight: Color(0x4D20C997), // rgba(32,201,151,0.3)
  removedWordHighlight: Color(0x4DEF4444), // rgba(239,68,68,0.3)
  lineNumberBackground: Color(0xFF121212),
  lineNumberText: Color(0xFFA0A0A0),
  lineNumberBorder: Color(0xFF333333),
  markerAddedBackground: Color(0x3320C997), // rgba(32,201,151,0.2)
  markerRemovedBackground: Color(0x33EF4444), // rgba(239,68,68,0.2)
  markerModifiedBackground: Color(0x339B70E0), // rgba(155,112,224,0.2)
  markerText: Color(0xFFA0A0A0),
  borderColor: Color(0xFF333333),
  dividerColor: Color(0xFF333333),
  summaryBackground: Color(0xFF1A1A1A),
  summaryAddedText: Color(0xFF20C997),
  summaryRemovedText: Color(0xFFEF4444),
  summaryModifiedText: Color(0xFF9B70E0),
  emptyStateText: Color(0xFF888888),
  separatorBackground: Color(0xFF1A1A1A),
  separatorText: Color(0xFFA0A0A0),
);

/// RN `diffThemes` collection.
const diffThemes = {
  'gitClassic': gitClassicTheme,
  'devToolsDefault': devToolsDefaultTheme,
};
