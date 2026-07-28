/// Ports packages/perf-monitor/src/perf-monitor/components/AutomationConfigView.tsx.
///
/// Configure and kick off an automated benchmark batch; while a batch runs the
/// same view re-renders as the progress + cancel panel (RN `RunningPanel`).
///
/// Sections mirror RN: **Target** (default route · bounce route · speed preset
/// · per-case duration · "Show advanced" → runs/cooldown/warmup/settle/nav
/// timeout/shuffle/capture toggles) and **Cases** (Clear · Copy · Saved ·
/// Paste N cases · Add case, then a bounded-height case list), with the run
/// button labelled "Run N cases × M runs = K recordings".
///
/// Logged deviations: the free-plan 3-case cap + ProUpgradeModal are omitted
/// (no license package in the Flutter SDK — the established "PRO UI
/// display-only" precedent), and the reload-between-cases toggle and "Test
/// reload now" button are omitted because Dart can't reload its realm (the
/// config field is sanitized to false).
library;

import 'package:buoy_core/buoy_core.dart';
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../automation_runner.dart';
import '../automation_settings.dart';
import '../case_sets.dart';
import '../compute_case_labels.dart';
import '../exporters.dart';
import '../parse_automation_cases.dart';
import '../perf_route_bridge.dart';
import '../perf_types.dart';
import '../route_validation.dart';
import 'perf_dialogs.dart';

const String _mono = 'monospace';

class AutomationConfigView extends StatefulWidget {
  const AutomationConfigView({super.key});

  @override
  State<AutomationConfigView> createState() => _AutomationConfigViewState();
}

class _AutomationConfigViewState extends State<AutomationConfigView> {
  AutomationConfig _config = AutomationConfigStore.instance.current;
  bool _adoptedPersisted = false;
  bool _showAdvanced = false;

  /// null | 'target' | 'bounce'
  String? _routePickerFor;
  bool _showSavedCases = false;

  /// How many cases the clipboard holds, for the Paste button preview.
  int _clipboardCaseCount = 0;

  AutomationStatus _status = automationRunner.getStatus();
  List<String> _sitemap = const [];

  Widget? _dialog;

  void Function()? _unsubConfig;
  void Function()? _unsubStatus;

