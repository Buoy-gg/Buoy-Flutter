/// Ports packages/route-events/src/utils/routeTemplate.ts.
///
/// Infer a route template from a concrete pathname and its segments. Dynamic
/// segments (numeric ids, UUIDs) collapse to `[id]`, so `/products/42` becomes
/// `/products/[id]`. Returns null when the template matches the pathname (i.e.
/// the route is fully static).
library;

final _numericRe = RegExp(r'^\d+$');
final _uuidRe = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);

/// RN `getRouteTemplate` — 1:1.
String? getRouteTemplate(String pathname, List<String> segments) {
  if (segments.isEmpty) return null;

  final templateParts = segments.map((segment) {
    if (_numericRe.hasMatch(segment)) return '[id]';
    if (_uuidRe.hasMatch(segment)) return '[id]';
    return segment;
  });

  final template = '/${templateParts.join('/')}';
  return template != pathname ? template : null;
}
