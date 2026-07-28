/// Ports packages/images/src/components/InsightsBar.tsx — compact warning
/// chips above the list when cross-record findings exist (duplicates, retry
/// storms, queue saturation, missing alt, layout shifts). Renders nothing when
/// all clear. A wrapping row (not a horizontal scroller, which under-measures
/// inside the modal's flex column).
library;

import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';

import '../image_record.dart';
import '../images_store.dart';

class InsightsBar extends StatelessWidget {
  const InsightsBar({super.key, required this.insights});

  final ImageInsights insights;

  @override
  Widget build(BuildContext context) {
    final chips = insightChips(insights);
    if (chips.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: MacOSColors.borderDefault, width: 0.5),
        ),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final chip in chips)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: MacOSColors.warningBackground,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                chip,
                style: const TextStyle(
                  color: MacOSColors.warning,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
