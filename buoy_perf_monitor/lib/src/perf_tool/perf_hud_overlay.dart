/// Ports the floating chip from
/// packages/perf-monitor/src/perf-monitor/components/PerfMonitorOverlay.tsx —
/// the draggable HUD auto-mounted via [BuoyOverlayHost]. Renders nothing unless
/// the HUD is enabled AND the modal is closed (RN suppresses the floating
/// bubble while the modal is open; the modal shows its own inline HUD).
///
/// Drag to move, tap to cycle strip → compact → card → strip. Position + mode
/// persist under `hud-prefs`. Empty regions pass touches through (only the chip
/// paints) — the overlay-host box-none analog.
///
/// B1 deviations (logged): drag-past-edge park (RN) is deferred; idle FPS
/// dashes after [_idleThresholdMs] of no frames (a snappy interpretation of
/// RN's "no frames in windowMs").
library;

import 'dart:math' as math;

import 'package:buoy_core/buoy_core.dart';
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';

import '../perf_types.dart';
import '../hud_preferences.dart';
import '../perf_monitor_controller.dart';
import 'perf_hud_surface.dart';

const double _padH = 10;

/// Margin the strip keeps from each screen edge. Deliberately tighter than the
/// bubble's drag/snap inset: at four cells the strip needs the width more than
/// it needs the breathing room, and it still reads as floating.
const double _stripEdgeMargin = 8;
const double _padV = 8;
const double _topSafe = 44;

class PerfHudOverlay extends StatefulWidget {
  const PerfHudOverlay({super.key});

  @override
  State<PerfHudOverlay> createState() => _PerfHudOverlayState();
}

class _PerfHudOverlayState extends State<PerfHudOverlay> {
  final _controller = PerfMonitorController.instance;

  bool _enabled = false;
  HudMode _mode = HudPreferences.defaults.mode;
  Offset? _position; // null → use default top-right until measured/loaded
  bool _prefsLoaded = false;

  /// The stop→name→save prompt, rendered above the chip (no Navigator exists
  /// above the dev-tools layer, so it lives in this Stack).
  Widget? _savePrompt;

  void Function()? _unsubEnabled;

  @override
  void initState() {
    super.initState();
    _unsubEnabled = _controller.subscribeEnabled((e) {
      if (mounted) setState(() => _enabled = e);
    });
    // ignore: discarded_futures
    loadHudPreferences().then((p) {
      if (!mounted) return;
      setState(() {
        _mode = p.mode;
        if (p.position.x >= 0 && p.position.y >= 0) {
          _position = Offset(p.position.x, p.position.y);
        }
        _prefsLoaded = true;
      });
    });
  }

  @override
  void dispose() {
    _unsubEnabled?.call();
    super.dispose();
  }

  /// The chip's OUTER box per mode. Padding lives inside these numbers (RN's
  /// `containerStyles.content` sits on the same flex:1 surface as the sized
  /// container), so the body fills rather than pinning its own size.
  /// 520 is an upper bound for wide viewports — [_fittedChipSize] fits it to
  /// the screen on a phone. Heights come from [hudHeightFor], the same
  /// contract the modal's inline HUD uses.
  Size _chipSize() => Size(520, hudHeightFor(_mode, padV: _padV));

  /// [_chipSize] fitted to the viewport — both modes are width-bound.
  Size _fittedChipSize(double screenWidth) {
    final size = _chipSize();
    final available = math.max(240.0, screenWidth - _stripEdgeMargin * 2);
    return Size(math.min(size.width, available), size.height);
  }

  /// Tap cycles strip → compact → card → strip (RN `handleCycleMode`).
  void _cycleMode() {
    setState(() => _mode = nextHudMode(_mode));
    _persist();
  }

  void _persist() {
    final pos = _position;
    // ignore: discarded_futures
    saveHudPreferences(
      HudPreferences(
        mode: _mode,
        position: pos == null ? (x: -1, y: -1) : (x: pos.dx, y: pos.dy),
        hidden: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    final chipSize = _fittedChipSize(screen.width);
    final defaultX = (screen.width - chipSize.width - 8).clamp(
      0.0,
      screen.width,
    );
    final pos = _position ?? Offset(defaultX, _topSafe);

    // Position the moving chip with Transform.translate (a layer offset, no
    // ParentData) rather than a re-applied Positioned — the latter, rebuilt at
    // the 4Hz snapshot cadence with a semantic GestureDetector child, trips
    // Flutter's `!semantics.parentDataDirty` assert and blanks the overlay.
    // Structure mirrors the working image_overlay standalone: a Positioned.fill
    // → Stack, with the chip aligned top-left and offset by the drag position.
    // Positioned.fill stays the direct child of the host's Stack (it is a
    // ParentDataWidget); the gate lives inside it.
    return Positioned.fill(
      child: ValueListenableBuilder<bool>(
        valueListenable: _controller.modalOpen,
        builder: (context, modalOpen, _) {
          if (!_prefsLoaded || !_enabled || modalOpen) {
            return const SizedBox.shrink();
          }
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Align(
                alignment: Alignment.topLeft,
                child: Transform.translate(
                  offset: pos,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _cycleMode,
                    onPanUpdate: (d) {
                      setState(() {
                        final next = (_position ?? pos) + d.delta;
                        _position = Offset(
                          next.dx.clamp(0.0, screen.width - 40),
                          next.dy.clamp(_topSafe, screen.height - 40),
                        );
                      });
                    },
                    onPanEnd: (_) => _persist(),
                    child: Container(
                      width: chipSize.width,
                      height: chipSize.height,
                      padding: const EdgeInsets.symmetric(
                        horizontal: _padH,
                        vertical: _padV,
                      ),
                      decoration: BoxDecoration(
                        color: BuoyColors.card,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: BuoyColors.textMuted.withValues(
                            alpha: 0x66 / 255,
                          ),
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x66000000),
                            blurRadius: 12,
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),
                      child: PerfHudSurface(
                        mode: _mode,
                        onPendingPromptChanged: (prompt) {
                          if (mounted) setState(() => _savePrompt = prompt);
                        },
                        builder: (context, body) => body,
                      ),
                    ),
                  ),
                ),
              ),
              ?_savePrompt,
            ],
          );
        },
      ),
    );
  }
}
