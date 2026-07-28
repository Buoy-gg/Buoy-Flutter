/// Ports packages/image-overlay/src/imageOverlay/components/ImageOverlayStandalone.tsx.
///
/// The full-screen overlay drawn OVER the running app (outside the control
/// modal). Auto-mounted via [BuoyOverlayHost] by `registerBuoyImageOverlay`.
/// Renders one of two things from [ImageOverlayController]:
/// - Component Match: a dashed teal highlight + label + the image centered on
///   the tracked widget's rect (opacity / scale / offset / flip).
/// - Free Placement: a draggable, aspect-locked-resizable image with corner
///   handles and a lock.
/// Empty regions pass touches through (no opaque background) — RN
/// `pointerEvents="box-none"`.
library;

import 'package:flutter/widgets.dart';

import 'image_overlay_controller.dart';
import 'image_overlay_types.dart';

// RN highlight/label/handle colors (ImageOverlayStandalone styles).
const Color _teal = Color(0xFF20C997);
const Color _tealActive = Color(0xFF10B981);
const Color _amber = Color(0xFFF59E0B);
const Color _white = Color(0xFFFFFFFF);

const double _freeMinSize = 30;

class ImageOverlayStandalone extends StatefulWidget {
  const ImageOverlayStandalone({super.key});

  @override
  State<ImageOverlayStandalone> createState() => _ImageOverlayStandaloneState();
}

class _ImageOverlayStandaloneState extends State<ImageOverlayStandalone> {
  final _controller = ImageOverlayController.instance;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChange);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final state = _controller.state;
    final provider = _controller.imageProvider;

    final aspectRatio = (state.imageWidth != null &&
            state.imageHeight != null &&
            state.imageHeight! > 0)
        ? state.imageWidth! / state.imageHeight!
        : 0.0;

    // ─── Free Placement Mode ───
    if (state.mode == OverlayMode.free &&
        state.enabled &&
        provider != null) {
      return Positioned.fill(
        child: Stack(
          children: [
            _FreePlacement(
              provider: provider,
              x: state.freeX,
              y: state.freeY,
              width: state.freeWidth,
              height: state.freeHeight,
              opacity: state.opacity,
              aspectRatio: aspectRatio,
              invertX: state.invertX,
              invertY: state.invertY,
              locked: state.locked,
            ),
          ],
        ),
      );
    }

    // ─── Component Match Mode ───
    final rect = state.targetRect;
    if (rect == null) return const SizedBox.shrink();

    final showImage = state.enabled && provider != null;

    return Positioned.fill(
      child: Stack(
        children: [
          if (state.showOutline) ...[
            // Dashed teal highlight (RN uses a dashed border; Flutter's default
            // Border has no dashed style, so we approximate with a solid 2px
            // teal box — same rect, -3 inset / +6 size).
            Positioned(
              left: rect.x - 3,
              top: rect.y - 3,
              width: rect.width + 6,
              height: rect.height + 6,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: _teal, width: 2),
                  ),
                ),
              ),
            ),
            if (state.targetLabel != null)
              Positioned(
                left: rect.x,
                top: rect.y - 20,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _teal,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      state.targetLabel!,
                      style: const TextStyle(
                        color: _white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
              ),
          ],
          if (showImage) _componentImage(state, provider),
        ],
      ),
    );
  }

  Widget _componentImage(ImageOverlayState state, ImageProvider provider) {
    final rect = state.targetRect!;
    final w = (state.imageWidth ?? rect.width) * state.scale;
    final h = (state.imageHeight ?? rect.height) * state.scale;
    final centerX = rect.x + rect.width / 2;
    final centerY = rect.y + rect.height / 2;
    return Positioned(
      left: centerX - w / 2 + state.offsetX,
      top: centerY - h / 2 + state.offsetY,
      width: w,
      height: h,
      child: IgnorePointer(
        child: Opacity(
          opacity: state.opacity,
          child: _OverlayImage(
            provider: provider,
            invertX: state.invertX,
            invertY: state.invertY,
          ),
        ),
      ),
    );
  }
}

