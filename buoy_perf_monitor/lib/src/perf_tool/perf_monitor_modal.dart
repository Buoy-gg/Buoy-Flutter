/// Ports packages/perf-monitor/src/perf-monitor/components/PerfMonitorModal.tsx.
///
/// The tool's root surface: a [JsModal] whose header carries the Single/Bulk
/// tab selector, a REC chip, search, the ⚡ Automate entry, the monitoring
/// power toggle, and an overflow menu (Filter & settings · Copy as JSON ·
/// Delete all). Views: **list** (Library of solo runs + collapsed batches,
/// with the inline live HUD pinned on top), **detail** (one run's stats +
/// timeline), **settings**, **diagnostics**, **automate**, **batch-report**
/// and **compare** — the last two both render [BatchReportView].
///
/// Behaviours ported 1:1: long-press → selection mode (bulk export/delete,
/// compare 2+ single runs), the persisted last-view (`modal-view` key,
/// load-then-save so the default doesn't clobber the restore), auto-landing on
/// the batch report when the runner finishes, and auto-hiding the whole modal
/// while a batch runs (the progress pill is the user-facing UI then).
library;

import 'dart:convert';

import 'package:buoy_core/buoy_core.dart';
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';

import '../aggregate_library.dart';
import '../automation_runner.dart';
import '../benchmark_recorder.dart';
import '../benchmark_storage.dart';
import '../exporters.dart';
import '../modal_view_persistence.dart';
import '../perf_monitor_controller.dart';
import '../perf_settings.dart';
import '../perf_types.dart';
import 'automation_config_view.dart';
import 'batch_report_view.dart';
import 'perf_detail_view.dart';
import 'perf_dialogs.dart';
import 'perf_hud_surface.dart';

/// RN JsModal persistence key (`@react_buoy_<tool>_modal` convention).
const String _perfModalKey = '@react_buoy_perf_monitor_modal';

const String _mono = 'monospace';

/// The active screen inside the modal (RN `ModalView`).
class _View {
  const _View(this.kind, {this.report, this.batchId, this.reportIds});
  final String kind;
  final BenchmarkReport? report;
  final String? batchId;
  final List<String>? reportIds;

  PersistedModalView toPersisted() => switch (kind) {
        'detail' => PersistedModalView(kind: 'detail', reportId: report?.id),
        'batch-report' =>
          PersistedModalView(kind: 'batch-report', batchId: batchId),
        'compare' =>
          PersistedModalView(kind: 'compare', reportIds: reportIds),
        _ => PersistedModalView(kind: kind),
      };
}

class PerfMonitorModal extends StatefulWidget {
  const PerfMonitorModal({
    super.key,
    required this.storage,
    required this.onClose,
    this.onMinimize,
  });

  final BuoyStorage storage;
  final VoidCallback onClose;
  final VoidCallback? onMinimize;

  @override
  State<PerfMonitorModal> createState() => _PerfMonitorModalState();
}

class _PerfMonitorModalState extends State<PerfMonitorModal> {
  final _controller = PerfMonitorController.instance;

  _View _view = const _View('list');
  bool _viewLoaded = false;

  List<BenchmarkIndexEntry> _items = const [];
  bool _perfEnabled = PerfMonitorController.instance.isEnabled();
  bool _recording = benchmarkRecorder.isRecording();
  AutomationStatus _automation = automationRunner.getStatus();

  /// Selection mode: cards show a checkbox, the header becomes a bulk-action
  /// bar, and tap toggles selection instead of opening detail.
  final List<String> _selected = [];
  bool _selectionMode = false;

  /// Defaults to "bulk": almost every run comes from an automation batch.
  String _listTab = 'bulk';

  bool _isSearchActive = false;
  String _searchText = '';
  final _searchCtrl = TextEditingController();

  bool _showOverflow = false;
  Widget? _dialog;
  Widget? _savePrompt;

  void Function()? _unsubEnabled;
  void Function()? _unsubRecording;
  void Function()? _unsubIndex;
  void Function()? _unsubSaved;
  void Function()? _unsubAutomation;
  void Function()? _removeViewer;

