/// Ports packages/images/src/components/ImageDetail.tsx — full record view:
/// preview, source, load timeline, dimensions with the oversize verdict +
/// estimated decoded/wasted memory, cache verdict, error details, a live
/// source-swap field, and global cache actions.
///
/// Deviation: RN's "PROVE SAVINGS" (expo-image-manipulator WebP re-encode) has
/// no Flutter equivalent and is dropped (see the tool doc).
library;

import 'package:buoy_core/buoy_core.dart' show TouchableOpacity;
// hide formatBytes: this file uses the RN-port formatBytes from image_format.
import 'package:buoy_shared_ui/buoy_shared_ui.dart' hide formatBytes;
import 'package:flutter/material.dart';

import '../image_format.dart';
import '../image_record.dart';
import '../images_actions.dart';
import '../images_store.dart';

class ImageDetail extends StatefulWidget {
  const ImageDetail({super.key, required this.record});

  final ImageRecord record;

  @override
  State<ImageDetail> createState() => _ImageDetailState();
}

class _ImageDetailState extends State<ImageDetail> {
  late final TextEditingController _urlController =
      TextEditingController(text: widget.record.uri);

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    final verdict = sizeVerdict(record);
    final cache = cacheBadge(record);
    final needed = neededPixels(record);
    final decoded = estDecodedBytes(record);
    final wasted = estWastedBytes(record);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (record.overrideLabel != null) _overrideBanner(record),
        if (record.uri.isNotEmpty && record.sourceKind != SourceKind.data)
          _preview(record),
        _section('SOURCE', [
          _row('URI', record.uri.isEmpty ? '(none)' : record.uri),
          _row('Kind', record.sourceKind.name),
          _row('Provider', record.lib.name),
          if (record.hasAltText == false)
            _row(
              'Alt text',
              'missing — add a semanticLabel',
              color: MacOSColors.warning,
            ),
        ]),
        const SizedBox(height: 12),
        _section('LOAD', [
          _row(
            'Status',
            record.status.name,
            color: record.status == ImageStatus.error
                ? MacOSColors.error
                : record.status == ImageStatus.loaded
                    ? MacOSColors.success
                    : MacOSColors.warning,
          ),
          _row('Duration', formatMs(record.durationMs)),
          _row('Cache', cache.label, color: cache.color),
          if (record.cacheVerdictSource != null)
            _row('Cache source', 'imageCache lookup after load'),
          if (record.progressSeen) _row('Downloaded', 'network transfer observed'),
          _row('Load cycles', '${record.loadCount}'),
          _row('Still mounted', record.mounted ? 'yes' : 'no'),
        ]),
        const SizedBox(height: 12),
        _section('DIMENSIONS', [
          if (record.intrinsic != null)
            _row('Decoded',
                '${record.intrinsic!.width}×${record.intrinsic!.height} px')
          else
            _row('Decoded', 'unknown'),
          if (record.layout != null)
            _row(
              'Displayed',
              '${record.layout!.width}×${record.layout!.height} dp '
              '(needs ${needed != null ? '${needed.width}×${needed.height}' : '?'} '
              'px @${record.devicePixelRatio}x)',
            )
          else
            _row('Displayed', 'no layout yet'),
          if (verdict.label.isNotEmpty)
            _row('Verdict', verdict.label, color: verdict.color),
          if (decoded > 0) _row('Est. decoded memory', formatBytes(decoded)),
          if (wasted > 0)
            _row(
              'Est. wasted',
              '${formatBytes(wasted)} — resize the source to '
              '${needed != null ? '${needed.width}×${needed.height}' : 'the displayed size'}',
              color: MacOSColors.warning,
            ),
          if (record.layoutShifts > 0)
            _row(
              'Layout shifts',
              '${record.layoutShifts} — box resized after load; reserve '
              'explicit width/height',
              color: MacOSColors.warning,
            ),
        ]),
        if (record.status == ImageStatus.error) ...[
          const SizedBox(height: 12),
          _section('ERROR', [
            _row('Message', record.error ?? 'unknown', color: MacOSColors.error),
            if (record.errorCode != null)
              _row('HTTP status', '${record.errorCode}'),
          ]),
        ],
        if (record.sourceKind == SourceKind.network && record.mounted) ...[
          const SizedBox(height: 12),
          _swapUrlSection(record),
        ],
        const SizedBox(height: 12),
        _section('CACHE ACTIONS (Flutter image cache, global)', [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: _actionButton('Clear memory cache', () {
              PaintingBinding.instance.imageCache.clear();
              PaintingBinding.instance.imageCache.clearLiveImages();
            }),
          ),
        ]),
      ],
    );
  }

  Widget _preview(ImageRecord record) {
    return Container(
      height: 140,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: MacOSColors.backgroundInput,
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: record.sourceKind == SourceKind.network
          ? Image.network(
              record.uri,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const Center(
                child: BuoyGlyph(BuoyIcons.imageOff, color: Colors.white24),
              ),
            )
          : const Center(
              child: BuoyGlyph(BuoyIcons.image, color: Colors.white24),
            ),
    );
  }

  Widget _overrideBanner(ImageRecord record) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: MacOSColors.warningBackground,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Simulation active: ${record.overrideLabel} — stats below describe '
              'the override, not the original source.',
              style: const TextStyle(
                color: MacOSColors.warning,
                fontSize: 11,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(width: 10),
          TouchableOpacity(
            activeOpacity: 0.7,
            onTap: () => ImagesActions.instance.clearOverride(record.id),
            child: const Text(
              'RESTORE',
              style: TextStyle(
                color: MacOSColors.warning,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _swapUrlSection(ImageRecord record) {
    return _section('SWAP SOURCE URL', [
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: TextField(
          controller: _urlController,
          maxLines: null,
          autocorrect: false,
          style: const TextStyle(
            color: MacOSColors.textPrimary,
            fontSize: 11,
            fontFamily: 'monospace',
          ),
          cursorColor: MacOSColors.info,
          decoration: InputDecoration(
            isDense: true,
            hintText: 'https://…',
            hintStyle: const TextStyle(color: MacOSColors.textMuted),
            filled: true,
            fillColor: MacOSColors.backgroundInput,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: MacOSColors.borderDefault),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: MacOSColors.borderDefault),
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            _actionButton('Apply', () {
              final trimmed = _urlController.text.trim();
              if (trimmed.isEmpty || trimmed == record.uri) return;
              ImagesActions.instance.setOverride(
                record.id,
                ImageOverride(
                  source: OverrideSource(OverrideKind.url, uri: trimmed),
                  label: 'URL swapped',
                ),
              );
            }),
            const SizedBox(width: 8),
            _actionButton(
              'Reset field',
              () => setState(() => _urlController.text = record.uri),
            ),
          ],
        ),
      ),
    ]);
  }

  Widget _section(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: MacOSColors.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: MacOSColors.backgroundCard,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: MacOSColors.borderDefault, width: 0.5),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _row(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                color: MacOSColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                color: color ?? MacOSColors.textPrimary,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton(String label, VoidCallback onTap) {
    return TouchableOpacity(
      activeOpacity: 0.7,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: MacOSColors.backgroundHover,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: MacOSColors.borderDefault, width: 0.5),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: MacOSColors.textPrimary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
