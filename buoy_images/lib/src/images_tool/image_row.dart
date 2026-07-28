/// Ports packages/images/src/components/ImageRow.tsx — one captured image in
/// the list: thumbnail + status dot, filename, provider + cache badges, load
/// time, decoded dims, and the size verdict.
///
/// The thumbnail is a plain `Image.network` (NOT a [BuoyImage]) so the tool
/// never captures its own preview into the registry.
library;

import 'package:buoy_core/buoy_core.dart' show TouchableOpacity;
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';

import '../image_format.dart';
import '../image_record.dart';

class ImageRow extends StatelessWidget {
  const ImageRow({super.key, required this.record, required this.onPress});

  final ImageRecord record;
  final void Function(int id) onPress;

  @override
  Widget build(BuildContext context) {
    final verdict = sizeVerdict(record);
    final cache = cacheBadge(record);
    final showThumb =
        record.sourceKind == SourceKind.network && record.uri.isNotEmpty;

    return TouchableOpacity(
      activeOpacity: 0.7,
      onTap: () => onPress(record.id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: MacOSColors.borderDefault, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            _thumb(showThumb),
            const SizedBox(width: 10),
            Expanded(child: _main(cache)),
            const SizedBox(width: 10),
            _right(verdict),
          ],
        ),
      ),
    );
  }

  Widget _thumb(bool showThumb) {
    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: MacOSColors.backgroundInput,
              borderRadius: BorderRadius.circular(6),
            ),
            clipBehavior: Clip.antiAlias,
            alignment: Alignment.center,
            child: showThumb
                ? Image.network(
                    record.uri,
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _fallback(),
                  )
                : _fallback(),
          ),
          Positioned(
            right: 2,
            bottom: 2,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: statusColor(record),
                shape: BoxShape.circle,
                border: Border.all(color: MacOSColors.backgroundBase),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fallback() => const Text(
    '?',
    style: TextStyle(
      color: MacOSColors.textMuted,
      fontSize: 16,
      fontWeight: FontWeight.w700,
    ),
  );

  Widget _main(CacheBadge cache) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          uriTail(record.uri),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: MacOSColors.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            _badge(record.lib.name.toUpperCase(), MacOSColors.textMuted),
            const SizedBox(width: 8),
            _badge(cache.label, cache.color),
            if (record.overrideLabel != null) ...[
              const SizedBox(width: 8),
              _badge('SIM', MacOSColors.warning),
            ],
            const SizedBox(width: 8),
            _meta(formatMs(record.durationMs)),
            if (record.intrinsic != null) ...[
              const SizedBox(width: 8),
              _meta('${record.intrinsic!.width}×${record.intrinsic!.height}'),
            ],
          ],
        ),
      ],
    );
  }

  Widget _badge(String text, Color color) => Text(
    text,
    style: TextStyle(
      fontSize: 9,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.5,
      color: color,
    ),
  );

  Widget _meta(String text) => Text(
    text,
    style: const TextStyle(
      color: MacOSColors.textSecondary,
      fontSize: 10,
      fontFeatures: [FontFeature.tabularFigures()],
    ),
  );

  Widget _right(SizeVerdict verdict) {
    if (record.status == ImageStatus.error) {
      return const Text(
        'FAILED',
        style: TextStyle(
          color: MacOSColors.error,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      );
    }
    if (verdict.label.isEmpty) return const SizedBox.shrink();
    return Text(
      verdict.label,
      style: TextStyle(
        color: verdict.color,
        fontSize: 10,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}
