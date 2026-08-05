import 'package:flutter/material.dart';

/// RN TouchableOpacity: dims to [activeOpacity] instantly on press-down and
/// fades back on release. Responds on tap-up with no recognizer delay.
class TouchableOpacity extends StatefulWidget {
  const TouchableOpacity({
    super.key,
    required this.onTap,
    required this.child,
    this.onLongPress,
    this.activeOpacity = 0.2,
  });

  final VoidCallback? onTap;

  /// RN's `onLongPress`. Kept on the same widget rather than wrapping in
  /// another GestureDetector so the press-dim and the long-press belong to one
  /// recognizer and can't fight each other in the gesture arena.
  final VoidCallback? onLongPress;
  final Widget child;

  /// RN TouchableOpacity default is 0.2.
  final double activeOpacity;

  @override
  State<TouchableOpacity> createState() => _TouchableOpacityState();
}

class _TouchableOpacityState extends State<TouchableOpacity> {
  bool _pressed = false;

  void _setPressed(bool pressed) {
    if (_pressed != pressed) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    // The press dim is driven by RAW pointer events: gesture callbacks
    // (onTapDown) don't fire until the tap wins the arena — which, with
    // competing recognizers around (header drag/tap), is only at finger-up,
    // so the dim would never render.
    return Listener(
      onPointerDown: widget.onTap == null && widget.onLongPress == null
          ? null
          : (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedOpacity(
          opacity: _pressed ? widget.activeOpacity : 1,
          // Instant dim on press, quick fade back on release (RN feel).
          duration: Duration(milliseconds: _pressed ? 0 : 150),
          child: widget.child,
        ),
      ),
    );
  }
}
