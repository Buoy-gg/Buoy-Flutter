/// Ports packages/perf-monitor/src/perf-monitor/utils/computeCaseLabels.ts.
///
/// Disambiguates case columns that share a name: which params are constant
/// across the whole batch (rendered once in the report header) and which
/// differ (used to build a tight per-case column label). If every case already
/// has a unique name, names are left alone.
library;

class CaseLabelInput {
  const CaseLabelInput({required this.name, this.params, this.route});
  final String name;
  final Map<String, String>? params;

  /// Treated as a synthetic param-like dimension so cases differing only by
  /// route still get disambiguated.
  final String? route;
}

class CaseLabelResult {
  const CaseLabelResult({required this.constantParams, required this.labels});

  /// Params whose value is identical across every case.
  final Map<String, String> constantParams;

  /// Per-case display label. Same length and order as the input.
  final List<String> labels;
}

/// Reserved key threading `route` through the params machinery. Prefixed with
/// `__` so it sorts before normal keys; stripped before returning constants.
const String _routeKey = '__route';

bool _namesAreUnique(List<CaseLabelInput> cases) {
  final seen = <String>{};
  for (final c in cases) {
    if (!seen.add(c.name)) return false;
  }
  return true;
}

List<String> _collectKeys(List<CaseLabelInput> cases) {
  final keys = <String>{};
  var anyRoute = false;
  for (final c in cases) {
    if (c.route != null && c.route!.isNotEmpty) anyRoute = true;
    final params = c.params;
    if (params == null) continue;
    keys.addAll(params.keys);
  }
  final sorted = keys.toList()..sort();
  return anyRoute ? [_routeKey, ...sorted] : sorted;
}

String _valueFor(CaseLabelInput c, String key) {
  if (key == _routeKey) return c.route ?? '';
  return c.params?[key] ?? '';
}

String _displayKey(String key) => key == _routeKey ? 'route' : key;

CaseLabelResult computeCaseLabels(List<CaseLabelInput> cases) {
  if (cases.isEmpty) {
    return const CaseLabelResult(constantParams: {}, labels: []);
  }

  // Short-circuit: names are already unique → nothing to compute.
  if (_namesAreUnique(cases)) {
    return CaseLabelResult(
      constantParams: const {},
      labels: [for (final c in cases) c.name],
    );
  }

  final keys = _collectKeys(cases);
  final constantParams = <String, String>{};
  final differingKeys = <String>[];

  for (final key in keys) {
    final first = _valueFor(cases.first, key);
    final same = cases.every((c) => _valueFor(c, key) == first);
    if (same) {
      // Skip empties — no point displaying `mode=` when every case omits it.
      if (first.isNotEmpty) constantParams[_displayKey(key)] = first;
    } else {
      differingKeys.add(key);
    }
  }

  final labels = <String>[];
  for (var i = 0; i < cases.length; i++) {
    final c = cases[i];
    final parts = [
      for (final k in differingKeys) '${_displayKey(k)}=${_valueFor(c, k)}',
    ];
    // No differing params and the names collide — two literally identical
    // cases; tag with index so the reader can still tell them apart.
    labels.add(parts.isNotEmpty ? parts.join(', ') : '${c.name} #${i + 1}');
  }

  return CaseLabelResult(constantParams: constantParams, labels: labels);
}

/// Render a param map as a compact "k=v, k=v" string (RN `formatParams`).
String formatParams(Map<String, String> params) {
  if (params.isEmpty) return '';
  final entries = params.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  return [for (final e in entries) '${e.key}=${e.value}'].join(', ');
}
