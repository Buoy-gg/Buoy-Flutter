import 'buoy_icon_data.dart';
import 'generated/buoy_icon_data.g.dart';

/// The icon type shared-ui widgets accept.
///
/// In the RN source these props are typed `LucideIcon` (a component); here they
/// are [BuoyIconData] from the cross-framework icon format, so the widget
/// signatures still read the same as their RN originals — and now render the
/// same artwork.
typedef LucideIcon = BuoyIconData;

/// The ~44 lucide UI glyphs Buoy uses, drawn from the Buoy Icon Format.
///
/// These were Material glyph substitutes until the lucide tier was ported;
/// Material's filled/rounded geometry never matched lucide's 2px round-capped
/// stroke, which is why the Flutter build looked different from React Native.
/// The artwork now lives in `shared/icons/glyphs/*.json` and is generated into
/// both frameworks — edit the JSON, then `pnpm icons`.
///
/// Render with [BuoyGlyph], the drop-in for Flutter's `Icon`:
///
/// ```dart
/// BuoyGlyph(BuoyIcons.filter, size: 14, color: macOSColors.text.secondary)
/// ```
class BuoyIcons {
  BuoyIcons._();

  static const LucideIcon filter = filterGlyph;

  /// The response-overrides mark. RN uses lucide's `FlaskConical` (a
  /// hand-written component in shared/src/icons); this is the same shape
  /// authored once in the BIF set so both frameworks draw it identically.
  static const LucideIcon flaskConical = flaskConicalGlyph;
  static const LucideIcon zap = zapGlyph;
  static const LucideIcon x = xGlyph;
  static const LucideIcon trash2 = trash2Glyph;
  static const LucideIcon search = searchGlyph;
  static const LucideIcon database = databaseGlyph;
  static const LucideIcon chevronDown = chevronDownGlyph;
  static const LucideIcon chevronUp = chevronUpGlyph;
  static const LucideIcon chevronRight = chevronRightGlyph;
  static const LucideIcon chevronLeft = chevronLeftGlyph;
  static const LucideIcon clock = clockGlyph;
  static const LucideIcon lock = lockGlyph;
  static const LucideIcon eye = eyeGlyph;
  static const LucideIcon eyeOff = eyeOffGlyph;
  static const LucideIcon fileText = fileTextGlyph;
  static const LucideIcon copy = copyGlyph;
  static const LucideIcon edit3 = edit3Glyph;
  static const LucideIcon hash = hashGlyph;
  static const LucideIcon box = boxGlyph;
  static const LucideIcon alertTriangle = alertTriangleGlyph;
  static const LucideIcon alertCircle = alertCircleGlyph;
  static const LucideIcon xCircle = xCircleGlyph;
  static const LucideIcon refreshCw = refreshCwGlyph;
  static const LucideIcon plus = plusGlyph;
  static const LucideIcon minus = minusGlyph;
  static const LucideIcon settings = settingsGlyph;
  static const LucideIcon key = keyGlyph;
  static const LucideIcon activity = activityGlyph;
  static const LucideIcon play = playGlyph;
  static const LucideIcon pause = pauseGlyph;
  static const LucideIcon layers = layersGlyph;
  static const LucideIcon check = checkGlyph;
  static const LucideIcon checkCircle = checkCircleGlyph;
  static const LucideIcon info = infoGlyph;
  static const LucideIcon power = powerGlyph;
  static const LucideIcon shield = shieldGlyph;
  static const LucideIcon globe = globeGlyph;
  static const LucideIcon wifi = wifiGlyph;
  static const LucideIcon server = serverGlyph;
  static const LucideIcon upload = uploadGlyph;
  static const LucideIcon download = downloadGlyph;
  static const LucideIcon link = linkGlyph;
  static const LucideIcon bug = bugGlyph;
  static const LucideIcon home = homeGlyph;
  static const LucideIcon user = userGlyph;

  // Added for Flutter call sites that were still reaching for a Material glyph.
  static const LucideIcon moreVertical = moreVerticalGlyph;
  static const LucideIcon barChart = barChartGlyph;

  static const LucideIcon arrowUp = arrowUpGlyph;
  static const LucideIcon arrowDown = arrowDownGlyph;
  static const LucideIcon image = imageGlyph;
  static const LucideIcon film = filmGlyph;
  static const LucideIcon music = musicGlyph;
  static const LucideIcon unlock = unlockGlyph;
  static const LucideIcon braces = bracesGlyph;

  static const LucideIcon code = codeGlyph;
  static const LucideIcon pin = pinGlyph;

  /// The saved-requests mark. RN uses lucide's `Bookmark`; authored once in
  /// the BIF set so both frameworks draw the same shape.
  static const LucideIcon bookmark = bookmarkGlyph;
  static const LucideIcon navigation = navigationGlyph;
  static const LucideIcon imageOff = imageOffGlyph;
  static const LucideIcon palette = paletteGlyph;
  static const LucideIcon gitBranch = gitBranchGlyph;
  static const LucideIcon gauge = gaugeGlyph;
  static const LucideIcon crop = cropGlyph;
  static const LucideIcon gripVertical = gripVerticalGlyph;
  static const LucideIcon circle = circleGlyph;
  static const LucideIcon arrowDownToLine = arrowDownToLineGlyph;
}
