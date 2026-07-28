/// Ports packages/route-events/src/components/RouteEventDetail.tsx +
/// RouteEventExpandedContent.tsx.
///
/// The full-screen detail for one route event: three readable sections (Route
/// Information / Timing / Parameters & Metadata) plus a prominent "Go to route"
/// footer action. The back header + toolbar copy live on the surrounding modal.
library;

import 'package:buoy_core/buoy_core.dart' show TouchableOpacity;
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';

import '../route_template.dart';
import '../routes_capture.dart';

/// RN `formatDuration` (RouteEventExpandedContent variant).
String _formatDuration(int ms) {
  if (ms < 1000) return '${ms}ms';
  if (ms < 60000) return '${(ms / 1000).toStringAsFixed(1)}s';
  final minutes = ms ~/ 60000;
  final seconds = (ms % 60000) ~/ 1000;
  return '${minutes}m ${seconds}s';
}

String _formatTimestamp(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} '
      '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
}

/// RN RouteEventDetail — scrollable sections + Go footer.
class RouteEventDetail extends StatelessWidget {
  const RouteEventDetail({
    super.key,
    required this.event,
    required this.visitNumber,
    required this.onNavigate,
  });

  final RouteChangeEvent event;
  final int visitNumber;
  final void Function(String pathname) onNavigate;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: BuoyColors.base,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(14),
              child: RouteEventExpandedContent(
                event: event,
                visitNumber: visitNumber,
                routeTemplate: getRouteTemplate(event.pathname, event.segments),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: BuoyColors.base,
              border: Border(top: BorderSide(color: BuoyColors.border)),
            ),
            child: TouchableOpacity(
              activeOpacity: 0.8,
              onTap: () => onNavigate(event.pathname),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: BuoyColors.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    BuoyGlyph(BuoyIcons.navigation, size: 16, color: Color(0xFFFFFFFF)),
                    SizedBox(width: 8),
                    Text(
                      'GO TO ROUTE',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFFFFFFF),
                        fontFamily: 'monospace',
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// RN RouteEventExpandedContent — the three detail sections.
class RouteEventExpandedContent extends StatelessWidget {
  const RouteEventExpandedContent({
    super.key,
    required this.event,
    required this.visitNumber,
    required this.routeTemplate,
  });

  final RouteChangeEvent event;
  final int visitNumber;
  final String? routeTemplate;

  @override
  Widget build(BuildContext context) {
    final hasParams = event.params.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section A: Route Information.
        _section([
          if (routeTemplate != null) _row('Template:', routeTemplate!, copy: routeTemplate),
          if (event.previousPathname != null)
            _row('From:', event.previousPathname!, copy: event.previousPathname),
          _row('To:', event.pathname, copy: event.pathname),
        ]),
        const SizedBox(height: 12),
        // Section B: Timing.
        _section([
          if (event.timeSincePrevious != null)
            _row('Duration:', _formatDuration(event.timeSincePrevious!)),
          _row('Time:', _formatTimestamp(event.timestamp)),
        ]),
        const SizedBox(height: 12),
        // Section C: Parameters & Metadata.
        _section([
          if (event.segments.isNotEmpty)
            _row('Segments:', event.segments.join(' → '),
                copy: event.segments.toString()),
          if (hasParams) _params(),
          if (visitNumber > 1)
            _row('Visited:', '$visitNumber time${visitNumber != 1 ? 's' : ''}'),
        ]),
      ],
    );
  }

  Widget _section(List<Widget> children) {
    final visible = children.whereType<Widget>().toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < visible.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          visible[i],
        ],
      ],
    );
  }

  Widget _row(String label, String value, {String? copy}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: BuoyColors.textSecondary,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 11,
              color: BuoyColors.text,
              fontFamily: 'monospace',
            ),
          ),
        ),
        if (copy != null)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: CopyButton(value: copy, size: 12),
          ),
      ],
    );
  }

  Widget _params() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Parameters (${event.params.length})',
              style: const TextStyle(
                fontSize: 11,
                color: BuoyColors.textSecondary,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600,
              ),
            ),
            CopyButton(value: event.params, size: 12),
          ],
        ),
        const SizedBox(height: 8),
        DataViewer(data: event.params, initialExpanded: true),
      ],
    );
  }
}
