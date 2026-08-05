import 'package:flutter/widgets.dart';

/// Host-to-modal visibility channel for minimized tools — the Flutter analog
/// of the RN AppHost's `visible` prop (`AppRenderer` passes `!app.minimized`
/// into each self-modal tool).
///
/// The host wraps each open tool's subtree in [BuoyModalVisibility] and flips
/// [visible] when the tool is minimized/restored. [JsModal] reads it via
/// [of] and hides itself while staying MOUNTED, so tool state (scroll
/// positions, filters, live subscriptions) survives minimize — RN parity,
/// where minimized tools keep rendering offscreen.
///
/// This must be an InheritedWidget rather than a host-side `Offstage`:
/// JsModal's root is `Positioned.fill`, and inserting a render-object widget
/// between the host Stack and that `Positioned` would break the ParentData
/// chain. The hide has to happen inside JsModal, below its own Positioned.
///
/// Defaults to visible when absent, so a JsModal outside the app-host stack
/// (e.g. the settings sheet) needs no wrapper.
class BuoyModalVisibility extends InheritedWidget {
  const BuoyModalVisibility({
    super.key,
    required this.visible,
    required super.child,
  });

  final bool visible;

  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<BuoyModalVisibility>()
          ?.visible ??
      true;

  @override
  bool updateShouldNotify(BuoyModalVisibility oldWidget) =>
      visible != oldWidget.visible;
}
