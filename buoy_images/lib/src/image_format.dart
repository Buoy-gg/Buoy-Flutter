/// Ports packages/images/src/format.ts — formatting + verdict helpers shared
/// by list rows, the detail view, and the copy report.
library;

import 'dart:ui' show Color;

import 'package:buoy_shared_ui/buoy_shared_ui.dart';

import 'image_record.dart';
import 'images_store.dart';

String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String formatMs(double? ms) {
  if (ms == null) return '—';
  if (ms < 1000) return '${ms.round()}ms';
  return '${(ms / 1000).toStringAsFixed(2)}s';
}

/// Last path segment of a URI, for compact row display (RN uriTail).
String uriTail(String uri) {
  if (uri.isEmpty) return '(no source)';
  final withoutQuery = uri.split('?').first;
  final segments = withoutQuery.split('/').where((s) => s.isNotEmpty).toList();
  return segments.isNotEmpty ? segments.last : uri;
}

class SizeVerdict {
  const SizeVerdict({required this.label, required this.color, this.factor});
  final String label;
  final Color color;
  final double? factor;
}

/// Fresco-style fit verdict: green within 10%, yellow within 50%, red beyond;
/// undersized (upscaled) sources get their own callout (RN sizeVerdict).
SizeVerdict sizeVerdict(ImageRecord record) {
  final factor = oversizeFactor(record);
  if (factor == null) {
    return const SizeVerdict(label: '', color: MacOSColors.textMuted);
  }
  if (factor < 0.9) {
    return SizeVerdict(
      label: '${factor.toStringAsFixed(1)}× upscaled',
      color: MacOSColors.info,
      factor: factor,
    );
  }
  if (factor <= 1.1) {
    return SizeVerdict(
      label: 'right-sized',
      color: MacOSColors.success,
      factor: factor,
    );
  }
  if (factor <= 1.5) {
    return SizeVerdict(
      label: '${factor.toStringAsFixed(1)}× oversized',
      color: MacOSColors.warning,
      factor: factor,
    );
  }
  return SizeVerdict(
    label: '${factor.toStringAsFixed(1)}× oversized',
    color: MacOSColors.error,
    factor: factor,
  );
}

Color statusColor(ImageRecord record) {
  switch (record.status) {
    case ImageStatus.loaded:
      return MacOSColors.success;
    case ImageStatus.error:
      return MacOSColors.error;
    case ImageStatus.loading:
      return MacOSColors.warning;
    case ImageStatus.pending:
      return MacOSColors.textMuted;
  }
}

class CacheBadge {
  const CacheBadge({required this.label, required this.color});
  final String label;
  final Color color;
}

/// Cache verdict badge (memory=green, disk=yellow, network=red) — RN cacheBadge.
CacheBadge cacheBadge(ImageRecord record) {
  final verdict = record.cacheVerdict;
  if (verdict == CacheVerdict.memory) {
    return const CacheBadge(label: 'MEMORY', color: MacOSColors.success);
  }
  if (verdict == CacheVerdict.disk) {
    return const CacheBadge(label: 'DISK', color: MacOSColors.warning);
  }
  if (verdict == CacheVerdict.none || record.progressSeen) {
    return const CacheBadge(label: 'NETWORK', color: MacOSColors.error);
  }
  return const CacheBadge(label: '?', color: MacOSColors.textMuted);
}
