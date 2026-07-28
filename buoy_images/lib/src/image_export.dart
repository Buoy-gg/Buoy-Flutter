/// Ports packages/images/src/export.ts — copy-friendly markdown reports for a
/// single record (detail copy) and the whole registry (list copy).
library;

import 'image_format.dart';
import 'image_record.dart';
import 'images_store.dart';

String formatRecordMarkdown(ImageRecord record) {
  final verdict = sizeVerdict(record);
  final cache = cacheBadge(record);
  final needed = neededPixels(record);
  final decoded = estDecodedBytes(record);
  final wasted = estWastedBytes(record);

  final lines = <String>[];
  lines.add('## Image report — ${uriTail(record.uri)}');
  lines.add('');
  lines.add('- URI: ${record.uri.isEmpty ? '(none)' : record.uri}');
  lines.add(
    '- Provider: ${record.lib.name} · kind: ${record.sourceKind.name} · '
    'mounted: ${record.mounted ? 'yes' : 'no'}',
  );
  lines.add(
    '- Status: ${record.status.name}'
    '${record.errorCode != null ? ' (HTTP ${record.errorCode})' : ''} · '
    'load cycles: ${record.loadCount}',
  );
  lines.add('- Cache: ${cache.label}');
  lines.add('- Load time: ${formatMs(record.durationMs)}');
  final intrinsic = record.intrinsic;
  if (intrinsic != null) {
    lines.add(
      '- Decoded: ${intrinsic.width}×${intrinsic.height}px ≈ '
      '${formatBytes(decoded)} decoded memory',
    );
  }
  final layout = record.layout;
  if (layout != null) {
    lines.add(
      '- Displayed: ${layout.width}×${layout.height}dp '
      '@${record.devicePixelRatio}x '
      '(needs ${needed != null ? '${needed.width}×${needed.height}px' : '?'})',
    );
  }
  if (verdict.label.isNotEmpty) {
    lines.add(
      '- Size verdict: ${verdict.label}'
      '${wasted > 0 && needed != null ? ' — wasting ≈${formatBytes(wasted)}; serve ${needed.width}×${needed.height}' : ''}',
    );
  }
  if (record.hasAltText == false) {
    lines.add('- Accessibility: MISSING semanticLabel');
  }
  if (record.layoutShifts > 0) {
    lines.add(
      '- Layout shifts after load: ${record.layoutShifts} '
      '(reserve explicit dimensions)',
    );
  }
  if (record.error != null) {
    lines.add('- Error: ${record.error}');
  }
  if (record.overrideLabel != null) {
    lines.add('- Simulation active: ${record.overrideLabel}');
  }
  return lines.join('\n');
}

String formatRegistryMarkdown(
  List<ImageRecord> records,
  ImageStats stats,
  ImageInsights insights,
  ({String network, bool blank}) modes,
) {
  final lines = <String>[];
  lines.add('## Buoy Images registry (${stats.total} records)');
  lines.add('');
  lines.add(
    '${stats.loaded} loaded · ${stats.errors} failed · ${stats.loading} in flight · '
    '≈${formatBytes(stats.estDecodedBytes)} decoded'
    '${stats.estWastedBytes > 0 ? ' · ${formatBytes(stats.estWastedBytes)} wasted on oversized sources' : ''}',
  );
  final chips = insightChips(insights);
  if (chips.isNotEmpty) lines.add('Insights: ${chips.join(' · ')}');
  if (modes.network != 'normal' || modes.blank) {
    lines.add(
      'Simulation active: network=${modes.network}${modes.blank ? ', blank images' : ''}',
    );
  }
  lines.add('');
  lines.add('| image | provider | status | cache | ms | decoded px | shown dp | verdict | notes |');
  lines.add('|---|---|---|---|---|---|---|---|---|');
  for (final r in records) {
    final verdict = sizeVerdict(r);
    final cache = cacheBadge(r);
    final dims = r.intrinsic != null
        ? '${r.intrinsic!.width}×${r.intrinsic!.height}'
        : '–';
    final layout = r.layout != null
        ? '${r.layout!.width}×${r.layout!.height}'
        : '–';
    final notes = [
      if (r.error != null) 'error: ${r.error}',
      if (r.overrideLabel != null) 'sim: ${r.overrideLabel}',
      if (r.hasAltText == false) 'no alt',
      if (r.layoutShifts > 0) '${r.layoutShifts} layout shifts',
      if (!r.mounted) 'unmounted',
    ].join('; ');
    lines.add(
      '| ${uriTail(r.uri)} | ${r.lib.name} | ${r.status.name} | ${cache.label} | '
      '${r.durationMs != null ? r.durationMs!.round() : '–'} | $dims | $layout | '
      '${verdict.label.isEmpty ? '–' : verdict.label} | ${notes.isEmpty ? '–' : notes} |',
    );
  }
  return lines.join('\n');
}
