/// Ports packages/events/src/types/copySettings.ts.
///
/// The Copy-Settings model + presets that drive the event exporter. MCP
/// `get_events` maps its friendly args onto these toggles via the events tool's
/// `exportEvents` action, so the field names + preset values must match RN
/// exactly.
library;

/// Timestamp rendering mode.
enum TimestampFormat { relative, absolute, both }

/// Output format.
enum ExportFormat { markdown, json, plaintext, mermaid }

/// Status filter for export.
enum ExportFilterMode { all, errors, success, pending }

/// Data-size threshold in KB (-1 = unlimited).
class DataSizeThreshold {
  static const int kb1 = 1;
  static const int kb5 = 5;
  static const int kb10 = 10;
  static const int kb50 = 50;
  static const int unlimited = -1;
}

/// Ports `EventsCopySettings`.
class EventsCopySettings {
  const EventsCopySettings({
    required this.timestampFormat,
    required this.includeSource,
    required this.includeStatus,
    required this.includeTitle,
    required this.includeSubtitle,
    required this.includeCorrelation,
    required this.includeDuration,
    required this.includeSummaryHeader,
    required this.includeTotalDuration,
    required this.includeEventData,
    required this.dataSizeThreshold,
    required this.format,
    required this.filterMode,
    required this.filterSources,
    required this.compactMode,
    required this.smartJsonParsing,
    required this.reduxChangedOnly,
    required this.showStorageDiff,
    required this.stripVerboseFields,
  });

  final TimestampFormat timestampFormat;
  final bool includeSource;
  final bool includeStatus;
  final bool includeTitle;
  final bool includeSubtitle;
  final bool includeCorrelation;
  final bool includeDuration;
  final bool includeSummaryHeader;
  final bool includeTotalDuration;
  final bool includeEventData;
  final int dataSizeThreshold;
  final ExportFormat format;
  final ExportFilterMode filterMode;

  /// Granular [EventSourceIds] to include (empty = all).
  final List<String> filterSources;

  final bool compactMode;
  final bool smartJsonParsing;
  final bool reduxChangedOnly;
  final bool showStorageDiff;
  final bool stripVerboseFields;

  EventsCopySettings copyWith({
    TimestampFormat? timestampFormat,
    bool? includeSource,
    bool? includeStatus,
    bool? includeTitle,
    bool? includeSubtitle,
    bool? includeCorrelation,
    bool? includeDuration,
    bool? includeSummaryHeader,
    bool? includeTotalDuration,
    bool? includeEventData,
    int? dataSizeThreshold,
    ExportFormat? format,
    ExportFilterMode? filterMode,
    List<String>? filterSources,
    bool? compactMode,
    bool? smartJsonParsing,
    bool? reduxChangedOnly,
    bool? showStorageDiff,
    bool? stripVerboseFields,
  }) {
    return EventsCopySettings(
      timestampFormat: timestampFormat ?? this.timestampFormat,
      includeSource: includeSource ?? this.includeSource,
      includeStatus: includeStatus ?? this.includeStatus,
      includeTitle: includeTitle ?? this.includeTitle,
      includeSubtitle: includeSubtitle ?? this.includeSubtitle,
      includeCorrelation: includeCorrelation ?? this.includeCorrelation,
      includeDuration: includeDuration ?? this.includeDuration,
      includeSummaryHeader: includeSummaryHeader ?? this.includeSummaryHeader,
      includeTotalDuration: includeTotalDuration ?? this.includeTotalDuration,
      includeEventData: includeEventData ?? this.includeEventData,
      dataSizeThreshold: dataSizeThreshold ?? this.dataSizeThreshold,
      format: format ?? this.format,
      filterMode: filterMode ?? this.filterMode,
      filterSources: filterSources ?? this.filterSources,
      compactMode: compactMode ?? this.compactMode,
      smartJsonParsing: smartJsonParsing ?? this.smartJsonParsing,
      reduxChangedOnly: reduxChangedOnly ?? this.reduxChangedOnly,
      showStorageDiff: showStorageDiff ?? this.showStorageDiff,
      stripVerboseFields: stripVerboseFields ?? this.stripVerboseFields,
    );
  }

  /// Apply an MCP `settings` map (the shape `get_events` sends). Recognizes
  /// `filterSources`, `filterMode`, `includeEventData`, `format`.
  EventsCopySettings applyOverrides(Map<String, Object?> overrides) {
    var next = this;
    final sources = overrides['filterSources'];
    if (sources is List) {
      next = next.copyWith(filterSources: sources.whereType<String>().toList());
    }
    final mode = overrides['filterMode'];
    if (mode is String) {
      next = next.copyWith(filterMode: _parseFilterMode(mode));
    }
    final includeData = overrides['includeEventData'];
    if (includeData is bool) next = next.copyWith(includeEventData: includeData);
    final format = overrides['format'];
    if (format is String) next = next.copyWith(format: _parseFormat(format));
    return next;
  }
}

ExportFilterMode _parseFilterMode(String v) {
  switch (v) {
    case 'errors':
      return ExportFilterMode.errors;
    case 'success':
      return ExportFilterMode.success;
    case 'pending':
      return ExportFilterMode.pending;
    default:
      return ExportFilterMode.all;
  }
}