/// RN `OverlayImage` — applies flip transforms.
class _OverlayImage extends StatelessWidget {
  const _OverlayImage({
    required this.provider,
    required this.invertX,
    required this.invertY,
  });

  final ImageProvider provider;
  final bool invertX;
  final bool invertY;

  @override
  Widget build(BuildContext context) {
    final image = Image(
      image: provider,
      fit: BoxFit.fill,
      width: double.infinity,
      height: double.infinity,
      gaplessPlayback: true,
    );
    if (!invertX && !invertY) return image;
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.diagonal3Values(
        invertX ? -1 : 1,
        invertY ? -1 : 1,
        1,
      ),
      child: image,
    );
  }
}

/// RN `FreePlacement` — draggable + aspect-ratio-locked corner resize.
class _FreePlacement extends StatefulWidget {
  const _FreePlacement({
    required this.provider,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.opacity,
    required this.aspectRatio,
    required this.invertX,
    required this.invertY,
    required this.locked,
  });

  final ImageProvider provider;
  final double x;
  final double y;
  final double width;
  final double height;
  final double opacity;
  final double aspectRatio;
  final bool invertX;
  final bool invertY;
  final bool locked;

  @override
  State<_FreePlacement> createState() => _FreePlacementState();
}

enum _Corner { topLeft, topRight, bottomLeft, bottomRight }

class _FreePlacementState extends State<_FreePlacement> {
  final _controller = ImageOverlayController.instance;
  bool _isInteracting = false;

  // Drag: start position captured on pan start.
  double _startX = 0;
  double _startY = 0;

  // Resize: start dims + accumulated total delta.
  _Rect _startDims = const _Rect(0, 0, 0, 0);
  Offset _totalDelta = Offset.zero;

  Size get _screen => MediaQuery.of(context).size;

  void _onDragStart(DragStartDetails _) {
    final s = _controller.state;
    _startX = s.freeX;
    _startY = s.freeY;
    _totalDelta = Offset.zero;
    setState(() => _isInteracting = true);
  }

  void _onDragUpdate(DragUpdateDetails d) {
    _totalDelta += d.delta;
    final s = _controller.state;
    final newX = (_startX + _totalDelta.dx)
        .clamp(0.0, _screen.width - s.freeWidth);
    final newY = (_startY + _totalDelta.dy)
        .clamp(0.0, _screen.height - s.freeHeight);
    _controller.setFreePosition(newX, newY);
  }

  void _onDragEnd(_) => setState(() => _isInteracting = false);

  void _onResizeStart(DragStartDetails _) {
    final s = _controller.state;
    _startDims = _Rect(s.freeX, s.freeY, s.freeWidth, s.freeHeight);
    _totalDelta = Offset.zero;
    setState(() => _isInteracting = true);
  }

