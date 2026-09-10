import 'dart:ui' as ui;

/// RN's `StyleSheet.hairlineWidth`: the thinnest line the screen can draw —
/// one PHYSICAL pixel, expressed in logical pixels (0.333… on a 3× phone).
///
/// The generated style constants (`*_styles.g.dart`) reference this wherever
/// the RN source says `StyleSheet.hairlineWidth`, so a hairline border is the
/// same thickness on both frameworks.
double get hairlineWidth {
  final ui.FlutterView? view =
      ui.PlatformDispatcher.instance.implicitView ??
      (ui.PlatformDispatcher.instance.views.isEmpty
          ? null
          : ui.PlatformDispatcher.instance.views.first);
  return 1 / (view?.devicePixelRatio ?? 1);
}
