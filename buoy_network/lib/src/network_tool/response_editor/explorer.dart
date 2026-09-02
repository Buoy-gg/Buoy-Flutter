/// Ports packages/network/src/network/components/response-editor/Explorer.tsx
/// — the response-body tree, where preview and editor are ONE surface.
///
/// The tree itself is buoy_shared_ui's [LiveExplorer] (RN hoisted the RQ
/// Explorer into shared-ui's `LiveExplorer` for the same reason; this file
/// was the Dart port of that ancestor and is now a thin wrapper). The only
/// thing that differs per host is where an edit LANDS: here it is
/// [ResponseEditorScope]'s `onChange`, which turns the rebuilt body into an
/// override rule.
library;

import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';

/// The RN `ResponseEditorContext`: the whole document plus one way to replace
/// it. Every edit rebuilds the root and hands it up.
class ResponseEditorScope extends InheritedWidget {
  const ResponseEditorScope({
    super.key,
    required this.root,
    required this.onChange,
    required super.child,
  });

  final Object? root;
  final ValueChanged<Object?> onChange;

  static ResponseEditorScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ResponseEditorScope>();

  @override
  bool updateShouldNotify(ResponseEditorScope oldWidget) =>
      !identical(oldWidget.root, root) || oldWidget.onChange != onChange;
}

/// One node of the tree. Kept as the response editor's public widget so its
/// callers and tests are untouched; delegates to [LiveExplorer] with a root
/// writer built from the enclosing [ResponseEditorScope].
class BuoyExplorer extends StatelessWidget {
  const BuoyExplorer({
    super.key,
    required this.label,
    required this.value,
    this.dataPath = const [],
    this.editable = false,
    this.itemsDeletable = false,
    this.defaultExpanded = const [],
  });

  final String label;
  final Object? value;
  final List<String> dataPath;
  final bool editable;

  /// This node sits inside a container, so it can be removed from it.
  final bool itemsDeletable;

  /// Labels that start expanded (RN's `defaultExpanded`).
  final List<String> defaultExpanded;

  @override
  Widget build(BuildContext context) {
    final scope = ResponseEditorScope.maybeOf(context);
    return LiveExplorer(
      label: label,
      value: value,
      dataPath: dataPath,
      editable: editable && scope != null,
      itemsDeletable: itemsDeletable,
      defaultExpanded: defaultExpanded,
      // A cache-style write: free and unlogged, so per keystroke (RN RQ).
      writer: scope == null
          ? null
          : RootWriter(getRoot: () => scope.root, setRoot: scope.onChange),
    );
  }
}
