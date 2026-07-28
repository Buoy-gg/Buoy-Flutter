/// Ports the HUD body from
/// packages/perf-monitor/src/perf-monitor/components/PerfMonitorOverlay.tsx
/// (StripBody) + PerfHudInline.tsx — shared by the floating overlay chip and
/// the modal's live view.
///
/// Three modes, cycled by tapping the chip: `strip` (route row + metric cells
/// with sparklines), `compact` (the same cells, no sparklines, no route row),
/// and `card` (a frameless column per metric: identity badge, large value with
/// a unit suffix, and the window hint — no chart, just big legible numbers).
/// The former pill/full bodies were removed.
///
/// RN identity/severity palette, shared by both builds: JS #F5B342 (amber) ·
/// UI #4A9EFF (blue) · CPU #4ADE80 (green) · MEM #A855F7 (purple); severity
/// good #34C759 / warn #FFEB3B / bad #FF453A. Idle
/// (no frames within the window) dashes JS/UI to "—" per the honest Flutter
/// deviation; memory keeps updating. Sparkline uses the cheap CustomPaint port.
///
/// The Rec column drives recording exactly as RN does (camcorder-convention
/// ● / ■ icon plus the MM:SS timer), and the route row reads from buoy_routes.
/// Logged deviation: no reaFps row (no worklet thread in Flutter).
library;

import 'dart:math' as math;

import 'package:buoy_core/buoy_core.dart';
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';

import '../perf_types.dart';
import '../windowed_stats.dart';
import 'perf_sparkline.dart';

// Identity colors (RN IDENTITY_*). One hue per metric across EVERY mode and
// both builds — strip cells, card badges, and every sparkline. Changing one
// here changes it everywhere, which is the point.
const Color _identityJs = Color(0xFFF5B342); // amber
const Color _identityUi = Color(0xFF4A9EFF); // blue
const Color _identityCpu = Color(0xFF4ADE80); // green
const Color _identityMem = Color(0xFFA855F7); // purple

// Severity (RN COLOR_*).
const Color _good = Color(0xFF34C759);
const Color _warn = Color(0xFFFFEB3B);
const Color _bad = Color(0xFFFF453A);
const Color _neutral = Color(0xFFB084DC);

const Color _cellBg = Color(0x0AFFFFFF); // rgba(255,255,255,0.04)
const Color _cellBorder = Color(0x14FFFFFF); // rgba(255,255,255,0.08)

// Card mode. No frame: the columns sit directly on the chip surface and are
// separated by whitespace alone, so the row reads as one instrument cluster
// rather than five boxed widgets. Dropping the frame also returns ~12pt per
// column to the text, which is what kept the unit suffix from clipping at five
// columns on a phone.
const double _cardGap = 7;

/// Card interior budget, summing to [kCardBodyHeight]: header (badge + value)
/// then the window hint. Kept as constants so the overlay's chip height and
/// the modal's inline box are derived from the layout instead of guessed.
///
/// No chart — card mode is the "big legible numbers" layout; charts live in
/// `strip`. The chart primitives in `perf_card_chart.dart` are unused for now,
/// kept on disk so re-adding them is a one-liner.
const double _cardHeaderHeight = 22;
const double _cardHintHeight = 11;
const double _cardHintGap = 2;
const double _cardValueSize = 16;

/// The Rec column is a badge and a 12pt dot — it does not need an equal share.
/// Five equal columns on a ~378pt chip leave 63pt each, and MEM ("MEM" + a
/// 3-char value + "GB") wants ~77pt, so the unit got scaled away. Fixing Rec
/// narrow hands the four metric columns ~69pt each.
/// "Rec" badge (~24) + gap (4) + the dot (11). Any narrower clips the dot.
const double _cardRecWidth = 40;

/// Height the card body needs. The chip/inline surfaces add their own outer
/// padding on top of this.
const double kCardBodyHeight =
    _cardHeaderHeight + _cardHintGap + _cardHintHeight;

const String _mono = 'monospace';

String _formatMemory(double v) {
  if (v >= 1024) return '${(v / 1024).toStringAsFixed(1)}gb';
  return '${v.round()}mb';
}

String _fpsText(double fps, String mode) {
  if (mode == 'ms') {
    if (!fps.isFinite || fps <= 0) return '—';
    return '${(1000 / fps).round()}ms';
  }
  return fps.round().toString();
}

