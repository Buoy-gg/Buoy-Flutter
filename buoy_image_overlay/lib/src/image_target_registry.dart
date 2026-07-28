/// Ports packages/image-overlay/src/imageOverlay/utils/fiberScanner.ts +
/// componentMeasurement.ts.
///
/// RN scans the React fiber tree for host components tagged
/// `testID="image-target:Label"` and measures them via the Fabric/Paper
/// measure APIs. Flutter has no equivalent runtime tree scan by test id, so the
/// idiomatic analog (mirroring how the impersonate tool takes app-supplied
/// identities) is an explicit widget: wrap a subtree in [BuoyImageTarget] and it
/// registers a `GlobalKey` + label into a static registry. [scanForImageTargets]
/// returns those live entries; [measureTarget] measures the key's `RenderBox`
/// in global (screen) coordinates — the same space RN's `pageX/pageY` use.
library;

import 'package:flutter/widgets.dart';

import 'image_overlay_types.dart';

/// RN `IMAGE_TARGET_PREFIX`. Kept so a target's synthetic `testID` reads the
/// same as the RN `testID="image-target:Label"` convention.
const String kImageTargetPrefix = 'image-target:';

/// The live set of registered targets, keyed by label (last registration for a
/// label wins — mirrors RN where the last matching fiber for a label is used).
final Map<String, _RegisteredTarget> _targets = <String, _RegisteredTarget>{};

class _RegisteredTarget {
  _RegisteredTarget(this.label, this.key, this.componentName);
  final String label;
  final GlobalKey key;
  final String? componentName;
}

/// Wrap any widget so the image-overlay tool's **Component Match** mode can
/// discover and measure it. The [label] appears in the tool's target list; the
/// overlay image is drawn onto this widget's measured rect.
///
/// ```dart
/// BuoyImageTarget(
///   label: 'ProfileCard',
///   child: ProfileCard(),
/// )
/// ```
class BuoyImageTarget extends StatefulWidget {
  const BuoyImageTarget({
    super.key,
    required this.label,
    required this.child,
    this.componentName,
  });

  /// The human label shown in the target list (RN's part after
  /// `image-target:`).
  final String label;

  /// Optional owning-component name shown as a hint in the target row (RN
  /// derives this from the fiber's owner).
  final String? componentName;

  final Widget child;

  @override
  State<BuoyImageTarget> createState() => _BuoyImageTargetState();
}

class _BuoyImageTargetState extends State<BuoyImageTarget> {
  final GlobalKey _key = GlobalKey();

  @override
  void initState() {
    super.initState();
    _register();
  }

  @override
  void didUpdateWidget(BuoyImageTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.label != widget.label) {
      // Drop the old label if it still points at us, then re-register.
      final existing = _targets[oldWidget.label];
      if (existing != null && existing.key == _key) {
        _targets.remove(oldWidget.label);
      }
      _register();
    }
  }

  void _register() {
    _targets[widget.label] =
        _RegisteredTarget(widget.label, _key, widget.componentName);
  }

  @override
  void dispose() {
    final existing = _targets[widget.label];
    if (existing != null && existing.key == _key) {
      _targets.remove(widget.label);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // KeyedSubtree gives the child a stable RenderObject we can measure without
    // altering layout.
    return KeyedSubtree(key: _key, child: widget.child);
  }
}

/// RN `scanForImageTargets()`. Returns every currently-registered
/// [BuoyImageTarget], sorted by label for a stable list order.
List<DiscoveredTarget> scanForImageTargets() {
  final entries = _targets.values.toList()
    ..sort((a, b) => a.label.compareTo(b.label));
  return [
    for (final t in entries)
      DiscoveredTarget(
        label: t.label,
        testID: '$kImageTargetPrefix${t.label}',
        key: t.key,
        componentName: t.componentName,
      ),
  ];
}

/// RN `measureInstance()` — measures a target's on-screen rect. Returns `null`
/// if the widget is unmounted or has no size yet.
MeasuredRect? measureTarget(GlobalKey key) {
  final context = key.currentContext;
  if (context == null) return null;
  final object = context.findRenderObject();
  if (object is! RenderBox || !object.hasSize) return null;
  final size = object.size;
  if (size.width <= 0 || size.height <= 0) return null;
  final origin = object.localToGlobal(Offset.zero);
  return MeasuredRect(
    x: origin.dx,
    y: origin.dy,
    width: size.width,
    height: size.height,
  );
}

/// Test-only: clear the registry between unit tests.
@visibleForTesting
void debugClearImageTargets() => _targets.clear();

/// Test-only: register a target without mounting a widget.
@visibleForTesting
void debugRegisterImageTarget(String label, GlobalKey key,
        {String? componentName}) =>
    _targets[label] = _RegisteredTarget(label, key, componentName);
