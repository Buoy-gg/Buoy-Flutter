/// Ports packages/perf-monitor/src/perf-monitor/components/AutomationProgressOverlay.tsx.
///
/// Floating pill rendered above the HUD whenever a batch is running. Stays
/// visible while the modal auto-hides, so the user can watch progress while
/// the test page exercises itself in the foreground: pulsing red dot +
/// phase + case index + total-batch-remaining + inline stop button.
///
/// Hidden when the runner is idle / done / cancelled. RN geometry: top 60,
/// radius 18, 1.5px error border @AA, padL 14 / padR 6 / padV 8, 10pt dot,
/// 12pt mono w700 label, 26pt round stop button.
library;

import 'package:buoy_core/buoy_core.dart';
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';

import '../automation_runner.dart';
import '../automation_settings.dart';
import '../batch_time_estimate.dart';
import '../perf_types.dart';

const String _mono = 'monospace';

class AutomationProgressOverlay extends StatefulWidget {
  const AutomationProgressOverlay({super.key});

  @override
  State<AutomationProgressOverlay> createState() =>
      _AutomationProgressOverlayState();
}

class _AutomationProgressOverlayState extends State<AutomationProgressOverlay>
    with SingleTickerProviderStateMixin {
  AutomationStatus _status = automationRunner.getStatus();
  AutomationConfig _config = AutomationConfigStore.instance.current;

  void Function()? _unsubStatus;
  void Function()? _unsubConfig;

  /// Pulse the recording dot so it reads as "live" — the same visual language
  /// as camera/voice-record indicators (RN: 600 ms each way, 1 → 0.35).
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
    lowerBound: 0.35,
    upperBound: 1,
  );

  @override
  void initState() {
    super.initState();
    _unsubStatus = automationRunner.subscribe((s) {
      if (mounted) setState(() => _status = s);
    });
    _unsubConfig = AutomationConfigStore.instance.subscribe((c) {
      if (mounted) setState(() => _config = c);
    });
    _pulse.repeat(reverse: true);
  }

  @override
  void dispose() {
    _unsubStatus?.call();
    _unsubConfig?.call();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_status.isActive) return const SizedBox.shrink();

    final total = _status.total ?? 0;
    final index = _status.index ?? 0;
    final runTotal = _status.runTotal ?? 1;
    final runIndex = _status.runIndex ?? 0;
    final remainingMs = batchRemainingMs(_status, _config);
    final remainingLabel =
        remainingMs != null ? formatDurationLeft(remainingMs) : '';
    // Only show the run counter on multi-run batches — no "run 1/1" noise.
    final runLabel = runTotal > 1 ? ' · r${runIndex + 1}/$runTotal' : '';
    final label = 'REC · ${_describePhase(_status.phase)} · ${index + 1}/$total'
        '$runLabel${remainingLabel.isNotEmpty ? " · $remainingLabel" : ""}';

    return Positioned.fill(
      child: DefaultTextStyle(
        style: const TextStyle(decoration: TextDecoration.none),
        child: Stack(
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 60),
                child: Container(
                  decoration: BoxDecoration(
                    color: MacOSColors.backgroundCard,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: MacOSColors.error.withValues(alpha: 0xAA / 255),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color:
                            MacOSColors.error.withValues(alpha: 0x73 / 255),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FadeTransition(
                        opacity: _pulse,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: MacOSColors.error,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: MacOSColors.textPrimary,
                          fontSize: 12,
                          fontFamily: _mono,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(width: 10),
                      TouchableOpacity(
                        activeOpacity: 0.7,
                        onTap: automationRunner.cancel,
                        child: Container(
                          width: 26,
                          height: 26,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: MacOSColors.error
                                .withValues(alpha: 0x33 / 255),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: MacOSColors.error
                                  .withValues(alpha: 0x88 / 255),
                            ),
                          ),
                          child: const Text(
                            '×',
                            style: TextStyle(
                              color: MacOSColors.error,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
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
    );
  }
}

String _describePhase(String phase) {
  switch (phase) {
    case 'navigating-bounce':
      return 'bounce';
    case 'navigating-target':
      return 'loading';
    case 'settling':
      return 'settling';
    case 'recording':
      return 'recording';
    case 'saving':
      return 'saving';
    case 'cooling-down':
      return 'cooldown';
    case 'reloading':
      return 'reloading';
    default:
      return '';
  }
}