  final _durationCtrl = TextEditingController();
  final _runsCtrl = TextEditingController();
  final _coolDownCtrl = TextEditingController();
  final _warmupCtrl = TextEditingController();
  final _settleCtrl = TextEditingController();
  final _navTimeoutCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _sitemap = getRouteList();
    _unsubConfig = AutomationConfigStore.instance.subscribe((persisted) {
      if (!mounted) return;
      // Only adopt the persisted value on first load; after that the user's
      // in-progress edits win (RN parity).
      if (_adoptedPersisted) return;
      if (_config.cases.isEmpty && _config.targetRoute.isEmpty) {
        setState(() {
          _config = persisted;
          _adoptedPersisted = true;
        });
        _syncControllers();
      }
    });
    _unsubStatus = automationRunner.subscribe((s) {
      if (mounted) setState(() => _status = s);
    });
    // ignore: discarded_futures
    AutomationConfigStore.instance.load();
    // ignore: discarded_futures
    CaseSetsStore.instance.load();
    // Auto-fill the target route from the current screen when empty.
    if (_config.targetRoute.isEmpty) {
      final current = getCurrentRoute();
      if (current.isNotEmpty) {
        _config = _config.copyWith(targetRoute: current);
      }
    }
    _syncControllers();
    // ignore: discarded_futures
    _refreshClipboardCount();
  }

  @override
  void dispose() {
    _unsubConfig?.call();
    _unsubStatus?.call();
    _durationCtrl.dispose();
    _runsCtrl.dispose();
    _coolDownCtrl.dispose();
    _warmupCtrl.dispose();
    _settleCtrl.dispose();
    _navTimeoutCtrl.dispose();
    super.dispose();
  }

  void _syncControllers() {
    _durationCtrl.text = '${_config.perCaseDurationMs}';
    _runsCtrl.text = '${_config.runsPerCase}';
    _coolDownCtrl.text = '${_config.coolDownMs}';
    _warmupCtrl.text = '${_config.discardWarmupRuns}';
    _settleCtrl.text = '${_config.settleMs}';
    _navTimeoutCtrl.text = '${_config.navTimeoutMs}';
  }

  void _update(AutomationConfig Function(AutomationConfig) patch) {
    setState(() => _config = patch(_config));
  }

  void _showDialog(Widget dialog) => setState(() => _dialog = dialog);
  void _closeDialog() => setState(() => _dialog = null);

  void _notice(String title, [String? message]) => _showDialog(
        PerfNoticeDialog(
          title: title,
          message: message,
          onDismiss: _closeDialog,
        ),
      );

  // ── Cases: add / duplicate / remove / import ────────────────────────────

  void _addCase() {
    _update((prev) => prev.copyWith(cases: [
          ...prev.cases,
          // The first case is the baseline column in the report.
          createBlankCase(
            prev.cases.isEmpty ? 'baseline' : 'case ${prev.cases.length + 1}',
          ),
        ]));
  }

  void _duplicateCase(String id) {
    _update((prev) {
      final idx = prev.cases.indexWhere((c) => c.id == id);
      if (idx < 0) return prev;
      final original = prev.cases[idx];
      final copy = createBlankCase('${original.name} (copy)')
        ..params = {...original.params}
        ..route = original.route;
      final next = [...prev.cases]..insert(idx + 1, copy);
      return prev.copyWith(cases: next);
    });
  }

  void _removeCase(String id) => _update(
        (prev) =>
            prev.copyWith(cases: [...prev.cases.where((c) => c.id != id)]),
      );

  void _applyImported(List<AutomationCase> incoming, String mode) {
    _update((prev) => prev.copyWith(
          cases: mode == 'replace' ? incoming : [...prev.cases, ...incoming],
        ));
  }

  Future<void> _refreshClipboardCount() async {
    final text = await readClipboardText();
    if (!mounted) return;
    if (text == null || text.trim().isEmpty) {
      setState(() => _clipboardCaseCount = 0);
      return;
    }
    final parsed = parseAutomationCases(text);
    if (parsed.cases.isEmpty) {
      setState(() => _clipboardCaseCount = 0);
      return;
    }
    final gated =
        filterImportableCases(parsed.cases, _config.targetRoute, _sitemap);
    setState(() => _clipboardCaseCount = gated.importable.length);
  }

  Future<void> _handleBulkPaste() async {
    final text = await readClipboardText();
    if (!mounted) return;
    if (text == null) {
      _notice('Clipboard unavailable',
          'The platform refused the clipboard read. Try again, or add cases by hand.');
      return;
    }
    if (text.trim().isEmpty) {
      _notice('Clipboard is empty',
          'Copy your case list first, then tap Paste again.');
      return;
    }
    final result = parseAutomationCases(text);
    if (result.cases.isEmpty) {
      _notice(
        'No valid cases found',
        result.errors.isNotEmpty
            ? 'No valid cases found in your clipboard. ${result.errors.length} line${result.errors.length == 1 ? "" : "s"} didn\'t match the expected format.'
            : 'No valid cases found in your clipboard. Copy a case list (one per line, or a JSON array) and try again.',
      );
      return;
    }

    // Sitemap gate: a pasted "case" whose resolved route isn't in THIS app's
    // sitemap is not a real target here (e.g. an external URL that parses
    // cleanly to "/apps"). Drop it rather than import junk.
    final gated =
        filterImportableCases(result.cases, _config.targetRoute, _sitemap);
    if (gated.importable.isEmpty) {
      _notice(
        'No valid cases found',
        gated.droppedUnknown > 0
            ? 'No valid cases found in your clipboard. ${gated.droppedUnknown} pasted route${gated.droppedUnknown == 1 ? " isn't" : "s aren't"} in your app\'s sitemap — looks like random text or an external URL, not a case for this app.'
            : 'No valid cases found in your clipboard. Copy a case list (one per line, or a JSON array) and try again.',
      );
      return;
    }

    // Always append (when the editor is empty, append == replace). Surface a
    // one-line confirmation only when something was dropped or skipped.
    _applyImported(gated.importable, 'append');
    if (gated.droppedUnknown > 0 || result.errors.isNotEmpty) {
      final summary = [
        'Found ${gated.importable.length} case${gated.importable.length == 1 ? "" : "s"}',
        if (gated.droppedUnknown > 0) '${gated.droppedUnknown} not in sitemap',
        if (result.errors.isNotEmpty) '${result.errors.length} skipped',
      ].join(' · ');
      final detail = [
        if (gated.droppedUnknown > 0)
          'Dropped ${gated.droppedUnknown} route${gated.droppedUnknown == 1 ? "" : "s"} not found in your app\'s sitemap.',
        if (result.errors.isNotEmpty)
          'Skipped lines: ${result.errors.take(3).map((e) => "#${e.line}").join(", ")}${result.errors.length > 3 ? "…" : ""}',
      ].join('\n');
      _notice(summary, detail.isEmpty ? null : detail);
    }
  }

  Future<void> _handleCopyCases() async {
    if (_config.cases.isEmpty) return;
    final ok = await copyText(serializeAutomationCases(_config.cases));
    if (!mounted) return;
    final n = _config.cases.length;
    _notice(
      ok ? 'Copied' : 'Copy failed',
      ok
          ? '$n case${n == 1 ? "" : "s"} copied as JSON. Paste them back here later, or share them.'
          : 'The platform refused the clipboard write.',
    );
  }

  /// Load a reusable list into the editor. Clones with fresh ids so repeated
  /// loads never collide, then reuses the Append/Replace prompt when the
  /// editor already has cases.
  void _applyCaseList(List<AutomationCase> incoming, String sourceLabel) {
    final fresh = cloneCasesWithNewIds(incoming);
    if (fresh.isEmpty) return;
    if (_config.cases.isEmpty) {
      _applyImported(fresh, 'replace');
      return;
    }
    final existing = _config.cases.length;
    _showDialog(PerfConfirmDialog(
      title: sourceLabel,
      message:
          '$existing case${existing == 1 ? "" : "s"} already in editor.\n\nAppend → ${existing + fresh.length} total. Replace all → ${fresh.length} total.',
      onCancel: _closeDialog,
      actions: [
        PerfConfirmAction(
          label: 'Append → ${existing + fresh.length}',
          onPressed: () {
            _closeDialog();
            _applyImported(fresh, 'append');
          },
        ),
        PerfConfirmAction(
          label: 'Replace → ${fresh.length}',
          destructive: true,
          onPressed: () {
            _closeDialog();
            _applyImported(fresh, 'replace');
          },
        ),
      ],
    ));
  }

  // ── Run ────────────────────────────────────────────────────────────────

  Future<void> _handleRun() async {
    final trimmedTarget = _config.targetRoute.trim();
    final trimmedBounce = _config.bounceRoute.trim();
    if (trimmedBounce.isEmpty) {
      _notice('Missing bounce', 'Pick a bounce route.');
      return;
    }
    if (_config.cases.isEmpty) {
      _notice('No cases', 'Add at least one case to run.');
      return;
    }
    if (!automationRunner.canRun()) {
      _notice(
        'Navigation unavailable',
        'Automated benchmarks need a GoRouter registered with buoy_routes: '
            'call registerBuoyRoutes(router: myRouter).',
      );
      return;
    }

    final normalized = _config.copyWith(
      targetRoute: trimmedTarget,
      bounceRoute: trimmedBounce,
    );

    // Hard errors block the run; unknown-sitemap warnings become a soft
    // confirm so the user can proceed if the sitemap is incomplete.
    final normalizedBounce = normalizePathname(trimmedBounce);
    var missingRoute = 0;
    var bounceClash = 0;
    var unknownSitemap = 0;
    for (final c in normalized.cases) {
      final resolved = resolveCaseRoute(c, normalized.targetRoute);
      if (resolved.isEmpty) {
        missingRoute += 1;
        continue;
      }
      if (normalizePathname(resolved) == normalizedBounce) bounceClash += 1;
      if (validateRouteAgainstSitemap(resolved, _sitemap) == 'unknown') {
        unknownSitemap += 1;
      }
    }
    if (missingRoute > 0) {
      _notice(
        'Missing route',
        '$missingRoute case${missingRoute == 1 ? " has" : "s have"} no route and no default Target. Set a target or paste cases with routes.',
      );
      return;
    }
    if (bounceClash > 0) {
      _notice(
        'Bounce equals case route',
        '$bounceClash case${bounceClash == 1 ? "" : "s"} navigates to the bounce route — no remount can happen. Pick a bounce route that no case uses.',
      );
      return;
    }

    Future<void> start() async {
      await AutomationConfigStore.instance.save(normalized);
      try {
        // The parent modal listens for runner status and navigates to the
        // batch report itself when "done" fires.
        await automationRunner.start(normalized);
      } catch (err) {
        if (!mounted) return;
        _notice('Could not start',
            err is StateError ? err.message : err.toString());
      }
    }

    if (unknownSitemap > 0) {
      _showDialog(PerfConfirmDialog(
        title: 'Routes not in sitemap',
        message:
            '$unknownSitemap case${unknownSitemap == 1 ? " uses a route" : "s use routes"} not found in your app\'s sitemap. They may navigate-fail at runtime.',
        onCancel: _closeDialog,
        actions: [
          PerfConfirmAction(
            label: 'Run anyway',
            onPressed: () {
              _closeDialog();
              // ignore: discarded_futures
              start();
            },
          ),
        ],
      ));
      return;
    }

    await start();
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_status.isActive) return _RunningPanel(status: _status);

    final canRun = automationRunner.canRun();

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!canRun) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: MacOSColors.warningBackground,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color:
                        MacOSColors.warning.withValues(alpha: 0x66 / 255),
                  ),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Navigation unavailable',
                      style: TextStyle(
                        color: MacOSColors.warning,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Automated benchmarks need a GoRouter registered with '
                      'buoy_routes. Manual recording from the HUD still works.',
                      style: TextStyle(
                        color: MacOSColors.textSecondary,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],

            // ── Target ────────────────────────────────────────────────
            _Section(
              title: 'Target',
              children: [
                const _FieldLabel(
                  'Default route (optional — used when a case has no route of its own)',
                ),
                _RouteValueRow(
                  value: _config.targetRoute,
                  placeholder: 'Pick a route… (optional)',
                  onBrowse: () => setState(() => _routePickerFor = 'target'),
                ),
                const _FieldLabel('Bounce route (forces remount between cases)'),
                _RouteValueRow(
                  value: _config.bounceRoute,
                  placeholder: 'Pick a route…',
                  onBrowse: () => setState(() => _routePickerFor = 'bounce'),
                ),
                const _FieldLabel('Speed preset'),
                _SpeedPresetSelector(
                  config: _config,
                  onPick: (preset) {
                    _update((prev) => applySpeedPreset(prev, preset));
                    _syncControllers();
                  },
                ),
                const _FieldLabel('Per-case duration (ms)'),
                _NumberField(
                  controller: _durationCtrl,
                  onChanged: (v) => _update(
                    (p) => p.copyWith(perCaseDurationMs: v ?? 0),
                  ),
                ),
                TouchableOpacity(
                  activeOpacity: 0.7,
                  onTap: () => setState(() => _showAdvanced = !_showAdvanced),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      _showAdvanced ? 'Hide advanced' : 'Show advanced',
                      style: const TextStyle(
                        color: MacOSColors.info,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                if (_showAdvanced) ...[
                  const _FieldLabel('Runs per case (1-10)'),
                  _NumberField(
                    controller: _runsCtrl,
                    onChanged: (v) => _update(
                      (p) => p.copyWith(
                        runsPerCase: (v ?? 3).clamp(1, 10),
                      ),
                    ),
                  ),
                  const _FieldLabel('Cool-down between runs (ms, 0-30000)'),
                  _NumberField(
                    controller: _coolDownCtrl,
                    onChanged: (v) => _update(
                      (p) => p.copyWith(
                        coolDownMs: (v ?? 2000).clamp(0, 30000),
                      ),
                    ),
                  ),
                  const _FieldLabel('Discard warmup runs (0 = keep all)'),
                  _NumberField(
                    controller: _warmupCtrl,
                    onChanged: (v) => _update(
                      (p) => p.copyWith(
                        discardWarmupRuns:
                            (v ?? 0).clamp(0, (p.runsPerCase - 1).clamp(0, 9)),
                      ),
                    ),
                  ),
                  const _FieldLabel('Settle delay before recording (ms)'),
                  _NumberField(
                    controller: _settleCtrl,
                    onChanged: (v) =>
                        _update((p) => p.copyWith(settleMs: v ?? 0)),
                  ),
                  const _FieldLabel('Navigation timeout (ms)'),
                  _NumberField(
                    controller: _navTimeoutCtrl,
                    onChanged: (v) =>
                        _update((p) => p.copyWith(navTimeoutMs: v ?? 0)),
                  ),
                  _ToggleRow(
                    label: 'Shuffle case order',
                    hint:
                        'Randomize case execution order (seeded by batch id, so '
                        'resumes still work). Use when comparing >3 cases at high '
                        'CPU/GPU load — without it, late cases get thermally '
                        'throttled scores that mask the real per-case perf signal.',
                    value: _config.shuffleCases,
                    onChanged: (v) =>
                        _update((p) => p.copyWith(shuffleCases: v)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),

            // ── Cases ─────────────────────────────────────────────────
            _Section(
              title: 'Cases',
              actions: [
                if (_config.cases.isNotEmpty)
                  _SmallButton(
                    label: 'Clear',
                    destructive: true,
                    onTap: () => _showDialog(PerfConfirmDialog(
                      title:
                          'Clear ${_config.cases.length} case${_config.cases.length == 1 ? "" : "s"}?',
                      message:
                          'This only resets the editor — saved batch reports are kept.',
                      onCancel: _closeDialog,
                      actions: [
                        PerfConfirmAction(
                          label: 'Clear',
                          destructive: true,
                          onPressed: () {
                            _closeDialog();
                            _update((p) => p.copyWith(cases: const []));
                          },
                        ),
                      ],
                    )),
                  ),
                if (_config.cases.isNotEmpty)
                  _SmallButton(
                    label: 'Copy',
                    // ignore: discarded_futures
                    onTap: () => _handleCopyCases(),
                  ),
                _SmallButton(
                  label: 'Saved',
                  onTap: () => setState(() => _showSavedCases = true),
                ),
                _SmallButton(
                  label: _clipboardCaseCount > 0
                      ? 'Paste $_clipboardCaseCount case${_clipboardCaseCount == 1 ? "" : "s"}'
                      : 'Paste cases',
                  // ignore: discarded_futures
                  onTap: () => _handleBulkPaste(),
                ),
                _SmallButton(
                  label: 'Add case',
                  primary: true,
                  icon: BuoyIcons.plus,
                  onTap: _addCase,
                ),
              ],
              children: [
                if (_config.cases.isEmpty)
                  const Text(
                    'No cases yet. Tap "Add case" for each variant you want to '
                    'compare — the first one is shown as the baseline column in '
                    'the report.',
                    style: TextStyle(
                      color: MacOSColors.textMuted,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  )
                else
                  // Bounded scroll: ~3 collapsed case cards fit before the
                  // inner scroll engages, keeping the form skimmable when a
                  // 14-case batch is pasted in.
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 420),
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.only(bottom: 4),
                      itemCount: _config.cases.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final c = _config.cases[i];
                        return _CaseEditor(
                          key: ValueKey(c.id),
                          index: i,
                          value: c,
                          defaultRoute: _config.targetRoute,
                          sitemap: _sitemap,
                          onChanged: () => setState(() {}),
                          onDuplicate: () => _duplicateCase(c.id),
                          onRemove: () => _removeCase(c.id),
                        );
                      },
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),

            // ── Run ───────────────────────────────────────────────────
            Opacity(
              opacity: (!canRun || _config.cases.isEmpty) ? 0.5 : 1,
              child: TouchableOpacity(
                activeOpacity: 0.8,
                onTap: (!canRun || _config.cases.isEmpty)
                    ? null
                    // ignore: discarded_futures
                    : () => _handleRun(),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: MacOSColors.info,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _formatRunButtonLabel(
                      _config.cases.length,
                      _config.runsPerCase,
                    ),
                    style: const TextStyle(
                      color: Color(0xFF0A0A0C),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),

        if (_routePickerFor != null)
          _RoutePickerModal(
            title: _routePickerFor == 'bounce'
                ? 'Pick bounce route'
                : 'Pick target route',
            currentValue: _routePickerFor == 'bounce'
                ? _config.bounceRoute
                : _config.targetRoute,
            onCancel: () => setState(() => _routePickerFor = null),
            onSelect: (path) {
              final which = _routePickerFor;
              setState(() => _routePickerFor = null);
              if (which == 'bounce') {
                _update((p) => p.copyWith(bounceRoute: path));
              } else {
                _update((p) => p.copyWith(targetRoute: path));
              }
            },
          ),

        if (_showSavedCases)
          _SavedCasesModal(
            currentCases: _config.cases,
            onClose: () => setState(() => _showSavedCases = false),
            onLoad: (set) {
              setState(() => _showSavedCases = false);
              _applyCaseList(set.cases, 'Load "${set.name}"');
            },
            onConfirm: _showDialog,
            onDismissConfirm: _closeDialog,
          ),

        ?_dialog,
      ],
    );
  }
}

/// Button label that surfaces total recordings up front so the user
/// understands the time cost (RN `formatRunButtonLabel`).
String _formatRunButtonLabel(int cases, int runsPerCase) {
  final caseWord = cases == 1 ? 'case' : 'cases';
  if (runsPerCase <= 1) return 'Run $cases $caseWord';
  return 'Run $cases $caseWord × $runsPerCase runs = ${cases * runsPerCase} recordings';
}

String _describePhase(AutomationStatus status) {
  final remaining = status.remainingMs ?? 0;
  String secs() => '${((remaining / 100).ceil() / 10).toStringAsFixed(1)}s';
  switch (status.phase) {
    case 'idle':
      return 'Idle';
    case 'navigating-bounce':
      return 'Bouncing through neutral route…';
    case 'navigating-target':
      return 'Loading target with case params…';
    case 'settling':
      return 'Settling… ${secs()}';
    case 'recording':
      return 'Recording… ${secs()} left';
    case 'saving':
      return 'Saving…';
    case 'cooling-down':
      return 'Cooling down… ${secs()}';
    case 'reloading':
      return 'Reloading app…';
    case 'done':
      return 'Done.';
    case 'cancelled':
      return 'Cancelled.';
    default:
      return '';
  }
}

/// In-progress panel replacing the form while a batch runs (RN `RunningPanel`).
class _RunningPanel extends StatelessWidget {
  const _RunningPanel({required this.status});
  final AutomationStatus status;

  @override
  Widget build(BuildContext context) {
    final showProgress = const {
      'navigating-bounce',
      'navigating-target',
      'settling',
      'recording',
      'saving',
      'cooling-down',
    }.contains(status.phase);
    final showRun = showProgress && (status.runTotal ?? 1) > 1;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: MacOSColors.backgroundCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: MacOSColors.borderDefault),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Batch in progress…',
                style: TextStyle(
                  color: MacOSColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _describePhase(status),
                style: const TextStyle(
                  color: MacOSColors.info,
                  fontSize: 13,
                  fontFamily: _mono,
                ),
              ),
              if (showProgress && status.index != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Case ${status.index! + 1} of ${status.total}'
                  '${showRun ? ", run ${status.runIndex! + 1} of ${status.runTotal}" : ""}',
                  style: const TextStyle(
                    color: MacOSColors.textSecondary,
                    fontSize: 12,
                    fontFamily: _mono,
                  ),
                ),
                Text(
                  status.caseName ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: MacOSColors.textSecondary,
                    fontSize: 12,
                    fontFamily: _mono,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              TouchableOpacity(
                activeOpacity: 0.8,
                onTap: automationRunner.cancel,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: MacOSColors.errorBackground,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color:
                          MacOSColors.error.withValues(alpha: 0x66 / 255),
                    ),
                  ),
                  child: const Text(
                    'Cancel run',
                    style: TextStyle(
                      color: MacOSColors.error,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Tip: leave the app foregrounded so samples aren\'t dropped. The page '
          'will visibly bounce between routes — that\'s expected.',
          style: TextStyle(
            color: MacOSColors.textMuted,
            fontSize: 12,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

// ── Case editor ───────────────────────────────────────────────────────────

class _CaseEditor extends StatelessWidget {
  const _CaseEditor({
    super.key,
    required this.index,
    required this.value,
    required this.defaultRoute,
    required this.sitemap,
    required this.onChanged,
    required this.onDuplicate,
    required this.onRemove,
  });

  final int index;
  final AutomationCase value;

  /// Top-level Target route, used as the fallback display when no own route.
  final String defaultRoute;
  final List<String> sitemap;
  final VoidCallback onChanged;
  final VoidCallback onDuplicate;
  final VoidCallback onRemove;

  String _fallbackName() => index == 0 ? 'baseline' : 'case ${index + 1}';

  String _derivedName(Map<String, String> params) {
    final formatted = formatParams(params);
    return formatted.isNotEmpty ? formatted : _fallbackName();
  }

  @override
  Widget build(BuildContext context) {
    final ownRoute = value.route?.trim() ?? '';
    final trimmedDefault = defaultRoute.trim();
    final resolvedRoute = ownRoute.isNotEmpty ? ownRoute : trimmedDefault;
    final routeStatus = resolvedRoute.isNotEmpty
        ? validateRouteAgainstSitemap(resolvedRoute, sitemap)
        : 'skipped';
    final routeDisplay = ownRoute.isNotEmpty
        ? ownRoute
        : (trimmedDefault.isNotEmpty
            ? '$trimmedDefault (default target)'
            : '(no route)');
    final routeIsFallback = ownRoute.isEmpty;
    final entries = value.params.entries.toList();

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: MacOSColors.backgroundBase,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MacOSColors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: MacOSColors.infoBackground,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  index == 0 ? 'BASE' : '$index',
                  style: const TextStyle(
                    color: MacOSColors.info,
                    fontSize: 9,
                    fontFamily: _mono,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _derivedName(value.params),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: MacOSColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      routeDisplay,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: routeIsFallback
                            ? MacOSColors.textMuted
                            : MacOSColors.textSecondary,
                        fontSize: 11,
                        fontFamily: _mono,
                      ),
                    ),
                    if (routeStatus == 'unknown')
                      const Text(
                        '⚠ not in sitemap',
                        style: TextStyle(
                          color: MacOSColors.warning,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
              _IconButton(
                icon: BuoyIcons.copy,
                color: MacOSColors.textMuted,
                onTap: onDuplicate,
              ),
              _IconButton(
                icon: BuoyIcons.trash2,
                color: MacOSColors.error,
                onTap: onRemove,
              ),
            ],
          ),
          if (entries.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'No params — this case loads the route as-is.',
                style: TextStyle(
                  color: MacOSColors.textMuted,
                  fontSize: 12,
                ),
              ),
            ),
          for (final entry in entries)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Expanded(
                    child: _ParamField(
                      initialValue: entry.key,
                      hint: 'key',
                      onChanged: (next) {
                        final rebuilt = <String, String>{};
                        for (final e in value.params.entries) {
                          if (e.key == entry.key) {
                            if (next.isEmpty) continue;
                            rebuilt[next] = e.value;
                          } else {
                            rebuilt[e.key] = e.value;
                          }
                        }
                        value.params = rebuilt;
                        value.name = _derivedName(rebuilt);
                        onChanged();
                      },
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Text('=',
                        style: TextStyle(color: MacOSColors.textMuted)),
                  ),
                  Expanded(
                    child: _ParamField(
                      initialValue: entry.value,
                      hint: 'value',
                      onChanged: (next) {
                        value.params = {...value.params, entry.key: next};
                        value.name = _derivedName(value.params);
                        onChanged();
                      },
                    ),
                  ),
                  _IconButton(
                    icon: BuoyIcons.x,
                    color: MacOSColors.textMuted,
                    onTap: () {
                      final next = {...value.params}..remove(entry.key);
                      value.params = next;
                      value.name = _derivedName(next);
                      onChanged();
                    },
                  ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TouchableOpacity(
              activeOpacity: 0.7,
              onTap: () {
                var key = 'param';
                var i = 1;
                while (value.params.containsKey(key)) {
                  key = 'param${i++}';
                }
                final next = {...value.params, key: ''};
                value.params = next;
                value.name = _derivedName(next);
                onChanged();
              },
              child: const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    BuoyGlyph(BuoyIcons.plus, size: 12, color: MacOSColors.info),
                    SizedBox(width: 4),
                    Text(
                      'Add param',
                      style: TextStyle(
                        color: MacOSColors.info,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
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

/// Param key/value input. Uses a controller listener rather than
/// `onChanged` — the iOS simulator's hardware keyboard skips
/// `TextField.onChanged` (verified during the network-tool port).
class _ParamField extends StatefulWidget {
  const _ParamField({
    required this.initialValue,
    required this.hint,
    required this.onChanged,
  });
  final String initialValue;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  State<_ParamField> createState() => _ParamFieldState();
}

class _ParamFieldState extends State<_ParamField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue);

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      if (_controller.text != widget.initialValue) {
        widget.onChanged(_controller.text);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      PerfTextField(controller: _controller, hintText: widget.hint);
}

// ── Route picker ─────────────────────────────────────────────────────────

class _RoutePickerModal extends StatefulWidget {
  const _RoutePickerModal({
    required this.title,
    required this.currentValue,
    required this.onCancel,
    required this.onSelect,
  });

  final String title;
  final String currentValue;
  final VoidCallback onCancel;
  final ValueChanged<String> onSelect;

  @override
  State<_RoutePickerModal> createState() => _RoutePickerModalState();
}

class _RoutePickerModalState extends State<_RoutePickerModal> {
  final _queryCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _queryCtrl.addListener(() {
      if (_queryCtrl.text != _query) setState(() => _query = _queryCtrl.text);
    });
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  bool _matches(String path) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return path.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final allRoutes = getRouteList();
    final stack = getNavigationStack();
    final currentPathname = getCurrentRoute();

    // Stack entries minus the current pathname — it shows above as its own CTA.
    final stackEntries = [
      for (final s in stack)
        if (s.pathname != currentPathname) s,
    ];
    final drop = <String>{
      if (currentPathname.isNotEmpty) currentPathname,
      for (final s in stackEntries) s.pathname,
    };
    final otherRoutes = [
      for (final p in allRoutes)
        if (!drop.contains(p)) p,
    ];

    final filteredStack = [
      for (final s in stackEntries)
        if (_matches(s.pathname)) s,
    ];
    final filteredOther = [
      for (final p in otherRoutes)
        if (_matches(p)) p,
    ];
    final currentMatches =
        currentPathname.isNotEmpty && _matches(currentPathname);
    final totalVisible =
        (currentMatches ? 1 : 0) + filteredStack.length + filteredOther.length;

    return PerfDialogShell(
      onDismiss: widget.onCancel,
      maxWidth: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  style: const TextStyle(
                    color: MacOSColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _IconButton(
                icon: BuoyIcons.x,
                color: MacOSColors.textMuted,
                onTap: widget.onCancel,
              ),
            ],
          ),
          const SizedBox(height: 10),
          PerfTextField(controller: _queryCtrl, hintText: 'Filter routes…'),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: ListView(
              shrinkWrap: true,
              children: [
                if (currentMatches) ...[
                  const _ListHeader('CURRENT ROUTE'),
                  TouchableOpacity(
                    activeOpacity: 0.8,
                    onTap: () => widget.onSelect(currentPathname),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: MacOSColors.info,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Use current page',
                                  style: TextStyle(
                                    color: Color(0xFF0A0A0C),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  currentPathname,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xCC0A0A0C),
                                    fontSize: 11,
                                    fontFamily: _mono,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const BuoyGlyph(BuoyIcons.chevronRight,
                              size: 14, color: Color(0xFF0A0A0C)),
                        ],
                      ),
                    ),
                  ),
                ],
                if (filteredStack.isNotEmpty) ...[
                  _ListHeader('NAVIGATION STACK (${filteredStack.length})'),
                  for (final entry in filteredStack)
                    _RouteRow(
                      pathname: entry.pathname,
                      badge: entry.isFocused ? 'TOP' : '#${entry.index}',
                      badgeActive: entry.isFocused,
                      selected: entry.pathname == widget.currentValue,
                      onTap: () => widget.onSelect(entry.pathname),
                    ),
                ],
                if (filteredOther.isNotEmpty) ...[
                  _ListHeader('ALL ROUTES (${filteredOther.length})'),
                  for (final path in filteredOther)
                    _RouteRow(
                      pathname: path,
                      selected: path == widget.currentValue,
                      onTap: () => widget.onSelect(path),
                    ),
                ],
                if (currentPathname.isEmpty &&
                    allRoutes.isEmpty &&
                    stackEntries.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'No routes available. Either buoy_routes isn\'t registered, '
                      'or no GoRouter has been attached yet.',
                      style: TextStyle(
                        color: MacOSColors.textMuted,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                if (totalVisible == 0 && _query.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'No routes match "$_query".',
                      style: const TextStyle(
                        color: MacOSColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteRow extends StatelessWidget {
  const _RouteRow({
    required this.pathname,
    required this.selected,
    required this.onTap,
    this.badge,
    this.badgeActive = false,
  });

  final String pathname;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;
  final bool badgeActive;

  @override
  Widget build(BuildContext context) {
    return TouchableOpacity(
      activeOpacity: 0.7,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? MacOSColors.infoBackground
              : MacOSColors.backgroundInput,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? MacOSColors.info : MacOSColors.borderDefault,
          ),
        ),
        child: Row(
          children: [
            if (badge != null) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: badgeActive
                      ? MacOSColors.successBackground
                      : MacOSColors.backgroundHover,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  badge!,
                  style: TextStyle(
                    color: badgeActive
                        ? MacOSColors.success
                        : MacOSColors.textMuted,
                    fontSize: 9,
                    fontFamily: _mono,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                pathname,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: MacOSColors.textPrimary,
                  fontSize: 12,
                  fontFamily: _mono,
                ),
              ),
            ),
            BuoyGlyph(
              BuoyIcons.chevronRight,
              size: 14,
              color: selected ? MacOSColors.info : MacOSColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Saved case sets ──────────────────────────────────────────────────────

class _SavedCasesModal extends StatefulWidget {
  const _SavedCasesModal({
    required this.currentCases,
    required this.onClose,
    required this.onLoad,
    required this.onConfirm,
    required this.onDismissConfirm,
  });

  final List<AutomationCase> currentCases;
  final VoidCallback onClose;
  final ValueChanged<SavedCaseSet> onLoad;
  final ValueChanged<Widget> onConfirm;
  final VoidCallback onDismissConfirm;

  @override
  State<_SavedCasesModal> createState() => _SavedCasesModalState();
}

class _SavedCasesModalState extends State<_SavedCasesModal> {
  final _nameCtrl = TextEditingController();
  List<SavedCaseSet> _sets = CaseSetsStore.instance.current;
  void Function()? _unsub;

  @override
  void initState() {
    super.initState();
    _unsub = CaseSetsStore.instance.subscribe((sets) {
      if (mounted) setState(() => _sets = sets);
    });
    _nameCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _unsub?.call();
    _nameCtrl.dispose();
    super.dispose();
  }

  void _handleSave() {
    final trimmed = _nameCtrl.text.trim();
    if (trimmed.isEmpty || widget.currentCases.isEmpty) return;
    Future<void> doSave() async {
      await CaseSetsStore.instance.save(trimmed, widget.currentCases);
      if (mounted) _nameCtrl.clear();
    }

    // Re-saving an existing name overwrites it — confirm so a typo'd collision
    // doesn't silently clobber a different set.
    if (CaseSetsStore.instance.nameExists(trimmed)) {
      widget.onConfirm(PerfConfirmDialog(
        title: 'Overwrite "$trimmed"?',
        message: 'A saved set with this name already exists.',
        onCancel: widget.onDismissConfirm,
        actions: [
          PerfConfirmAction(
            label: 'Overwrite',
            destructive: true,
            onPressed: () {
              widget.onDismissConfirm();
              // ignore: discarded_futures
              doSave();
            },
          ),
        ],
      ));
    } else {
      // ignore: discarded_futures
      doSave();
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSave =
        _nameCtrl.text.trim().isNotEmpty && widget.currentCases.isNotEmpty;
    final n = widget.currentCases.length;

    return PerfDialogShell(
      onDismiss: widget.onClose,
      maxWidth: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Saved case sets',
                  style: TextStyle(
                    color: MacOSColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _IconButton(
                icon: BuoyIcons.x,
                color: MacOSColors.textMuted,
                onTap: widget.onClose,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: PerfTextField(
                  controller: _nameCtrl,
                  hintText: n > 0
                      ? 'Name this set (e.g. test all)'
                      : 'Add cases to the editor first',
                  onSubmitted: (_) => _handleSave(),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 84,
                child: PerfDialogButton(
                  label: 'Save',
                  primary: true,
                  disabled: !canSave,
                  onTap: _handleSave,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            n > 0
                ? 'Saves the $n case${n == 1 ? "" : "s"} in the editor. Re-using a name overwrites it.'
                : 'Nothing to save yet — build a case list in the editor, then save it here to reuse later.',
            style: const TextStyle(
              color: MacOSColors.textMuted,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: ListView(
              shrinkWrap: true,
              children: [
                if (_sets.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'No saved sets yet. Build a matrix above, name it, and tap Save.',
                      style: TextStyle(
                        color: MacOSColors.textMuted,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  )
                else ...[
                  _ListHeader('SAVED (${_sets.length})'),
                  for (final set in _sets)
                    Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      decoration: BoxDecoration(
                        color: MacOSColors.backgroundInput,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: MacOSColors.borderDefault),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TouchableOpacity(
                              activeOpacity: 0.7,
                              onTap: () => widget.onLoad(set),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 9,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            set.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: MacOSColors.textPrimary,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          Text(
                                            '${set.cases.length} case${set.cases.length == 1 ? "" : "s"}',
                                            style: const TextStyle(
                                              color: MacOSColors.textMuted,
                                              fontSize: 11,
                                              fontFamily: _mono,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const BuoyGlyph(
                                      BuoyIcons.chevronRight,
                                      size: 14,
                                      color: MacOSColors.textMuted,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          _IconButton(
                            icon: BuoyIcons.trash2,
                            color: MacOSColors.error,
                            onTap: () => widget.onConfirm(PerfConfirmDialog(
                              title: 'Delete "${set.name}"?',
                              message: 'This can\'t be undone.',
                              onCancel: widget.onDismissConfirm,
                              actions: [
                                PerfConfirmAction(
                                  label: 'Delete',
                                  destructive: true,
                                  onPressed: () {
                                    widget.onDismissConfirm();
                                    // ignore: discarded_futures
                                    CaseSetsStore.instance.delete(set.id);
                                  },
                                ),
                              ],
                            )),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Small shared pieces ──────────────────────────────────────────────────

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.children,
    this.actions = const [],
  });

  final String title;
  final List<Widget> children;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MacOSColors.backgroundCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MacOSColors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: MacOSColors.borderDefault),
              ),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: 8,
              spacing: 8,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    title.toUpperCase(),
                    style: const TextStyle(
                      color: MacOSColors.textSecondary,
                      fontSize: 11,
                      letterSpacing: 1,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (actions.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    alignment: WrapAlignment.end,
                    children: actions,
                  ),
              ],
            ),
          ),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final child in children) ...[
                  child,
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            color: MacOSColors.textMuted,
            fontSize: 11,
            letterSpacing: 0.4,
          ),
        ),
      );
}

class _RouteValueRow extends StatelessWidget {
  const _RouteValueRow({
    required this.value,
    required this.placeholder,
    required this.onBrowse,
  });

  final String value;
  final String placeholder;
  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    return TouchableOpacity(
      activeOpacity: 0.7,
      onTap: onBrowse,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: MacOSColors.backgroundInput,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: MacOSColors.borderDefault),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                value.isNotEmpty ? value : placeholder,
                style: TextStyle(
                  color: value.isNotEmpty
                      ? MacOSColors.textPrimary
                      : MacOSColors.textMuted,
                  fontSize: 13,
                  fontFamily: _mono,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: MacOSColors.backgroundHover,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: MacOSColors.borderDefault),
              ),
              child: const Text(
                'Browse',
                style: TextStyle(
                  color: MacOSColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpeedPresetSelector extends StatelessWidget {
  const _SpeedPresetSelector({required this.config, required this.onPick});
  final AutomationConfig config;
  final ValueChanged<AutomationSpeedPreset> onPick;

  @override
  Widget build(BuildContext context) {
    final active = detectSpeedPreset(config);
    final hint = active != null
        ? speedPresetHints[active]!
        : 'Custom tuning — pick a preset to reset to known-good defaults.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (final preset in AutomationSpeedPreset.values) ...[
              if (preset != AutomationSpeedPreset.values.first)
                const SizedBox(width: 8),
              Expanded(
                child: TouchableOpacity(
                  activeOpacity: 0.7,
                  onTap: () => onPick(preset),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: active == preset
                          ? MacOSColors.infoBackground
                          : MacOSColors.backgroundInput,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: active == preset
                            ? MacOSColors.info
                            : MacOSColors.borderDefault,
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          preset == AutomationSpeedPreset.fast
                              ? 'Fast'
                              : 'Slow',
                          style: TextStyle(
                            color: active == preset
                                ? MacOSColors.info
                                : MacOSColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          preset == AutomationSpeedPreset.fast
                              ? '~4 min · cooling pad'
                              : '~9 min · room temp',
                          style: TextStyle(
                            color: active == preset
                                ? MacOSColors.info
                                : MacOSColors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Text(
          hint,
          style: const TextStyle(
            color: MacOSColors.textMuted,
            fontSize: 12,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}

class _NumberField extends StatefulWidget {
  const _NumberField({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final ValueChanged<int?> onChanged;

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  String _last = '';

  @override
  void initState() {
    super.initState();
    _last = widget.controller.text;
    widget.controller.addListener(_onText);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    super.dispose();
  }

  void _onText() {
    final text = widget.controller.text;
    if (text == _last) return;
    _last = text;
    final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
    widget.onChanged(digits.isEmpty ? null : int.tryParse(digits));
  }

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: MacOSColors.backgroundInput,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: MacOSColors.borderDefault),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: TextField(
          controller: widget.controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          cursorColor: MacOSColors.info,
          style: const TextStyle(
            color: MacOSColors.textPrimary,
            fontSize: 13,
            fontFamily: _mono,
            decoration: TextDecoration.none,
          ),
          decoration: const InputDecoration(
            isDense: true,
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(vertical: 10),
          ),
        ),
      );
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.hint,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: MacOSColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hint,
                  style: const TextStyle(
                    color: MacOSColors.textMuted,
                    fontSize: 11,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          PerfMiniToggle(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// Compact 36×20 toggle replacing the platform Switch (RN `MiniToggle`).
class PerfMiniToggle extends StatelessWidget {
  const PerfMiniToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return TouchableOpacity(
      activeOpacity: 0.7,
      onTap: () => onChanged(!value),
      child: Container(
        width: 36,
        height: 20,
        padding: const EdgeInsets.all(2),
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        decoration: BoxDecoration(
          color: value
              ? MacOSColors.success.withValues(alpha: 0x33 / 255)
              : MacOSColors.backgroundInput,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: value ? MacOSColors.success : MacOSColors.borderDefault,
          ),
        ),
        child: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: value ? MacOSColors.success : MacOSColors.textMuted,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({
    required this.label,
    required this.onTap,
    this.primary = false,
    this.destructive = false,
    this.icon,
  });

  final String label;
  final VoidCallback onTap;
  final bool primary;
  final bool destructive;
  final LucideIcon? icon;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    Color border;
    if (primary) {
      bg = MacOSColors.info;
      fg = const Color(0xFF0A0A0C);
      border = MacOSColors.info;
    } else if (destructive) {
      bg = MacOSColors.errorBackground;
      fg = MacOSColors.error;
      border = MacOSColors.error.withValues(alpha: 0x55 / 255);
    } else {
      bg = MacOSColors.backgroundInput;
      fg = MacOSColors.textPrimary;
      border = MacOSColors.borderDefault;
    }
    return TouchableOpacity(
      activeOpacity: 0.7,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              BuoyGlyph(icon, size: 12, color: fg),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  const _IconButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final LucideIcon icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => TouchableOpacity(
        activeOpacity: 0.2,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: BuoyGlyph(icon, size: 14, color: color),
        ),
      );
}

class _ListHeader extends StatelessWidget {
  const _ListHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 6),
        child: Text(
          text,
          style: const TextStyle(
            color: MacOSColors.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
      );
}
