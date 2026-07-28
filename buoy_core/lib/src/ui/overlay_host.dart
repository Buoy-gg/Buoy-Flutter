import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// A tiny, generic registry of full-screen overlay builders that
/// [BuoyDevTools] renders in its Stack, **above the app child but below the
/// open tool / floating bubble / dial**.
///
/// This is the Flutter analog of the RN `FloatingDevTools` "standalone overlay"
/// slot — where tools like `image-overlay` (its overlay image), `impersonate`
/// (its floating banner), `debug-borders`, and `highlight-updates` mount a
/// layer that draws OVER the running app but OUTSIDE their control modal.
///
/// A tool registers a [WidgetBuilder] once (usually from its `register…()`
/// entry point) and gets back an unregister closure:
///
/// ```dart
/// final remove = BuoyOverlayHost.instance.register(
///   (context) => const MyToolStandaloneOverlay(),
/// );
/// // …later, if the tool is torn down:
/// remove();
/// ```
///
/// The host is intentionally minimal: it holds no per-tool state and imposes no
/// layout. Each registered builder must return a widget that positions its own
/// content (e.g. a `Positioned.fill` wrapping a `Stack`) and pass touches
/// through on empty regions (no opaque background) so the app underneath stays
/// interactive — the Flutter equivalent of RN's `pointerEvents="box-none"`.
class BuoyOverlayHost {
  BuoyOverlayHost._();

  /// The process-wide overlay host. One [BuoyDevTools] observes it.
  static final BuoyOverlayHost instance = BuoyOverlayHost._();

  final ValueNotifier<List<WidgetBuilder>> _builders =
      ValueNotifier<List<WidgetBuilder>>(const []);

  /// The current registered builders — [BuoyDevTools] rebuilds its overlay
  /// layer whenever this changes.
  ValueListenable<List<WidgetBuilder>> get listenable => _builders;

  /// Register a full-screen overlay [builder]. Returns a closure that removes
  /// it again. Safe to call before [BuoyDevTools] mounts (the layer picks it
  /// up on first build). Registering the same builder twice stacks it twice —
  /// callers that must be idempotent should guard with their own flag (see
  /// `registerBuoyImageOverlay`).
  VoidCallback register(WidgetBuilder builder) {
    _builders.value = <WidgetBuilder>[..._builders.value, builder];
    return () {
      if (!_builders.value.contains(builder)) return;
      _builders.value =
          _builders.value.where((b) => b != builder).toList(growable: false);
    };
  }
}
