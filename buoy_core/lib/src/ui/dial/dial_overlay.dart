import 'dart:async';
import '../../icons/buoy_icon_painter.dart';
import '../../icons/buoy_icons.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../../core/dial_math.dart';
import '../../storage.dart';
import '../../tool.dart';
import '../buoy_theme.dart';
import '../settings/settings_sheet.dart';

/// The exact cubic beziers the RN dial ships for its easings
/// (`dialCSSBeziers.easeOutCubic` / `easeInCubic`) and the press spring
/// approximation (damping 15 / stiffness 400).
const _easeOutCubic = Cubic(0.33, 1, 0.68, 1);
const _easeInCubic = Cubic(0.32, 0, 0.67, 0);
const _pressCurve = Cubic(0.22, 1.2, 0.36, 1);

/// RN spring params (Animated.spring): dial scale 15/150, center button
/// 10/200, icon-select pulse 15/500 then 10/200. Mass 1 throughout.
const _dialSpring = SpringDescription(mass: 1, stiffness: 150, damping: 15);
const _centerSpring = SpringDescription(mass: 1, stiffness: 200, damping: 10);
const _pulseInSpring = SpringDescription(mass: 1, stiffness: 500, damping: 15);

const _teal = BuoyTheme.teal;

/// The radial dial menu — 1:1 port of the RN `DialDevTools` + `DialIcon`,
/// including the animation graph: independent parallel entrance animations
/// (backdrop timing, dial spring, rotation, delayed center spring, delayed
/// icon tween) and the staged exit sequence (icons → center+dial → backdrop).
///
/// Deviations: no settings modal yet (center button closes the dial) and the
/// continuous pulse is removed by request.
class DialOverlay extends StatefulWidget {
  const DialOverlay({
    super.key,
    required this.tools,
    required this.storage,
    required this.onLaunch,
    required this.onDismissed,
  });

  final List<BuoyTool> tools;
  final BuoyStorage storage;
  final void Function(BuoyTool tool) onLaunch;

  /// Called after the exit sequence finishes; the parent unmounts then.
  final VoidCallback onDismissed;

  @override
  State<DialOverlay> createState() => _DialOverlayState();
}