ExportFormat _parseFormat(String v) {
  switch (v) {
    case 'json':
      return ExportFormat.json;
    case 'plaintext':
    case 'text':
      return ExportFormat.plaintext;
    case 'mermaid':
      return ExportFormat.mermaid;
    default:
      return ExportFormat.markdown;
  }
}

/// Ports `DEFAULT_COPY_SETTINGS`.
const EventsCopySettings kDefaultCopySettings = EventsCopySettings(
  timestampFormat: TimestampFormat.relative,
  includeSource: true,
  includeStatus: true,
  includeTitle: true,
  includeSubtitle: true,
  includeCorrelation: true,
  includeDuration: true,
  includeSummaryHeader: true,
  includeTotalDuration: true,
  includeEventData: false,
  dataSizeThreshold: DataSizeThreshold.kb5,
  format: ExportFormat.markdown,
  filterMode: ExportFilterMode.all,
  filterSources: [],
  compactMode: false,
  smartJsonParsing: true,
  reduxChangedOnly: true,
  showStorageDiff: true,
  stripVerboseFields: true,
);

/// Ports `COPY_PRESETS`. Keyed by RN preset name (llm/bugReport/json/errors/
/// minimal/mermaid) — the names MCP `get_events` accepts.
const Map<String, EventsCopySettings> kCopyPresets = {
  'llm': EventsCopySettings(
    timestampFormat: TimestampFormat.relative,
    includeSource: true,
    includeStatus: true,
    includeTitle: true,
    includeSubtitle: true,
    includeCorrelation: true,
    includeDuration: true,
    includeSummaryHeader: true,
    includeTotalDuration: true,
    includeEventData: false,
    dataSizeThreshold: DataSizeThreshold.kb5,
    format: ExportFormat.markdown,
    filterMode: ExportFilterMode.all,
    filterSources: [],
    compactMode: false,
    smartJsonParsing: true,
    reduxChangedOnly: true,
    showStorageDiff: true,
    stripVerboseFields: true,
  ),
  'bugReport': EventsCopySettings(
    timestampFormat: TimestampFormat.both,
    includeSource: true,
    includeStatus: true,
    includeTitle: true,
    includeSubtitle: true,
    includeCorrelation: true,
    includeDuration: true,
    includeSummaryHeader: true,
    includeTotalDuration: true,
    includeEventData: true,
    dataSizeThreshold: DataSizeThreshold.kb10,
    format: ExportFormat.markdown,
    filterMode: ExportFilterMode.all,
    filterSources: [],
    compactMode: false,
    smartJsonParsing: true,
    reduxChangedOnly: true,
    showStorageDiff: true,
    stripVerboseFields: true,
  ),
  'json': EventsCopySettings(
    timestampFormat: TimestampFormat.absolute,
    includeSource: true,
    includeStatus: true,
    includeTitle: true,
    includeSubtitle: true,
    includeCorrelation: true,
    includeDuration: true,
    includeSummaryHeader: false,
    includeTotalDuration: false,
    includeEventData: true,
    dataSizeThreshold: DataSizeThreshold.unlimited,
    format: ExportFormat.json,
    filterMode: ExportFilterMode.all,
    filterSources: [],
    compactMode: false,
    smartJsonParsing: true,
    reduxChangedOnly: false,
    showStorageDiff: false,
    stripVerboseFields: false,
  ),
  'errors': EventsCopySettings(
    timestampFormat: TimestampFormat.relative,
    includeSource: true,
    includeStatus: true,
    includeTitle: true,
    includeSubtitle: true,
    includeCorrelation: true,
    includeDuration: true,
    includeSummaryHeader: true,
    includeTotalDuration: false,
    includeEventData: true,
    dataSizeThreshold: DataSizeThreshold.kb10,
    format: ExportFormat.markdown,
    filterMode: ExportFilterMode.errors,
    filterSources: [],
    compactMode: false,
    smartJsonParsing: true,
    reduxChangedOnly: true,
    showStorageDiff: true,
    stripVerboseFields: true,
  ),
  'minimal': EventsCopySettings(
    timestampFormat: TimestampFormat.relative,
    includeSource: false,
    includeStatus: true,
    includeTitle: true,
    includeSubtitle: false,
    includeCorrelation: false,
    includeDuration: false,
    includeSummaryHeader: false,
    includeTotalDuration: false,
    includeEventData: false,
    dataSizeThreshold: DataSizeThreshold.kb1,
    format: ExportFormat.plaintext,
    filterMode: ExportFilterMode.all,
    filterSources: [],
    compactMode: true,
    smartJsonParsing: true,
    reduxChangedOnly: true,
    showStorageDiff: false,
    stripVerboseFields: true,
  ),
  'mermaid': EventsCopySettings(
    timestampFormat: TimestampFormat.relative,
    includeSource: true,
    includeStatus: true,
    includeTitle: true,
    includeSubtitle: false,
    includeCorrelation: true,
    includeDuration: true,
    includeSummaryHeader: false,
    includeTotalDuration: false,
    includeEventData: false,
    dataSizeThreshold: DataSizeThreshold.kb1,
    format: ExportFormat.mermaid,
    filterMode: ExportFilterMode.all,
    filterSources: [],
    compactMode: false,
    smartJsonParsing: true,
    reduxChangedOnly: true,
    showStorageDiff: true,
    stripVerboseFields: true,
  ),
};