  @override
  void initState() {
    super.initState();
    // Suppress the floating chip + keep sampling while the modal is open.
    // Deferred inside the controller — a synchronous notify from initState
    // would rebuild the overlay mid-build.
    _controller.setModalOpen(true);
    _removeViewer = _controller.addLiveViewer();

    _unsubEnabled = _controller.subscribeEnabled((e) {
      if (mounted) setState(() => _perfEnabled = e);
    });
    _unsubRecording = benchmarkRecorder.subscribe((r) {
      if (mounted) setState(() => _recording = r);
    });
    _unsubIndex = subscribeBenchmarkIndex(() {
      // ignore: discarded_futures
      _refresh();
    });
    _unsubSaved = benchmarkRecorder.subscribeSaved((_) {
      // ignore: discarded_futures
      _refresh();
    });
    _unsubAutomation = automationRunner.subscribe((status) {
      if (!mounted) return;
      setState(() => _automation = status);
      // Land on the batch report when the runner finishes, then acknowledge so
      // the same batch doesn't re-trigger on every reopen.
      if (status.phase == 'done' && status.batchId != null) {
        setState(() => _view = _View('batch-report', batchId: status.batchId));
        // ignore: discarded_futures
        _refresh();
        automationRunner.acknowledge();
      }
    });

    _searchCtrl.addListener(() {
      if (_searchCtrl.text != _searchText) {
        setState(() => _searchText = _searchCtrl.text);
      }
    });

    // ignore: discarded_futures
    PerfSettingsStore.instance.load();
    // ignore: discarded_futures
    _refresh();
    // ignore: discarded_futures
    _restoreView();
  }

  @override
  void dispose() {
    _unsubEnabled?.call();
    _unsubRecording?.call();
    _unsubIndex?.call();
    _unsubSaved?.call();
    _unsubAutomation?.call();
    _removeViewer?.call();
    _searchCtrl.dispose();
    // Hand the surface back to the floating chip once this frame settles.
    _controller.setModalOpen(false);
    super.dispose();
  }

  Future<void> _refresh() async {
    final list = await BenchmarkStorage.list();
    if (mounted) setState(() => _items = list);
  }

  /// Load-then-save: hold off persisting `_view` until the restore finishes,
  /// otherwise the initial `list` default clobbers what the user had open.
  Future<void> _restoreView() async {
    final persisted = await loadModalView();
    if (!mounted) {
      return;
    }
    if (persisted == null) {
      setState(() => _viewLoaded = true);
      return;
    }
    _View? restored;
    switch (persisted.kind) {
      case 'list':
      case 'settings':
      case 'automate':
      case 'diagnostics':
        restored = _View(persisted.kind);
      case 'batch-report':
        restored = _View('batch-report', batchId: persisted.batchId);
      case 'compare':
        // Drop ids whose reports were deleted since; fewer than 2 survivors is
        // meaningless — fall back to the list.
        final index = await BenchmarkStorage.list();
        final alive = {for (final e in index) e.id};
        final ids = [
          for (final id in persisted.reportIds ?? const <String>[])
            if (alive.contains(id)) id,
        ];
        if (ids.length >= 2) restored = _View('compare', reportIds: ids);
      case 'detail':
        final report = await BenchmarkStorage.load(persisted.reportId ?? '');
        if (report != null) restored = _View('detail', report: report);
    }
    if (!mounted) return;
    setState(() {
      if (restored != null) _view = restored;
      _viewLoaded = true;
    });
  }