class _DialOverlayState extends State<DialOverlay>
    with TickerProviderStateMixin {
  // Independent values, mirroring the RN Animated.Values. The spring-driven
  // ones are unbounded so overshoot works.
  late final AnimationController _backdrop;
  late final AnimationController _dialScale;
  late final AnimationController _rotation;
  late final AnimationController _centerScale;
  late final AnimationController _iconsProgress;

  final List<Timer> _entranceTimers = [];
  bool _closing = false;
  int _page = 0;
  bool _settingsOpen = false;

  @override
  void initState() {
    super.initState();
    _backdrop = AnimationController(vsync: this);
    _dialScale = AnimationController.unbounded(vsync: this);
    _rotation = AnimationController(vsync: this);
    _centerScale = AnimationController.unbounded(vsync: this);
    _iconsProgress = AnimationController(vsync: this);

    // Entrance — all started in parallel like the RN effect:
    // backdrop: timing 400ms (RN default easing = inOut ease).
    _backdrop.animateTo(
      1,
      duration: const Duration(milliseconds: DialAnimation.backdropInMs),
      curve: Curves.easeInOut,
    );
    // dial: physics spring to 1.
    _dialScale.animateWith(SpringSimulation(_dialSpring, 0, 1, 0));
    // rotation: 0→360° over 800ms easeOutCubic (RN then snaps the value to
    // 0, which is visually identical).
    _rotation.animateTo(
      1,
      duration: const Duration(milliseconds: DialAnimation.rotationMs),
      curve: _easeOutCubic,
    );
    // center button: 300ms delay, then spring.
    _entranceTimers.add(
      Timer(
        const Duration(milliseconds: DialAnimation.centerButtonDelayMs),
        () {
          if (!mounted || _closing) return;
          _centerScale.animateWith(
            SpringSimulation(_centerSpring, _centerScale.value, 1, 0),
          );
        },
      ),
    );
    // icons: 500ms delay, then 600ms easeOutCubic.
    _entranceTimers.add(
      Timer(const Duration(milliseconds: DialAnimation.iconsDelayMs), () {
        if (!mounted || _closing) return;
        _iconsProgress.animateTo(
          1,
          duration: const Duration(milliseconds: DialAnimation.iconsInMs),
          curve: _easeOutCubic,
        );
      }),
    );

    // RN persists the settings modal's open state and restores it with the
    // dial.
    widget.storage.loadSettingsOpen().then((open) {
      if (mounted && open && !_closing) {
        setState(() => _settingsOpen = true);
      }
    });
  }

  void _toggleSettings() {
    if (_closing) return;
    setState(() => _settingsOpen = !_settingsOpen);
    widget.storage.saveSettingsOpen(_settingsOpen);
  }

  void _cancelEntranceTimers() {
    for (final timer in _entranceTimers) {
      timer.cancel();
    }
    _entranceTimers.clear();
  }

  /// RN handleClose: icons collapse → (center button ∥ dial) scale down →
  /// backdrop fades → dismiss.
  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    _cancelEntranceTimers();

    await _iconsProgress.animateTo(
      0,
      duration: const Duration(milliseconds: DialAnimation.iconsOutMs),
      curve: _easeInCubic,
    );
    if (!mounted) return;
    await Future.wait([
      _centerScale.animateTo(
        0,
        duration: const Duration(milliseconds: 200),
        curve: _easeInCubic,
      ),
      _dialScale.animateTo(
        0,
        duration: const Duration(milliseconds: DialAnimation.dialScaleOutMs),
        curve: _easeInCubic,
      ),
    ]);
    if (!mounted) return;
    await _backdrop.animateTo(
      0,
      duration: const Duration(milliseconds: DialAnimation.backdropOutMs),
      curve: Curves.easeInOut,
    );
    if (!mounted) return;
    widget.onDismissed();
  }

  /// RN handleIconPress: pulse the center button (spring 0.9 → 1), then after
  /// the 50ms action delay launch the tool and run the close sequence.
  void _handleIconTap(BuoyTool tool) {
    if (_closing) return;
    _pulseCenterButton();
    Timer(const Duration(milliseconds: 50), () {
      if (!mounted) return;
      widget.onLaunch(tool);
      _close();
    });
  }

  Future<void> _pulseCenterButton() async {
    await _centerScale.animateWith(
      SpringSimulation(_pulseInSpring, _centerScale.value, 0.9, 0),
    );
    if (!mounted || _closing) return;
    await _centerScale.animateWith(
      SpringSimulation(_centerSpring, _centerScale.value, 1, 0),
    );
  }

  @override
  void dispose() {
    _cancelEntranceTimers();
    _backdrop.dispose();
    _dialScale.dispose();
    _rotation.dispose();
    _centerScale.dispose();
    _iconsProgress.dispose();
    super.dispose();
  }

  int get _pageCount =>
      math.max(1, (widget.tools.length / maxDialSlots).ceil());

  void _goToPage(int page) {
    setState(() => _page = page.clamp(0, _pageCount - 1));
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final layout = getDialLayout(screen.width);
    final circleSize = layout.circleSize;
    final left = (screen.width - circleSize) / 2;

    return Positioned.fill(
      // Transparent Material: no Scaffold above this layer, and bare Text
      // would get the yellow-underline debug fallback.
      child: Material(
        type: MaterialType.transparency,
        child: AnimatedBuilder(
          animation: Listenable.merge([
            _backdrop,
            _dialScale,
            _rotation,
            _centerScale,
            _iconsProgress,
          ]),
          builder: (context, _) {
            final dialScale = _dialScale.value;
            return Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    onTap: _close,
                    child: Opacity(
                      opacity: _backdrop.value.clamp(0.0, 1.0),
                      child: const ColoredBox(color: BuoyTheme.dialBackdrop),
                    ),
                  ),
                ),
                // RN: absolute, left centered, bottom: 80. The whole parent
                // (circle + icons + center button) scales and rotates.
                Positioned(
                  left: left,
                  bottom: 80,
                  width: circleSize,
                  height: circleSize,
                  child: Transform.scale(
                    scale: dialScale,
                    child: Transform.rotate(
                      angle: _rotation.value * 2 * math.pi,
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: [
                          _CircleBackground(circleSize: circleSize),
                          for (var i = 0; i < maxDialSlots; i++)
                            _slot(i, layout),
                          Transform.scale(
                            scale: _centerScale.value.clamp(0.0, 2.0),
                            child: _CenterButton(
                              settingsOpen: _settingsOpen,
                              onTap: _toggleSettings,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // RN: pager only when tools span pages, 16px below the
                // circle's bottom edge, at the circle's width, tracking the
                // dial's scale.
                if (_pageCount > 1)
                  Positioned(
                    left: left,
                    top: screen.height - 80 + 16,
                    width: circleSize,
                    child: Opacity(
                      opacity: dialScale.clamp(0.0, 1.0),
                      child: Transform.scale(
                        scale: dialScale,
                        child: _PaginationBar(
                          page: _page,
                          pageCount: _pageCount,
                          onPrev: _page > 0 ? () => _goToPage(_page - 1) : null,
                          onNext: _page < _pageCount - 1
                              ? () => _goToPage(_page + 1)
                              : null,
                        ),
                      ),
                    ),
                  ),
                if (_settingsOpen)
                  SettingsSheet(
                    storage: widget.storage,
                    tools: widget.tools,
                    onClose: _toggleSettings,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _slot(int index, DialLayout layout) {
    // RN's DialIcon "spiral" degenerates to straight radial motion: the trig
    // interpolations run between equal endpoints (cos θ → cos(θ+2π)), so the
    // real device animation is translate = progress × finalPosition with
    // scale = opacity = progress. Ported as-is for 1:1 feel (the true spiral
    // in core/dial_math.dart is what the web build uses).
    final progress = getStaggeredIconProgress(
      _iconsProgress.value,
      index,
      maxDialSlots,
    );
    final pos = getIconPosition(index, maxDialSlots, layout.iconRadius);
    final toolIndex = _page * maxDialSlots + index;
    final tool = toolIndex < widget.tools.length
        ? widget.tools[toolIndex]
        : null;

    return Transform.translate(
      offset: Offset(pos.x * progress, pos.y * progress),
      child: Opacity(
        opacity: progress.clamp(0.0, 1.0),
        child: Transform.scale(
          scale: progress,
          child: tool != null
              ? _ToolIcon(
                  tool: tool,
                  size: layout.iconSize,
                  onTap: () => _handleIconTap(tool),
                )
              : const _EmptySlotDot(),
        ),
      ),
    );
  }
}

/// The dial disc — RN `styles.circle` + `gradientBackground` + the three
/// offset teal wash layers + grid lines. Layer alphas are the RN hex alphas
/// (0x10/0x08/0x15) pre-multiplied by each layer's opacity (0.6/0.4/0.3).
class _CircleBackground extends StatelessWidget {
  const _CircleBackground({required this.circleSize});

  final double circleSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: circleSize,
      height: circleSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: _teal.withValues(alpha: 0x40 / 255)),
        boxShadow: [
          BoxShadow(color: _teal.withValues(alpha: 0.5), blurRadius: 20),
        ],
      ),
      child: ClipOval(
        child: Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: Colors.black)),
            Positioned.fill(
              child: ColoredBox(
                color: _teal.withValues(alpha: (0x10 / 255) * 0.6),
              ),
            ),
            Positioned(
              left: circleSize * 0.3,
              top: circleSize * 0.3,
              right: 0,
              bottom: 0,
              child: ColoredBox(
                color: _teal.withValues(alpha: (0x08 / 255) * 0.4),
              ),
            ),
            Positioned(
              left: circleSize * 0.5,
              top: circleSize * 0.5,
              right: 0,
              bottom: 0,
              child: ColoredBox(
                color: _teal.withValues(alpha: (0x15 / 255) * 0.3),
              ),
            ),
            Positioned.fill(child: CustomPaint(painter: _GridPainter())),
          ],
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  /// RN draws full-diameter lines that the opaque 120px center stack covers;
  /// starting the spokes at that disc's edge is visually identical and keeps
  /// them clear of the center button.
  static const _innerRadius = dialButtonSize * 1.5 / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final paint = Paint()
      ..color = _teal.withValues(alpha: 0x26 / 255)
      ..strokeWidth = 1;
    for (final degrees in getGridLineRotations()) {
      final rad = degrees * math.pi / 180;
      final dir = Offset(math.cos(rad), math.sin(rad));
      canvas.drawLine(
        center + dir * _innerRadius,
        center + dir * radius,
        paint,
      );
      canvas.drawLine(
        center - dir * _innerRadius,
        center - dir * radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) => false;
}

/// RN center stack: 120px gradient disc (BUTTON_SIZE×1.5, black + teal
/// washes) → 96px bordered disc (×1.2, grid-line tint bg, 2px teal border) →
/// 80px button with glowing white BUOY text.
class _CenterButton extends StatelessWidget {
  const _CenterButton({required this.settingsOpen, required this.onTap});

  /// When the settings sheet is open the label reads CLOSE / SETTINGS (RN
  /// closeTextTop/Bottom).
  final bool settingsOpen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const outer = dialButtonSize * 1.5; // 120
    const ring = dialButtonSize * 1.2; // 96
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: outer,
        height: outer,
        child: ClipOval(
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Positioned.fill(child: ColoredBox(color: Colors.black)),
              Positioned.fill(
                child: ColoredBox(
                  color: _teal.withValues(alpha: (0x10 / 255) * 0.5),
                ),
              ),
              Positioned(
                left: outer * 0.2,
                top: outer * 0.2,
                right: 0,
                bottom: 0,
                child: ColoredBox(
                  color: _teal.withValues(alpha: (0x08 / 255) * 0.3),
                ),
              ),
              Positioned(
                left: outer * 0.4,
                top: outer * 0.4,
                right: 0,
                bottom: 0,
                child: ColoredBox(
                  color: _teal.withValues(alpha: (0x15 / 255) * 0.2),
                ),
              ),
              Container(
                width: ring,
                height: ring,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _teal.withValues(alpha: 0x26 / 255),
                  borderRadius: BorderRadius.circular(dialButtonSize * 0.6),
                  border: Border.all(
                    color: _teal.withValues(alpha: 0x40 / 255),
                    width: 2,
                  ),
                ),
                child: SizedBox(
                  width: dialButtonSize,
                  height: dialButtonSize,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final line
                            in settingsOpen
                                ? const ['CLOSE', 'SETTINGS']
                                : const ['BUOY'])
                          Text(
                            line,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                              fontFamily: 'monospace',
                              color: Colors.white,
                              height: 1.2,
                              shadows: [Shadow(color: _teal, blurRadius: 4)],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// RN `DialIcon`: 60px slot, icon rendered at 32, 6px gap (wrapper
/// marginBottom 4 + label marginTop 2), 8px w900 mono label in #E0E0E0 that
/// shrinks to fit, 0.95 press spring. The RN gradient/glow layers are
/// near-invisible washes and are omitted.
class _ToolIcon extends StatefulWidget {
  const _ToolIcon({
    required this.tool,
    required this.size,
    required this.onTap,
  });

  final BuoyTool tool;
  final double size;
  final VoidCallback onTap;

  @override
  State<_ToolIcon> createState() => _ToolIconState();
}

class _ToolIconState extends State<_ToolIcon> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1,
        duration: const Duration(milliseconds: 120),
        curve: _pressCurve,
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              widget.tool.icon(32, widget.tool.color),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  widget.tool.name.toUpperCase(),
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.3,
                    fontFamily: 'monospace',
                    color: BuoyTheme.secondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// RN empty slot: 12px dot, muted 0x15 fill, 1px muted 0x50 border.
class _EmptySlotDot extends StatelessWidget {
  const _EmptySlotDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: BuoyTheme.muted.withValues(alpha: 0x15 / 255),
        border: Border.all(
          color: BuoyTheme.muted.withValues(alpha: 0x50 / 255),
        ),
      ),
    );
  }
}

/// PREV · 01 / 03 · NEXT — 1:1 port of the RN `DialPagination` styles,
/// space-between across the dial's width.
class _PaginationBar extends StatelessWidget {
  const _PaginationBar({
    required this.page,
    required this.pageCount,
    required this.onPrev,
    required this.onNext,
  });

  final int page;
  final int pageCount;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  String _pad(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _PageButton(
          label: 'PREV',
          chevron: BuoyIcons.chevronLeft,
          chevronLeading: true,
          onTap: onPrev,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text.rich(
            TextSpan(
              // Current page glows; "/ total" is dim with no glow.
              text: _pad(page + 1),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
                fontFamily: 'monospace',
                color: Colors.white,
                shadows: [Shadow(color: _teal, blurRadius: 6)],
              ),
              children: [
                TextSpan(
                  text: ' / ${_pad(pageCount)}',
                  style: const TextStyle(
                    color: BuoyTheme.secondary,
                    shadows: [],
                  ),
                ),
              ],
            ),
          ),
        ),
        _PageButton(
          label: 'NEXT',
          chevron: BuoyIcons.chevronRight,
          chevronLeading: false,
          onTap: onNext,
        ),
      ],
    );
  }
}

class _PageButton extends StatefulWidget {
  const _PageButton({
    required this.label,
    required this.chevron,
    required this.chevronLeading,
    required this.onTap,
  });

  final String label;
  final LucideIcon chevron;
  final bool chevronLeading;
  final VoidCallback? onTap;

  @override
  State<_PageButton> createState() => _PageButtonState();
}

class _PageButtonState extends State<_PageButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    // Disabled accent = dialColors.emptyDotBorder (muted @ 0x50 alpha).
    final accent = enabled
        ? _teal
        : BuoyTheme.muted.withValues(alpha: 0x50 / 255);
    final text = Text(
      widget.label,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.5,
        fontFamily: 'monospace',
        color: accent,
        shadows: enabled
            ? const [Shadow(color: _teal, blurRadius: 4)]
            : const [],
      ),
    );
    final icon = BuoyGlyph(widget.chevron, size: 18, color: accent);
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        // RN presses spring to 0.92 (damping 15 / stiffness 400).
        scale: _pressed ? 0.92 : 1,
        duration: const Duration(milliseconds: 120),
        curve: _pressCurve,
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _teal.withValues(alpha: 0x40 / 255)),
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: _teal.withValues(alpha: 0.4),
                        blurRadius: 8,
                      ),
                    ]
                  : const [],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 4,
              children: widget.chevronLeading ? [icon, text] : [text, icon],
            ),
          ),
        ),
      ),
    );
  }
}