Color _fpsColor(double v, double max) {
  if (max <= 0) return _neutral;
  final ratio = v / max;
  if (ratio >= PerfThresholds.fpsGoodPct) return _good;
  if (ratio >= PerfThresholds.fpsWarnPct) return _warn;
  return _bad;
}

Color _cpuColor(double v) {
  if (v < PerfThresholds.cpuGoodMax) return _good;
  if (v < PerfThresholds.cpuWarnMax) return _warn;
  return _bad;
}

/// Truncate a route for the HUD's route row (RN `truncateRoute`): keep the
/// tail, which is the distinctive part of a pathname.
String truncateRoute(String route, int maxLen) {
  if (route.length <= maxLen) return route;
  return '…${route.substring(route.length - (maxLen - 1))}';
}

/// Live HUD body. [idle] = no frames within the window (dash FPS).
///
/// The Rec control drives RECORDING (RN parity): red ● = idle/tap-to-record,
/// red ■ = recording/tap-to-stop, with the elapsed MM:SS beneath it.
class PerfHudBody extends StatelessWidget {
  const PerfHudBody({
    super.key,
    required this.mode,
    required this.snapshot,
    required this.settings,
    required this.idle,
    required this.recording,
    required this.recordingElapsed,
    required this.onRecordTap,
    required this.onStopTap,
    this.routeLabel,
  });

  final HudMode mode;
  final PerfSnapshot snapshot;
  final PerfSettings settings;
  final bool idle;

  /// Whether a benchmark recording is currently in flight.
  final bool recording;

  /// MM:SS elapsed for the active recording ("" when idle).
  final String recordingElapsed;
  final VoidCallback onRecordTap;
  final VoidCallback onStopTap;

  /// Active route pathname; null when buoy_routes isn't wired.
  final String? routeLabel;

  void _togglePower() => recording ? onStopTap() : onRecordTap();

  double get _maxRefresh => math.max(60, snapshot.deviceMaxRefreshRate);

  WindowStats _stat(MetricKey k) =>
      computeWindowStats(snapshot.history, k, windowMs: settings.windowMs);

  /// Channel accessor handed to [PerfSparkline] (RN `PICK_JS` / `PICK_UI` /
  /// `PICK_CPU` / `PICK_MEM`).
  static double Function(PerfSample) _pick(MetricKey k) => switch (k) {
    MetricKey.jsFps => (s) => s.jsFps,
    MetricKey.uiFps => (s) => s.uiFps,
    MetricKey.cpuUsage => (s) => s.cpuUsage,
    MetricKey.memoryUsage => (s) => s.memoryUsage,
  };

  @override
  Widget build(BuildContext context) {
    final Widget body;
    switch (mode) {
      case HudMode.strip:
        body = _strip();
      case HudMode.compact:
        body = _strip(compact: true);
      case HudMode.card:
        body = _cards();
    }
    // The overlay host renders outside a Material/DefaultTextStyle, so bare
    // Text inherits Flutter's fallback style (yellow debug underline) for any
    // unset property. Pin a base style so both surfaces render clean text.
    return DefaultTextStyle(
      style: const TextStyle(
        decoration: TextDecoration.none,
        color: MacOSColors.textPrimary,
        fontFamily: _mono,
        fontSize: 12,
      ),
      child: body,
    );
  }