  void _onResizeUpdate(_Corner corner, DragUpdateDetails d) {
    _totalDelta += d.delta;
    final dx = _totalDelta.dx;
    final dy = _totalDelta.dy;
    if (dx.abs() < 0.5 && dy.abs() < 0.5) return;

    final start = _startDims;
    final ratio = widget.aspectRatio > 0
        ? widget.aspectRatio
        : (start.height == 0 ? 1.0 : start.width / start.height);
    final useDx = dx.abs() >= dy.abs();

    double newWidth;
    double newHeight;
    var newX = start.x;
    var newY = start.y;

    switch (corner) {
      case _Corner.bottomRight:
        newWidth = useDx ? start.width + dx : (start.height + dy) * ratio;
        newWidth = newWidth
            .clamp(_freeMinSize, _screen.width - start.x)
            .toDouble();
        newHeight = newWidth / ratio;
      case _Corner.bottomLeft:
        newWidth = useDx ? start.width - dx : (start.height + dy) * ratio;
        newWidth = newWidth < _freeMinSize ? _freeMinSize : newWidth;
        newHeight = newWidth / ratio;
        newX = start.x + start.width - newWidth;
        newX = newX < 0 ? 0 : newX;
        newWidth = newWidth < (start.x + start.width)
            ? newWidth
            : (start.x + start.width);
        newHeight = newWidth / ratio;
      case _Corner.topRight:
        newWidth = useDx ? start.width + dx : (start.height - dy) * ratio;
        newWidth = newWidth
            .clamp(_freeMinSize, _screen.width - start.x)
            .toDouble();
        newHeight = newWidth / ratio;
        newY = start.y + start.height - newHeight;
        newY = newY < 0 ? 0 : newY;
        newHeight = newHeight < (start.y + start.height)
            ? newHeight
            : (start.y + start.height);
        newWidth = newHeight * ratio;
      case _Corner.topLeft:
        newWidth = useDx ? start.width - dx : (start.height - dy) * ratio;
        newWidth = newWidth < _freeMinSize ? _freeMinSize : newWidth;
        newHeight = newWidth / ratio;
        newX = start.x + start.width - newWidth;
        newY = start.y + start.height - newHeight;
        newX = newX < 0 ? 0 : newX;
        newY = newY < 0 ? 0 : newY;
        newWidth = newWidth < (start.x + start.width)
            ? newWidth
            : (start.x + start.width);
        newHeight = newWidth / ratio;
        newY = start.y + start.height - newHeight;
    }

    newWidth = (newWidth < _freeMinSize ? _freeMinSize : newWidth)
        .roundToDouble();
    newHeight = (newHeight < _freeMinSize ? _freeMinSize : newHeight)
        .roundToDouble();
    _controller.setFreeDimensions(
      newWidth,
      newHeight,
      newX.roundToDouble(),
      newY.roundToDouble(),
    );
  }

  void _onResizeEnd(_) => setState(() => _isInteracting = false);

  @override
  Widget build(BuildContext context) {
    final locked = widget.locked;
    Color borderColor;
    if (locked) {
      borderColor = _amber;
    } else if (_isInteracting) {
      borderColor = _teal;
    } else {
      borderColor = const Color(0x00000000);
    }

    return Positioned(
      left: widget.x,
      top: widget.y,
      width: widget.width,
      height: widget.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Draggable image (locked → not draggable).
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: locked ? null : _onDragStart,
              onPanUpdate: locked ? null : _onDragUpdate,
              onPanEnd: locked ? null : _onDragEnd,
              child: Opacity(
                opacity: widget.opacity,
                child: _OverlayImage(
                  provider: widget.provider,
                  invertX: widget.invertX,
                  invertY: widget.invertY,
                ),
              ),
            ),
          ),
          // Border (RN freeBorder: -6 inset, radius 4).
          Positioned(
            top: -6,
            left: -6,
            right: -6,
            bottom: -6,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: borderColor, width: 1),
                ),
              ),
            ),
          ),
          // Corner handles — hidden when locked.
          if (!locked) ...[
            _handle(_Corner.topLeft, top: -20, left: -20),
            _handle(_Corner.topRight, top: -20, right: -20),
            _handle(_Corner.bottomLeft, bottom: -20, left: -20),
            _handle(_Corner.bottomRight, bottom: -20, right: -20),
          ],
        ],
      ),
    );
  }

  Widget _handle(
    _Corner corner, {
    double? top,
    double? left,
    double? right,
    double? bottom,
  }) {
    return Positioned(
      top: top,
      left: left,
      right: right,
      bottom: bottom,
      width: 24,
      height: 24,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: _onResizeStart,
        onPanUpdate: (d) => _onResizeUpdate(corner, d),
        onPanEnd: _onResizeEnd,
        child: Center(
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isInteracting ? _tealActive : _teal,
              border: Border.all(color: _white, width: 2),
              boxShadow: _isInteracting
                  ? const [
                      BoxShadow(color: _tealActive, blurRadius: 6),
                    ]
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _Rect {
  const _Rect(this.x, this.y, this.width, this.height);
  final double x;
  final double y;
  final double width;
  final double height;
}
