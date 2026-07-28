/// Ports packages/images/src/components/ImagesModal.tsx (+ ImagesHeader.tsx) —
/// the Images tool's root surface. Opens in JsModal with the RN persistence key
/// (`@react_buoy_images_modal`); shows the captured-image list (insights bar +
/// rows + mass-action footer) and a per-record detail view with a stepper
/// footer. Header carries the stats subtitle, a copy-report button, and clear.
///
/// Every screen owns its scrolling, so JsModal's scroll wrapper is disabled.
library;

import 'package:buoy_core/buoy_core.dart';
// hide formatBytes: this file uses the RN-port formatBytes from image_format.
import 'package:buoy_shared_ui/buoy_shared_ui.dart' hide formatBytes;
import 'package:flutter/material.dart';

import '../image_export.dart';
import '../image_format.dart';
import '../image_record.dart';
import '../images_actions.dart';
import '../images_store.dart';
import 'image_detail.dart';
import 'image_detail_footer.dart';
import 'image_row.dart';
import 'images_list_footer.dart';
import 'insights_bar.dart';

class ImagesModal extends StatefulWidget {
  const ImagesModal({
    super.key,
    required this.storage,
    required this.onClose,
    this.onMinimize,
  });

  final BuoyStorage storage;
  final VoidCallback onClose;
  final VoidCallback? onMinimize;

  @override
  State<ImagesModal> createState() => _ImagesModalState();
}

class _ImagesModalState extends State<ImagesModal> {
  int? _selectedId;
  void Function()? _unsubStore;
  void Function()? _unsubActions;

  @override
  void initState() {
    super.initState();
    _unsubStore = ImagesStore.instance.subscribe(_onChange);
    _unsubActions = ImagesActions.instance.subscribeActions(_onChange);
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _unsubStore?.call();
    _unsubActions?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Newest-first, mirroring the RN adapter/UI.
    final records = ImagesStore.instance.records.reversed.toList();
    final stats = computeStats(ImagesStore.instance.getSnapshot());
    final selected =
        _selectedId != null ? ImagesStore.instance.getRecord(_selectedId!) : null;
    final selectedIndex =
        selected != null ? records.indexWhere((r) => r.id == selected.id) : -1;

    return JsModal(
      storage: widget.storage,
      onClose: widget.onClose,
      onMinimize: widget.onMinimize,
      persistenceKey: devToolsStorageKeys.images.modal(),
      wrapChildInScrollView: false,
      headerContent: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: _header(records, stats, selected, selectedIndex),
      ),
      child: SizedBox.expand(
        child: ColoredBox(
          color: MacOSColors.backgroundBase,
          child: selected != null
              ? _detail(selected, records, selectedIndex)
              : _list(records, stats),
        ),
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────

  Widget _header(
    List<ImageRecord> records,
    ImageStats stats,
    ImageRecord? selected,
    int selectedIndex,
  ) {
    if (selected != null) {
      final counter = selectedIndex >= 0 && records.isNotEmpty
          ? '${selectedIndex + 1} of ${records.length}'
          : null;
      return ModalHeader(
        children: [
          ModalHeaderBack(onBack: () => setState(() => _selectedId = null)),
          ModalHeaderContent(child: _titleWithSub('Image detail', counter)),
          ModalHeaderActions(
            children: [
              CopyButton(
                value: () => formatRecordMarkdown(selected),
                size: 14,
                decoration: headerActionButtonDecoration(),
                width: 32,
                height: 32,
              ),
            ],
          ),
        ],
      );
    }

    final wasted = stats.estWastedBytes > 0
        ? ' · ${formatBytes(stats.estWastedBytes)} wasted'
        : '';
    final subtitle =
        '${stats.total} images · ${stats.errors} failed · '
        '≈${formatBytes(stats.estDecodedBytes)} decoded$wasted';

    return ModalHeader(
      children: [
        ModalHeaderContent(child: _titleWithSub('Images', subtitle)),
        ModalHeaderActions(
          children: [
            CopyButton(
              value: () => formatRegistryMarkdown(
                records,
                stats,
                computeInsights(ImagesStore.instance.getSnapshot()),
                ImagesActions.instance.globalModes,
              ),
              size: 14,
              enabled: records.isNotEmpty,
              decoration: headerActionButtonDecoration(),
              width: 32,
              height: 32,
            ),
            HeaderActionButton(
              icon: BuoyIcons.trash2,
              color: records.isNotEmpty
                  ? MacOSColors.textMuted
                  : MacOSColors.textDisabled,
              disabled: records.isEmpty,
              onTap: ImagesStore.instance.clearRecords,
            ),
          ],
        ),
      ],
    );
  }

  Widget _titleWithSub(String title, String? subtitle) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: BuoyColors.text,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (subtitle != null && subtitle.isNotEmpty)
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: MacOSColors.textMuted,
              fontSize: 10,
            ),
          ),
      ],
    );
  }

  // ── List ────────────────────────────────────────────────────────────────

  Widget _list(List<ImageRecord> records, ImageStats stats) {
    return Column(
      children: [
        InsightsBar(insights: computeInsights(ImagesStore.instance.getSnapshot())),
        Expanded(
          child: records.isEmpty
              ? _empty()
              : ListView.builder(
                  itemCount: records.length,
                  itemBuilder: (context, index) => ImageRow(
                    record: records[index],
                    onPress: (id) => setState(() => _selectedId = id),
                  ),
                ),
        ),
        const ImagesListFooter(),
      ],
    );
  }

  Widget _empty() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'No images captured yet',
              style: TextStyle(
                color: MacOSColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Every BuoyImage load is recorded here with cache verdicts, '
              'timings, and oversize checks.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: MacOSColors.textSecondary,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Detail ────────────────────────────────────────────────────────────────

  Widget _detail(
    ImageRecord selected,
    List<ImageRecord> records,
    int selectedIndex,
  ) {
    return Column(
      children: [
        Expanded(child: ImageDetail(key: ValueKey(selected.id), record: selected)),
        ImageDetailFooter(
          key: ValueKey('footer-${selected.id}'),
          record: selected,
          // Newest-first list: "previous" = newer.
          hasPrevious: selectedIndex > 0,
          hasNext: selectedIndex >= 0 && selectedIndex < records.length - 1,
          onPrevious: () {
            final target = records[selectedIndex - 1];
            setState(() => _selectedId = target.id);
          },
          onNext: () {
            final target = records[selectedIndex + 1];
            setState(() => _selectedId = target.id);
          },
        ),
      ],
    );
  }
}