  /// Stacked recording control on the strip's trailing edge (RN `RecColumn`):
  /// "Rec" label, camcorder-convention icon (red ● idle / red ■ recording,
  /// 8pt), then the MM:SS timer while recording.
  Widget _recColumn() {
    return TouchableOpacity(
      activeOpacity: 0.7,
      onTap: _togglePower,
      child: SizedBox(
        width: 32,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Rec',
              style: TextStyle(
                color: recording ? _bad : const Color(0x8CFFFFFF),
                fontSize: 11,
                fontFamily: _mono,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 3),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: _bad,
                borderRadius: BorderRadius.circular(recording ? 1 : 4),
              ),
            ),
            if (recording) ...[
              const SizedBox(height: 3),
              Text(
                recordingElapsed,
                style: const TextStyle(
                  color: _bad,
                  fontSize: 9,
                  fontFamily: _mono,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// The trailing-window hint, stacked into two lines ("min" over "50")
  /// instead of one ("min 50").
  ///
  /// Four cells share the 360pt strip, so a one-line hint is the widest thing
  /// competing for a ~80pt cell — it was the first to clip, and clipping
  /// "min 50" down to "min" tells you nothing. Stacking halves the width it
  /// needs (the longest line is now the value alone). Two 9pt lines add up to
  /// the ~18pt the 14pt number already occupies, so the header row doesn't
  /// grow.
  Widget _stackedHint(String hint) {
    final space = hint.indexOf(' ');
    final word = space > 0 ? hint.substring(0, space) : hint;
    final value = space > 0 ? hint.substring(space + 1) : '';
    const style = TextStyle(
      color: MacOSColors.textMuted,
      fontSize: 8,
      height: 9 / 8,
      letterSpacing: 0.2,
      fontFamily: _mono,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          word,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.clip,
          style: style,
        ),
        if (value.isNotEmpty)
          Text(
            value,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.clip,
            style: style,
          ),
      ],
    );
  }

  /// Route row shown above the metrics (RN StripBody/FullBody `routeRow`:
  /// 12/14px tall, 9pt mono w500, letterSpacing 0.3, text.secondary). The
  /// height is always reserved so the bubble doesn't jump when route-events
  /// lights up — hence the blank space when no route is known.
  Widget _routeRow(int maxLen, {double height = 12}) => SizedBox(
    height: height,
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        routeLabel != null && routeLabel!.isNotEmpty
            ? truncateRoute(routeLabel!, maxLen)
            : ' ',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: MacOSColors.textSecondary,
          fontSize: 9,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.3,
          fontFamily: _mono,
        ),
      ),
    ),
  );

  // ── STRIP ─────────────────────────────────────────────────────────────
  Widget _strip({bool compact = false}) {
    final cells = <Widget>[];
    if (settings.showJsFps) {
      cells.add(
        _miniCell(
          'JS',
          snapshot.jsFps,
          _maxRefresh,
          _identityJs,
          tone: _Tone.fps,
          stat: _stat(MetricKey.jsFps),
          metric: MetricKey.jsFps,
          targetRatio: PerfThresholds.fpsGoodPct,
          baselineValue: _maxRefresh,
          showChart: !compact,
          fpsIdle: idle,
        ),
      );
    }
    if (settings.showUiFps) {
      cells.add(
        _miniCell(
          'UI',
          snapshot.uiFps,
          _maxRefresh,
          _identityUi,
          tone: _Tone.fps,
          stat: _stat(MetricKey.uiFps),
          metric: MetricKey.uiFps,
          targetRatio: PerfThresholds.fpsGoodPct,
          baselineValue: _maxRefresh,
          showChart: !compact,
          fpsIdle: idle,
        ),
      );
    }
    if (settings.showCpu && snapshot.capabilities.cpu) {
      cells.add(
        _miniCell(
          'CPU',
          snapshot.cpuUsage,
          100,
          _identityCpu,
          tone: _Tone.cpu,
          stat: _stat(MetricKey.cpuUsage),
          metric: MetricKey.cpuUsage,
          targetRatio: PerfThresholds.cpuWarnMax / 100,
          showChart: !compact,
        ),
      );
    }
    if (settings.showMem) {
      cells.add(
        _miniCell(
          'MEM',
          snapshot.memoryUsage,
          1024,
          _identityMem,
          tone: _Tone.mem,
          stat: _stat(MetricKey.memoryUsage),
          metric: MetricKey.memoryUsage,
          // No universal ceiling — the trend is the signal (RN scaleMode auto).
          scaleMode: SparklineScale.auto,
          showChart: !compact,
        ),
      );
    }
    // RN sizing: STRIP_ROUTE_ROW_HEIGHT 12 + STRIP_CELLS_HEIGHT 64; cells gap
    // 4 with 2px vertical padding, then a POWER_BUTTON_GAP (6) before the Rec
    // column. Compact drops the route row and the sparklines, leaving the
    // numbers — the surface owns the shorter height.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!compact) _routeRow(44),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < cells.length; i++) ...[
                        if (i > 0) const SizedBox(width: 4),
                        Expanded(child: cells[i]),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _recColumn(),
            ],
          ),
        ),
      ],
    );
  }

  // ── CARD ──────────────────────────────────────────────────────────────
  /// One rounded card per metric: identity badge, large value + small unit,
  /// the window hint, and a smooth glowing trace. The Rec control gets a card
  /// of its own on the trailing edge.
  Widget _cards() {
    final cards = <Widget>[];
    if (settings.showJsFps) {
      cards.add(
        _metricCard(
          'JS',
          snapshot.jsFps,
          _maxRefresh,
          _identityJs,
          tone: _Tone.fps,
          stat: _stat(MetricKey.jsFps),
          fpsIdle: idle,
        ),
      );
    }
    if (settings.showUiFps) {
      cards.add(
        _metricCard(
          'UI',
          snapshot.uiFps,
          _maxRefresh,
          _identityUi,
          tone: _Tone.fps,
          stat: _stat(MetricKey.uiFps),
          fpsIdle: idle,
        ),
      );
    }
    if (settings.showCpu && snapshot.capabilities.cpu) {
      cards.add(
        _metricCard(
          'CPU',
          snapshot.cpuUsage,
          100,
          _identityCpu,
          tone: _Tone.cpu,
          stat: _stat(MetricKey.cpuUsage),
        ),
      );
    }
    if (settings.showMem) {
      cards.add(
        _metricCard(
          'MEM',
          snapshot.memoryUsage,
          1024,
          _identityMem,
          tone: _Tone.mem,
          stat: _stat(MetricKey.memoryUsage),
        ),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(width: _cardGap),
          Expanded(child: cards[i]),
        ],
        const SizedBox(width: _cardGap),
        SizedBox(width: _cardRecWidth, child: _recCard()),
      ],
    );
  }

  /// Tinted identity chip carrying the metric's name.
  Widget _badge(String label, Color identity) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
    decoration: BoxDecoration(
      color: identity.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: identity.withValues(alpha: 0.45)),
    ),
    child: Text(
      label,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.clip,
      style: TextStyle(
        color: identity,
        fontSize: 9,
        height: 1.1,
        fontFamily: _mono,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
    ),
  );

  Widget _metricCard(
    String label,
    double value,
    double max,
    Color identity, {
    required _Tone tone,
    required WindowStats stat,
    bool fpsIdle = false,
  }) {
    final parts = _cardValue(tone, value, fpsIdle);
    final valueColor = _cardValueColor(tone, value, max, identity, fpsIdle);
    return _cardContent(
      header: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _badge(label, identity),
          const SizedBox(width: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                parts.value,
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  color: valueColor,
                  fontSize: _cardValueSize,
                  height: 1.0,
                  fontFamily: _mono,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (parts.unit.isNotEmpty) ...[
                const SizedBox(width: 2),
                Text(
                  parts.unit,
                  maxLines: 1,
                  softWrap: false,
                  style: const TextStyle(
                    color: MacOSColors.textMuted,
                    fontSize: 9,
                    height: 1.0,
                    fontFamily: _mono,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
      hint: _miniHint(tone, stat, fpsIdle),
    );
  }

  /// Recording card. Same shape as a metric card so the row reads as one
  /// instrument cluster: the "Rec" badge, the camcorder-convention icon where
  /// a value would sit, MM:SS in the hint slot, and a beat row for the chart.
  Widget _recCard() {
    final elapsed = recordingElapsed;
    return TouchableOpacity(
      activeOpacity: 0.7,
      onTap: _togglePower,
      child: _cardContent(
        header: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _badge('Rec', _bad),
            const SizedBox(width: 6),
            Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                color: _bad,
                borderRadius: BorderRadius.circular(recording ? 2 : 5.5),
                boxShadow: [
                  BoxShadow(color: _bad.withValues(alpha: 0.5), blurRadius: 6),
                ],
              ),
            ),
          ],
        ),
        hint: recording && elapsed.isNotEmpty ? elapsed : '',
        hintColor: recording ? _bad : null,
      ),
    );
  }

  /// Shared card interior: header line, right-aligned hint, chart fills the
  /// rest. [FittedBox] on the header is the narrow-phone escape hatch — five
  /// cards on a 393pt screen leave ~67pt each, which is a few points short of
  /// what the badge + a three-digit value want.
  Widget _cardContent({
    required Widget header,
    required String hint,
    Color? hintColor,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      SizedBox(
        height: _cardHeaderHeight,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: header,
        ),
      ),
      const SizedBox(height: _cardHintGap),
      SizedBox(
        height: _cardHintHeight,
        child: Align(
          // Trails the value, mirroring the mock — the number is the
          // headline, the window stat is the footnote under it.
          alignment: Alignment.centerRight,
          child: Text(
            hint.isEmpty ? ' ' : hint,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.clip,
            style: TextStyle(
              color: hintColor ?? MacOSColors.textMuted,
              fontSize: 9,
              height: 1.0,
              fontFamily: _mono,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    ],
  );

  /// Split the live value into the big number and its small unit suffix.
  ({String value, String unit}) _cardValue(
    _Tone tone,
    double value,
    bool fpsIdle,
  ) {
    switch (tone) {
      case _Tone.fps:
        if (fpsIdle) return (value: '—', unit: '');
        if (settings.frameBudgetMode == 'ms') {
          if (!value.isFinite || value <= 0) return (value: '—', unit: '');
          return (value: '${(1000 / value).round()}', unit: 'ms');
        }
        // No "fps" suffix: a bare frame count is the universal convention, and
        // three characters is the difference between the MEM column fitting
        // its unit and clipping it at five columns on a phone.
        return (value: '${value.round()}', unit: '');
      case _Tone.cpu:
        return (value: '${value.round()}', unit: '%');
      case _Tone.mem:
        if (value >= 1024) {
          return (value: (value / 1024).toStringAsFixed(1), unit: 'GB');
        }
        return (value: '${value.round()}', unit: 'MB');
    }
  }

  /// Identity hue while the metric is healthy, severity hue once it isn't.
  ///
  /// Card mode's appeal is one coherent color per card, which pure severity
  /// coloring would break (four green numbers against four different badges).
  /// Keeping identity for "good" preserves the look; escalating to
  /// yellow/red for warn/bad makes a degraded card the only one that breaks
  /// its own palette, which is exactly where the eye should go.
  Color _cardValueColor(
    _Tone tone,
    double value,
    double max,
    Color identity,
    bool fpsIdle,
  ) {
    if (fpsIdle) return MacOSColors.textMuted;
    switch (tone) {
      case _Tone.fps:
        final c = _fpsColor(value, max);
        return c == _good ? identity : c;
      case _Tone.cpu:
        final c = _cpuColor(value);
        return c == _good ? identity : c;
      case _Tone.mem:
        return identity;
    }
  }

  Widget _miniCell(
    String label,
    double value,
    double max,
    Color identity, {
    required _Tone tone,
    required WindowStats stat,
    required MetricKey metric,
    double? targetRatio,
    double? baselineValue,
    SparklineScale scaleMode = SparklineScale.fixed,
    bool showChart = true,
    bool fpsIdle = false,
  }) {
    final String valueText;
    final Color valueColor;
    if (tone == _Tone.fps) {
      valueText = fpsIdle ? '—' : _fpsText(value, settings.frameBudgetMode);
      valueColor = fpsIdle ? MacOSColors.textMuted : _fpsColor(value, max);
    } else if (tone == _Tone.cpu) {
      valueText = '${value.round()}%';
      valueColor = _cpuColor(value);
    } else {
      valueText = _formatMemory(value);
      valueColor = _neutral;
    }
    final minHint = _miniHint(tone, stat, fpsIdle);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            // The hint is a two-line block, so the row centers its children;
            // the label + number keep their shared baseline in the inner Row.
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: const Color(0xA6B4C8E6),
                      fontSize: 9,
                      fontFamily: _mono,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    valueText,
                    style: TextStyle(
                      color: valueColor,
                      fontSize: 14,
                      fontFamily: _mono,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              if (minHint.isNotEmpty) ...[
                const SizedBox(width: 6),
                Flexible(child: _stackedHint(minHint)),
              ],
            ],
          ),
        ),
        if (showChart) ...[
          const SizedBox(height: 2),
          Expanded(
            // RN `miniStyles.chartFrame`: cell bg + 1px border, radius 4,
            // overflow hidden so columns can't paint past the rounded corners.
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Container(
                decoration: BoxDecoration(
                  color: _cellBg,
                  border: Border.all(color: _cellBorder),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: PerfSparkline(
                  history: snapshot.history,
                  pick: _pick(metric),
                  max: max,
                  color: identity,
                  scaleMode: scaleMode,
                  targetRatio: targetRatio,
                  baselineValue: baselineValue,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ── helpers ─────────────────────────────────────────────────────────────
  String _miniHint(_Tone tone, WindowStats s, bool fpsIdle) {
    if (s.samplesUsed == 0) return '';
    switch (tone) {
      case _Tone.fps:
        if (settings.frameBudgetMode == 'ms') {
          if (_maxRefresh <= 0) return '';
          return 'budget ${(1000 / _maxRefresh).toStringAsFixed(1)}ms';
        }
        return 'min ${s.min.round()}';
      case _Tone.cpu:
        return 'max ${s.max.round()}%';
      case _Tone.mem:
        final v = s.min;
        return v >= 1024
            ? 'min ${(v / 1024).toStringAsFixed(1)}gb'
            : 'min ${v.round()}mb';
    }
  }
}

enum _Tone { fps, cpu, mem }
