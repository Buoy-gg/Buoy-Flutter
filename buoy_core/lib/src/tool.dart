import 'package:flutter/widgets.dart';

import 'storage.dart';

/// Builds a tool's own modal surface (a JsModal). Rendered directly in the
/// BuoyDevTools stack — the tool positions itself and calls [onClose] to
/// destroy it or [onMinimize] to hand it to the host's minimized dock (which
/// re-opens it, restoring geometry from persistence).
typedef BuoyToolModalBuilder =
    Widget Function(
      BuildContext context,
      BuoyStorage storage,
      VoidCallback onClose,
      VoidCallback onMinimize,
    );

/// A devtool registered in the floating menu — the Dart analog of the RN
/// package's `InstalledApp`. Dart has no runtime `require()`, so unlike RN's
/// auto-discovery, tools are always registered explicitly (same constraint as
/// the sync client's `tools:` map).
class BuoyTool {
  const BuoyTool({
    required this.id,
    required this.name,
    required this.color,
    required this.icon,
    this.description,
    this.screenBuilder,
    this.modalBuilder,
    this.onPressed,
  });

  /// Stable id; matches the RN tool-id union where the tool exists there
  /// (e.g. 'network').
  final String id;

  /// Short label shown under the dial icon (rendered uppercase).
  final String name;

  final Color color;
  final IconData icon;

  /// Short blurb shown in the settings modal's tool cards.
  final String? description;

  /// Modal-style tools: built full-screen by the menu's tool host.
  final WidgetBuilder? screenBuilder;

  /// JsModal-style tools: build their own draggable/resizable modal (takes
  /// precedence over [screenBuilder]).
  final BuoyToolModalBuilder? modalBuilder;

  /// Toggle-style tools: invoked directly, no screen opens.
  final void Function(BuildContext context)? onPressed;
}
