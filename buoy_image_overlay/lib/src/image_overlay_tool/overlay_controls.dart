/// Ports packages/image-overlay/src/imageOverlay/components/OverlayControls.tsx.
///
/// Opacity / scale / offset controls — each a labeled row with -/+ stepper
/// buttons flanking a draggable slider track and a right-aligned value.
library;

import 'package:buoy_core/buoy_core.dart';
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';

/// RN `SliderStepper`.
class _SliderStepper extends StatelessWidget {
  const _SliderStepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.displayValue,
    required this.onChange,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final double step;
  final String displayValue;
  final ValueChanged<double> onChange;

  double _clamp(double v) => v < min ? min : (v > max ? max : v);

  @override
  Widget build(BuildContext context) {
    final fraction = max > min ? (value - min) / (max - min) : 0.0;
    // controlRow: paddingHorizontal 12, gap 4.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: MacOSColors.textMuted,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _stepper('-', () => onChange(_clamp(value - step))),
              const SizedBox(width: 6),
              Expanded(child: _track(fraction.toDouble())),
              const SizedBox(width: 6),
              _stepper('+', () => onChange(_clamp(value + step))),
              const SizedBox(width: 6),
              SizedBox(
                width: 45,
                child: Text(
                  displayValue,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: MacOSColors.textPrimary,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stepper(String glyph, VoidCallback onTap) {
    return TouchableOpacity(
      activeOpacity: 0.6,
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: MacOSColors.backgroundHover,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: MacOSColors.borderDefault),
        ),
        child: Text(
          glyph,
          style: const TextStyle(
            fontSize: 16,
            height: 18 / 16,
            fontWeight: FontWeight.w700,
            color: MacOSColors.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _track(double fraction) {
    void handle(double localX, double width) {
      if (width <= 0) return;
      final frac = (localX / width).clamp(0.0, 1.0);
      onChange(_clamp(min + frac * (max - min)));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => handle(d.localPosition.dx, width),
          onHorizontalDragStart: (d) => handle(d.localPosition.dx, width),
          onHorizontalDragUpdate: (d) => handle(d.localPosition.dx, width),
          child: SizedBox(
            height: 28,
            child: Stack(
              children: [
                // sliderTrack
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: MacOSColors.backgroundHover,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: MacOSColors.borderDefault),
                    ),
                  ),
                ),
                // sliderFill
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: width * fraction,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: BuoyColors.primary.withValues(alpha: 0x30 / 255),
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ),
                // sliderThumb (width 4, top/bottom inset 4, marginLeft -2)
                Positioned(
                  left: (width * fraction) - 2,
                  top: 4,
                  bottom: 4,
                  width: 4,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: BuoyColors.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// RN `OverlayControls`. When [opacityOnly], shows just the opacity slider.
class OverlayControls extends StatelessWidget {
  const OverlayControls({
    super.key,
    required this.opacity,
    required this.scale,
    required this.offsetX,
    required this.offsetY,
    required this.onOpacityChange,
    required this.onScaleChange,
    required this.onOffsetChange,
    this.opacityOnly = false,
  });

  final double opacity;
  final double scale;
  final double offsetX;
  final double offsetY;
  final ValueChanged<double> onOpacityChange;
  final ValueChanged<double> onScaleChange;
  final void Function(double x, double y) onOffsetChange;
  final bool opacityOnly;

  @override
  Widget build(BuildContext context) {
    final opacitySlider = _SliderStepper(
      label: 'Opacity',
      value: opacity,
      min: 0,
      max: 1,
      step: 0.05,
      displayValue: '${(opacity * 100).round()}%',
      onChange: onOpacityChange,
    );

    if (opacityOnly) return opacitySlider;

    return Column(
      children: [
        opacitySlider,
        const SizedBox(height: 8),
        _SliderStepper(
          label: 'Scale',
          value: scale,
          min: 0.05,
          max: 3,
          step: 0.05,
          displayValue: '${(scale * 100).round()}%',
          onChange: onScaleChange,
        ),
        const SizedBox(height: 8),
        _SliderStepper(
          label: 'Offset X',
          value: offsetX,
          min: -200,
          max: 200,
          step: 2,
          displayValue: '${offsetX.round()}px',
          onChange: (v) => onOffsetChange(v.roundToDouble(), offsetY),
        ),
        const SizedBox(height: 8),
        _SliderStepper(
          label: 'Offset Y',
          value: offsetY,
          min: -200,
          max: 200,
          step: 2,
          displayValue: '${offsetY.round()}px',
          onChange: (v) => onOffsetChange(offsetX, v.roundToDouble()),
        ),
      ],
    );
  }
}