  void _navigate(_View next) {
    setState(() {
      if (next.kind != 'list') {
        _selectionMode = false;
        _selected.clear();
      }
      _view = next;
    });
    if (_viewLoaded) {
      // ignore: discarded_futures
      saveModalView(next.toPersisted());
    }
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

  // ── Derived lists ──────────────────────────────────────────────────────

  List<LibraryItem> get _libraryItems => aggregateLibrary(_items);

  List<LibraryItem> get _activeItems {
    final q = _searchText.trim().toLowerCase();
    return [
      for (final item in _libraryItems)
        if ((_listTab == 'single') == !item.isBatch && _matchesSearch(item, q))
          item,
    ];
  }

  bool _matchesSearch(LibraryItem item, String q) {
    if (q.isEmpty) return true;
    if (!item.isBatch) {
      final e = item.entry!;
      return e.name.toLowerCase().contains(q) ||
          (e.route?.toLowerCase().contains(q) ?? false);
    }
    return (item.baselineName?.toLowerCase().contains(q) ?? false) ||
        (item.route?.toLowerCase().contains(q) ?? false) ||
        item.batchId.toLowerCase().contains(q);
  }

  int get _soloCountTotal => _libraryItems.where((i) => !i.isBatch).length;
  int get _batchCountTotal => _libraryItems.where((i) => i.isBatch).length;

  // ── Selection actions ──────────────────────────────────────────────────

  void _toggleSelect(String id) => setState(() {
        _selected.contains(id) ? _selected.remove(id) : _selected.add(id);
      });

  void _enterSelection(String id) => setState(() {
        _selectionMode = true;
        if (!_selected.contains(id)) _selected.add(id);
      });

  void _exitSelection() => setState(() {
        _selectionMode = false;
        _selected.clear();
      });

  void _switchListTab(String tab) => setState(() {
        // Selection is homogeneous per tab (run ids vs batch ids) — switching
        // clears it so bulk actions never have to ask which kind an id is.
        _listTab = tab;
        _selectionMode = false;
        _selected.clear();
      });

  void _handleBulkDelete() {
    if (_selected.isEmpty) return;
    final ids = [..._selected];
    final noun = _listTab == 'bulk' ? 'batch' : 'run';
    _showDialog(PerfConfirmDialog(
      title:
          'Delete ${ids.length} $noun${ids.length == 1 ? "" : (noun == "batch" ? "es" : "s")}?',
      message: 'This cannot be undone.',
      onCancel: _closeDialog,
      actions: [
        PerfConfirmAction(
          label: 'Delete',
          destructive: true,
          onPressed: () async {
            _closeDialog();
            if (_listTab == 'bulk') {
              for (final batchId in ids) {
                await BenchmarkStorage.deleteBatch(batchId);
              }
            } else {
              await BenchmarkStorage.deleteMany(ids);
            }
            await _refresh();
            _exitSelection();
          },
        ),
      ],
    ));
  }

  Future<void> _handleBulkExport() async {
    if (_selected.isEmpty) return;
    // On the bulk tab the selected ids are batch ids — expand them to child
    // run ids so the export is always a flat list of reports.
    List<String> reportIds;
    if (_listTab == 'bulk') {
      final byBatch = {
        for (final i in _libraryItems)
          if (i.isBatch) i.batchId: i.childIds,
      };
      reportIds = [for (final id in _selected) ...?byBatch[id]];
    } else {
      reportIds = [..._selected];
    }
    final reports = <BenchmarkReport>[];
    for (final id in reportIds) {
      final r = await BenchmarkStorage.load(id);
      if (r != null) reports.add(r);
    }
    if (!mounted) return;
    if (reports.isEmpty) {
      _notice('Missing', 'Selected benchmarks could not be loaded.');
      return;
    }
    await copyText(
      const JsonEncoder.withIndent('  ')
          .convert([for (final r in reports) r.toJson()]),
    );
    _exitSelection();
  }

  void _handleCompareSelected() {
    if (_selected.length < 2) return;
    _navigate(_View('compare', reportIds: [..._selected]));
  }

  Future<void> _handleCopyAll() async {
    final active = _activeItems;
    if (active.isEmpty) return;
    // Expand batches to their child entries so the JSON keeps the shape AI
    // tooling consumes — a flat BenchmarkIndexEntry[].
    final byId = {for (final e in _items) e.id: e};
    final flat = <BenchmarkIndexEntry>[];
    for (final item in active) {
      if (!item.isBatch) {
        flat.add(item.entry!);
      } else {
        for (final id in item.childIds) {
          final e = byId[id];
          if (e != null) flat.add(e);
        }
      }
    }
    await copyText(
      const JsonEncoder.withIndent('  ')
          .convert([for (final e in flat) e.toJson()]),
    );
  }

  void _handleDeleteAll() {
    _showDialog(PerfConfirmDialog(
      title: _listTab == 'bulk'
          ? 'Delete all batches?'
          : 'Delete all single runs?',
      message: 'This cannot be undone.',
      onCancel: _closeDialog,
      actions: [
        PerfConfirmAction(
          label: 'Delete all',
          destructive: true,
          onPressed: () async {
            _closeDialog();
            if (_listTab == 'bulk') {
              for (final item in _libraryItems) {
                if (item.isBatch) {
                  await BenchmarkStorage.deleteBatch(item.batchId);
                }
              }
            } else {
              await BenchmarkStorage.deleteMany([
                for (final e in _items)
                  if (e.batchId == null) e.id,
              ]);
            }
            setState(_selected.clear);
            await _refresh();
          },
        ),
      ],
    ));
  }

  Future<void> _openDetail(String id) async {
    final report = await BenchmarkStorage.load(id);
    if (!mounted) return;
    if (report == null) {
      _notice('Missing', 'That benchmark could not be loaded.');
      return;
    }
    _navigate(_View('detail', report: report));
  }

  // ── Build ──────────────────────────────────────────────────────────────

  String get _headerTitle => switch (_view.kind) {
        'detail' => _view.report?.metadata.name ?? '',
        'settings' => 'Settings',
        'automate' => 'Automate',
        'batch-report' => 'Batch report',
        'compare' => 'Compare',
        'diagnostics' => 'Diagnostics',
        // The list view repurposes the title slot for the tabs + REC chip.
        _ => '',
      };

  @override
  Widget build(BuildContext context) {
    // Auto-hide while a batch runs: the progress pill is the user-facing UI
    // then, and the modal would just cover the page under test.
    if (_automation.isActive) return const SizedBox.shrink();

    final inSelection = _view.kind == 'list' && _selectionMode;

    return JsModal(
      storage: widget.storage,
      onClose: widget.onClose,
      onMinimize: widget.onMinimize,
      persistenceKey: _perfModalKey,
      wrapChildInScrollView: false,
      headerContent: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: _header(inSelection),
      ),
      child: SizedBox.expand(
        child: ColoredBox(
          color: MacOSColors.backgroundBase,
          child: Stack(
            children: [
              Positioned.fill(child: _screen()),
              if (_showOverflow) _overflowMenu(),
              ?_savePrompt,
              ?_dialog,
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(bool inSelection) {
    return ModalHeader(
      children: [
        if (inSelection)
          TouchableOpacity(
            activeOpacity: 0.7,
            onTap: _exitSelection,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: MacOSColors.info,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          )
        else if (_view.kind != 'list')
          ModalHeaderBack(onBack: () => _navigate(const _View('list'))),
        // ModalHeaderContent is already an Expanded — don't wrap it in another
        // one or two ParentDataWidgets fight over the same render object.
        ModalHeaderContent(
          title: inSelection ? '' : _headerTitle,
          child: inSelection
              ? _chip('${_selected.length}', 'selected')
              : (_view.kind == 'list' ? _listHeaderContent() : null),
        ),
        ModalHeaderActions(children: _headerActions(inSelection)),
      ],
    );
  }

  Widget _listHeaderContent() {
    if (_isSearchActive) {
      return Container(
        decoration: BoxDecoration(
          color: MacOSColors.backgroundInput,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: MacOSColors.borderDefault),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
        child: Row(
          children: [
            const BuoyGlyph(BuoyIcons.search,
                size: 14, color: MacOSColors.textSecondary),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                cursorColor: MacOSColors.info,
                style: const TextStyle(
                  color: MacOSColors.textPrimary,
                  fontSize: 13,
                  decoration: TextDecoration.none,
                ),
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 8),
                  hintText: 'Search runs by name or route…',
                  hintStyle: TextStyle(
                    color: MacOSColors.textMuted,
                    fontSize: 13,
                  ),
                ),
                onSubmitted: (_) => setState(() => _isSearchActive = false),
              ),
            ),
            if (_searchText.isNotEmpty)
              TouchableOpacity(
                activeOpacity: 0.2,
                onTap: () => setState(() {
                  _searchCtrl.clear();
                  _isSearchActive = false;
                }),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: BuoyGlyph(BuoyIcons.x,
                      size: 14, color: MacOSColors.textSecondary),
                ),
              ),
          ],
        ),
      );
    }
    // RN gives the tab selector a fixed 200 (`styles.listTabSelector`) and lets
    // the row overflow invisibly on narrow layouts. Flutter paints an overflow
    // stripe instead, so 200 is a MAXIMUM here: the tabs shrink to fit and the
    // REC chip — the thing you actually need to see while recording — keeps its
    // intrinsic width.
    return Row(
      children: [
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: TabSelector(
              tabs: [
                (key: 'single', label: 'Single ($_soloCountTotal)'),
                (key: 'bulk', label: 'Bulk ($_batchCountTotal)'),
              ],
              activeTab: _listTab,
              onTabChange: _switchListTab,
            ),
          ),
        ),
        if (_recording) ...[
          const SizedBox(width: 8),
          _chip('REC', null, recording: true),
        ],
      ],
    );
  }

  Widget _chip(String value, String? label, {bool recording = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: recording
            ? MacOSColors.errorBackground
            : MacOSColors.backgroundHover,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: recording
              ? MacOSColors.error.withValues(alpha: 0x50 / 255)
              : MacOSColors.borderDefault,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (recording) ...[
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: MacOSColors.error,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
          ],
          Text(
            value,
            style: TextStyle(
              color: recording ? MacOSColors.error : MacOSColors.textPrimary,
              fontSize: 12,
              fontFamily: _mono,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (label != null) ...[
            const SizedBox(width: 4),
            Text(
              label.toUpperCase(),
              style: const TextStyle(
                color: MacOSColors.textMuted,
                fontSize: 11,
                fontFamily: _mono,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _headerActions(bool inSelection) {
    if (_view.kind == 'batch-report' || _view.kind == 'compare') {
      return [
        HeaderActionButton(
          icon: BuoyIcons.database,
          color: MacOSColors.textSecondary,
          onTap: () => _navigate(const _View('list')),
        ),
      ];
    }
    if (inSelection) {
      final count = _selected.length;
      return [
        if (_listTab == 'single')
          HeaderActionButton(
            icon: BuoyIcons.barChart,
            color: count >= 2 ? MacOSColors.info : MacOSColors.textDisabled,
            disabled: count < 2,
            onTap: _handleCompareSelected,
          ),
        HeaderActionButton(
          icon: BuoyIcons.copy,
          color: count > 0
              ? MacOSColors.textSecondary
              : MacOSColors.textDisabled,
          disabled: count == 0,
          // ignore: discarded_futures
          onTap: () => _handleBulkExport(),
        ),
        HeaderActionButton(
          icon: BuoyIcons.trash2,
          color: count > 0 ? MacOSColors.error : MacOSColors.textDisabled,
          disabled: count == 0,
          onTap: _handleBulkDelete,
        ),
      ];
    }
    if (_view.kind != 'list') return const [];
    // Action order mirrors the network tool: Search · Automate · Power · ⋮.
    return [
      HeaderActionButton(
        icon: BuoyIcons.search,
        color: MacOSColors.textSecondary,
        onTap: () => setState(() => _isSearchActive = true),
      ),
      HeaderActionButton(
        icon: BuoyIcons.zap,
        color: MacOSColors.warning,
        onTap: () => _navigate(const _View('automate')),
      ),
      PowerToggleButton(
        isEnabled: _perfEnabled,
        onToggle: () =>
            _perfEnabled ? _controller.disable() : _controller.enable(),
      ),
      HeaderActionButton(
        icon: BuoyIcons.moreVertical,
        color: MacOSColors.textSecondary,
        onTap: () => setState(() => _showOverflow = true),
      ),
    ];
  }

  /// Collapses the secondary list actions (Filter · Copy · Delete all) behind
  /// a single ⋮ button, as RN does on narrow layouts.
  Widget _overflowMenu() {
    final hasItems = _activeItems.isNotEmpty;
    Widget item(
      LucideIcon icon,
      String label,
      VoidCallback onTap, {
      bool disabled = false,
      bool destructive = false,
    }) {
      return TouchableOpacity(
        activeOpacity: 0.7,
        onTap: disabled
            ? null
            : () {
                setState(() => _showOverflow = false);
                onTap();
              },
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              SizedBox(
                width: 16,
                child: BuoyGlyph(
                  icon,
                  size: 15,
                  color: destructive
                      ? MacOSColors.error
                      : MacOSColors.textSecondary,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  color: disabled
                      ? MacOSColors.textDisabled
                      : (destructive
                          ? MacOSColors.error
                          : MacOSColors.textPrimary),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Positioned.fill(
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _showOverflow = false),
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            top: 4,
            right: 12,
            child: Container(
              constraints: const BoxConstraints(minWidth: 168),
              decoration: BoxDecoration(
                color: MacOSColors.backgroundCard,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: MacOSColors.borderDefault),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x59000000),
                    blurRadius: 14,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  item(BuoyIcons.filter, 'Filter & settings',
                      () => _navigate(const _View('settings'))),
                  item(
                    BuoyIcons.copy,
                    'Copy as JSON',
                    // ignore: discarded_futures
                    () => _handleCopyAll(),
                    disabled: !hasItems,
                  ),
                  item(
                    BuoyIcons.trash2,
                    _listTab == 'bulk' ? 'Delete all batches' : 'Delete all runs',
                    _handleDeleteAll,
                    disabled: !hasItems,
                    destructive: true,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _screen() {
    switch (_view.kind) {
      case 'detail':
        final report = _view.report;
        return report == null
            ? const SizedBox.shrink()
            : PerfDetailView(report: report);
      case 'settings':
        return PerfSettingsView(
          onOpenDiagnostics: () => _navigate(const _View('diagnostics')),
          onReset: () => _showDialog(PerfConfirmDialog(
            title: 'Reset settings?',
            message: 'Restore Performance Monitor defaults.',
            onCancel: _closeDialog,
            actions: [
              PerfConfirmAction(
                label: 'Reset',
                destructive: true,
                onPressed: () {
                  _closeDialog();
                  // ignore: discarded_futures
                  PerfSettingsStore.instance.reset();
                },
              ),
            ],
          )),
        );
      case 'diagnostics':
        return const PerfDiagnosticsView();
      case 'automate':
        return const AutomationConfigView();
      case 'batch-report':
        return BatchReportView(
          batchId: _view.batchId,
          onOpenLibrary: () => _navigate(const _View('list')),
        );
      case 'compare':
        return BatchReportView(
          reportIds: _view.reportIds,
          onOpenLibrary: () => _navigate(const _View('list')),
        );
      default:
        return _listView();
    }
  }

  Widget _listView() {
    final items = _activeItems;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        // The inline HUD lives at the top of the runs list so live FPS/CPU/MEM
        // stay visible while browsing. The floating bubble suppresses itself
        // while the modal is open, so this is the only HUD surface.
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
          // Tappable like the floating chip: it shares the persisted HUD mode,
          // so cycling here and cycling on the bubble are the same control.
          child: PerfHudInline(
            onPendingPromptChanged: (prompt) {
              if (mounted) setState(() => _savePrompt = prompt);
            },
          ),
        ),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 8),
            child: Column(
              children: [
                Text(
                  _listTab == 'bulk' ? 'No batches yet' : 'No single runs yet',
                  style: const TextStyle(
                    color: MacOSColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _listTab == 'bulk'
                      ? 'Run an automation batch from the ⚡ menu to compare a matrix of cases side-by-side. Saved batches show up here.'
                      : 'Tap the power button on the HUD to start a recording. Tap it again to stop and name the run. Save a second run exercised differently to see a side-by-side comparison.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: MacOSColors.textSecondary,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          )
        else
          for (final item in items)
            item.isBatch
                ? BatchRunCard(
                    key: ValueKey(item.batchId),
                    item: item,
                    selected: _selected.contains(item.batchId),
                    selectionMode: _selectionMode,
                    onOpen: () =>
                        _navigate(_View('batch-report', batchId: item.batchId)),
                    onDelete: () => _showDialog(PerfConfirmDialog(
                      title: 'Delete batch (${item.caseCount} runs)?',
                      message:
                          'This removes every recording in this batch. It cannot be undone.',
                      onCancel: _closeDialog,
                      actions: [
                        PerfConfirmAction(
                          label: 'Delete',
                          destructive: true,
                          onPressed: () async {
                            _closeDialog();
                            await BenchmarkStorage.deleteBatch(item.batchId);
                            await _refresh();
                          },
                        ),
                      ],
                    )),
                    onToggleSelect: () => _toggleSelect(item.batchId),
                    onEnterSelection: () => _enterSelection(item.batchId),
                  )
                : RunCard(
                    key: ValueKey(item.entry!.id),
                    entry: item.entry!,
                    selected: _selected.contains(item.entry!.id),
                    selectionMode: _selectionMode,
                    // ignore: discarded_futures
                    onOpen: () => _openDetail(item.entry!.id),
                    onToggleSelect: () => _toggleSelect(item.entry!.id),
                    onEnterSelection: () => _enterSelection(item.entry!.id),
                  ),
      ],
    );
  }
}
