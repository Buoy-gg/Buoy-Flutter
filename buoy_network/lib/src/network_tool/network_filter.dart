import 'package:flutter/foundation.dart';

import '../network_capture.dart';
import 'ignored_patterns.dart';

/// Ports of the network package's pure filter logic
/// (types/index.ts NetworkFilter + filterNetworkEvents.ts +
/// formatGraphQLVariables.ts) operating on [NetworkCaptureEvent].

enum NetworkStatusFilter { success, error, pending }

@immutable
class NetworkFilter {
  const NetworkFilter({
    this.methods,
    this.status,
    this.contentTypes,
    this.searchText,
    this.host,
  });

  final List<String>? methods;
  final NetworkStatusFilter? status;
  final List<String>? contentTypes;
  final String? searchText;
  final String? host;

  bool get hasActiveFacets =>
      status != null ||
      (methods?.isNotEmpty ?? false) ||
      (contentTypes?.isNotEmpty ?? false);

  NetworkFilter copyWith({
    Object? methods = _sentinel,
    Object? status = _sentinel,
    Object? contentTypes = _sentinel,
    Object? searchText = _sentinel,
    Object? host = _sentinel,
  }) {
    return NetworkFilter(
      methods: methods == _sentinel ? this.methods : methods as List<String>?,
      status: status == _sentinel ? this.status : status as NetworkStatusFilter?,
      contentTypes: contentTypes == _sentinel
          ? this.contentTypes
          : contentTypes as List<String>?,
      searchText:
          searchText == _sentinel ? this.searchText : searchText as String?,
      host: host == _sentinel ? this.host : host as String?,
    );
  }

  static const _sentinel = Object();
}

/// Content-type bucket label for an event ("JSON", "XML", …, "OTHER") —
/// mirrors getContentTypeBadge/getContentType in the RN components.
String contentTypeLabel(NetworkCaptureEvent event) {
  final headers = event.responseHeaders.isNotEmpty
      ? event.responseHeaders
      : event.requestHeaders;
  final contentType = (headers['content-type'] ?? headers['Content-Type'] ?? '')
      .toLowerCase();
  if (contentType.contains('json')) return 'JSON';
  if (contentType.contains('xml')) return 'XML';
  if (contentType.contains('html')) return 'HTML';
  if (contentType.contains('text')) return 'TEXT';
  if (contentType.contains('image')) return 'IMAGE';
  if (contentType.contains('video')) return 'VIDEO';
  if (contentType.contains('audio')) return 'AUDIO';
  if (contentType.contains('form')) return 'FORM';
  return 'OTHER';
}

bool isSuccessEvent(NetworkCaptureEvent e) {
  final status = e.status;
  return status != null && status >= 200 && status < 300;
}

bool isErrorEvent(NetworkCaptureEvent e) =>
    e.error != null || (e.status != null && e.status! >= 400);

bool isPendingEvent(NetworkCaptureEvent e) =>
    e.status == null && e.error == null;

/// filterNetworkEvents — search/method/status/host/content-type.
List<NetworkCaptureEvent> filterNetworkEvents(
  List<NetworkCaptureEvent> events,
  NetworkFilter filter,
) {
  final searchLower = (filter.searchText?.isNotEmpty ?? false)
      ? filter.searchText!.toLowerCase()
      : null;
  final methodSet = (filter.methods?.isNotEmpty ?? false)
      ? filter.methods!.toSet()
      : null;
  final contentTypeSet = (filter.contentTypes?.isNotEmpty ?? false)
      ? filter.contentTypes!.toSet()
      : null;

  var filtered = events;

  if (methodSet != null) {
    filtered = [
      for (final e in filtered)
        if (methodSet.contains(e.method)) e,
    ];
  }

  if (filter.status != null) {
    filtered = [
      for (final e in filtered)
        if (switch (filter.status!) {
          NetworkStatusFilter.success => isSuccessEvent(e),
          NetworkStatusFilter.error => isErrorEvent(e),
          NetworkStatusFilter.pending => isPendingEvent(e),
        })
          e,
    ];
  }

  if (searchLower != null) {
    filtered = [
      for (final e in filtered)
        if (_matchesSearch(e, searchLower)) e,
    ];
  }

  if (filter.host != null) {
    filtered = [
      for (final e in filtered)
        if (Uri.tryParse(e.url)?.host == filter.host) e,
    ];
  }

  if (contentTypeSet != null) {
    filtered = [
      for (final e in filtered)
        if (contentTypeSet.contains(contentTypeLabel(e))) e,
    ];
  }

  return filtered;
}

bool _matchesSearch(NetworkCaptureEvent e, String searchLower) {
  final uri = Uri.tryParse(e.url);
  return e.url.toLowerCase().contains(searchLower) ||
      e.method.toLowerCase().contains(searchLower) ||
      (uri != null && uri.path.toLowerCase().contains(searchLower)) ||
      (uri != null && uri.host.toLowerCase().contains(searchLower)) ||
      (e.error?.toLowerCase().contains(searchLower) ?? false) ||
      (e.operationName?.toLowerCase().contains(searchLower) ?? false) ||
      searchGraphQLVariables(e.graphqlVariables, searchLower);
}

/// applyIgnoredPatterns — drop events matching any shared exclude pattern.
List<NetworkCaptureEvent> applyIgnoredPatterns(
  List<NetworkCaptureEvent> events,
  List<IgnoredPattern> patterns,
) {
  if (patterns.isEmpty) return events;
  return [
    for (final e in events)
      if (!patterns.any((p) => urlMatchesIgnoredPattern(e.url, p))) e,
  ];
}

// ── GraphQL display helpers (formatGraphQLVariables.ts) ─────────────────

String? _formatValue(Object? value, [int maxLength = 30]) {
  if (value == null) return null;
  if (value is bool || value is num) return '$value';
  if (value is String) {
    if (value.length > maxLength) {
      return '${value.substring(0, maxLength - 1)}…';
    }
    return value;
  }
  if (value is List) {
    if (value.isEmpty) return null;
    if (value.length == 1) return _formatValue(value.first, maxLength);
    return '${value.length} items';
  }
  if (value is Map) {
    for (final v in value.values) {
      final formatted = _formatValue(v, maxLength);
      if (formatted != null) return formatted;
    }
    return null;
  }
  return null;
}

List<String>? formatGraphQLVariables(
  Map<String, Object?>? variables, [
  int maxValues = 3,
]) {
  if (variables == null) return null;
  final values = <String>[];
  for (final value in variables.values) {
    final formatted = _formatValue(value);
    if (formatted != null) values.add(formatted);
    if (values.length >= maxValues) break;
  }
  return values.isEmpty ? null : values;
}

/// "GetPokemon › Sandshrew" — matches the React Query key display pattern.
String formatGraphQLDisplay(
  String operationName,
  Map<String, Object?>? variables,
) {
  final values = formatGraphQLVariables(variables);
  if (values == null || values.isEmpty) return operationName;
  return [operationName, ...values].join(' › ');
}

bool searchGraphQLVariables(
  Map<String, Object?>? variables,
  String searchText,
) {
  if (variables == null) return false;
  return variables.values.any((v) => _searchValue(v, searchText));
}

bool _searchValue(Object? value, String searchText) {
  if (value is String) return value.toLowerCase().contains(searchText);
  if (value is num || value is bool) return '$value'.contains(searchText);
  if (value is List) return value.any((v) => _searchValue(v, searchText));
  if (value is Map) {
    return value.values.any((v) => _searchValue(v, searchText));
  }
  return false;
}
