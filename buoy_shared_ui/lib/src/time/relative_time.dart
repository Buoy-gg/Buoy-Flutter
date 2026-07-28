import 'package:flutter/material.dart';

import '../formatting.dart';
import '../minute_ticker.dart';

/// Ports packages/shared/src/utils/time/RelativeTime.tsx (+ useRelativeTime.ts).
///
/// Leaf widget that renders a live relative timestamp ("5s ago"). Composition-
/// over-memo (rule 2): list rows render THIS instead of computing the relative
/// string themselves, so the shared [MinuteTicker] tick re-renders only this
/// Text — not the whole (often const) row and its icon subtree. It retains the
/// ticker while mounted and releases it on dispose, matching the RN
/// TickProvider ref-count model.
class RelativeTime extends StatefulWidget {
  const RelativeTime({
    super.key,
    required this.timestamp,
    this.style,
    this.prefix = '',
    this.suffix = '',
  });

  /// Milliseconds-since-epoch, a [DateTime], or null (renders empty).
  final Object? timestamp;
  final TextStyle? style;

  /// Static text rendered before/after inside the same Text node.
  final String prefix;
  final String suffix;

  @override
  State<RelativeTime> createState() => _RelativeTimeState();
}

class _RelativeTimeState extends State<RelativeTime> {
  @override
  void initState() {
    super.initState();
    MinuteTicker.instance.retain();
  }

  @override
  void dispose() {
    MinuteTicker.instance.release();
    super.dispose();
  }

  int? _timestampMs() {
    final ts = widget.timestamp;
    if (ts == null) return null;
    if (ts is DateTime) return ts.millisecondsSinceEpoch;
    if (ts is int) return ts;
    if (ts is num) return ts.toInt();
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final ms = _timestampMs();
    return ValueListenableBuilder<int>(
      valueListenable: MinuteTicker.instance.tick,
      builder: (context, _, _) {
        final relative = ms == null ? '' : formatRelativeTime(ms);
        return Text('${widget.prefix}$relative${widget.suffix}',
            style: widget.style);
      },
    );
  }
}
