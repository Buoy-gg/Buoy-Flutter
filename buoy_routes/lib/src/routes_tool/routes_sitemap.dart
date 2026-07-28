/// Ports packages/route-events/src/components/RoutesSitemap.tsx.
///
/// The visual sitemap of every route the app defines, built from the parsed
/// [RouteInfo] tree ([BuoyRoutesController.sitemap]). Header actions
/// (Home / Copy / Refresh / Search), stats grid, organized+searchable groups,
/// expandable route cards with a type tag, copy, and Go. RN numerics inlined.
///
/// Deviation (logged): no Pro gating; dynamic-route "Go" navigates to the
/// bracket template as-is (Flutter has no Alert.prompt) — concrete-path nav via
/// desktop/MCP works fully.
library;

import 'package:buoy_core/buoy_core.dart' show TouchableOpacity;
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';

import '../route_parser.dart';
import '../routes_controller.dart';

Color _routeTypeColor(RouteType type) {
  switch (type) {
    case RouteType.static:
      return const Color(0xFF3B82F6); // blue
    case RouteType.dynamic:
      return const Color(0xFFF59E0B); // orange
    case RouteType.catchAll:
      return const Color(0xFFEC4899); // pink
    case RouteType.indexRoute:
      return const Color(0xFF10B981); // green
    case RouteType.layout:
      return const Color(0xFF8B5CF6); // purple
    case RouteType.group:
      return const Color(0xFF6366F1); // indigo
    case RouteType.notFound:
      return const Color(0xFFEF4444); // red
  }
}

class RoutesSitemap extends StatefulWidget {
  const RoutesSitemap({super.key});

  @override
  State<RoutesSitemap> createState() => _RoutesSitemapState();
}

class _RoutesSitemapState extends State<RoutesSitemap> {
  String _searchQuery = '';
  bool _isSearching = false;
  bool _isRefreshing = false;
  final _searchController = TextEditingController();
  Set<String> _expandedGroups = {'Root Routes', 'Dynamic Routes'};

  List<RouteInfo> _routes = const [];

  @override
  void initState() {
    super.initState();
    _routes = BuoyRoutesController.instance.sitemap();
    _searchController.addListener(() {
      if (_searchController.text != _searchQuery) {
        setState(() => _searchQuery = _searchController.text);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<RouteInfo> get _sorted => RouteParser.sortRoutes(_routes);

  List<RouteInfo> get _filtered => _searchQuery.isEmpty
      ? _sorted
      : RouteParser.filterRoutes(_sorted, _searchQuery);

  List<RouteGroup> get _displayGroups {
    if (_searchQuery.isNotEmpty && _filtered.isNotEmpty) {
      return [RouteGroup(title: 'Search Results', routes: _filtered)];
    }
    return RouteParser.organizeRoutes(_filtered);
  }

  RouteStats get _stats => RouteParser.getRouteStats(_routes);

  Object _copyData() {
    final stats = _stats;
    return {
      'summary': {
        'total': stats.total,
        'static': stats.static,
        'dynamic': stats.dynamic,
        'layouts': stats.layouts,
        'groups': stats.groups,
        'timestamp': DateTime.now().toIso8601String(),
      },
      'allRoutes': [for (final r in RouteParser.flatten(_routes)) r.path],
    };
  }

  void _refresh() {
    if (_isRefreshing) return;
    setState(() {
      _isRefreshing = true;
      _routes = BuoyRoutesController.instance.sitemap();
    });
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _isRefreshing = false);
    });
  }

  void _navigate(RouteInfo route) {
    if (route.type == RouteType.layout || route.type == RouteType.group) return;
    try {
      BuoyRoutesController.instance.navigate(route.path);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_routes.isEmpty) {
      return const ColoredBox(
        color: BuoyColors.base,
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'No routes found. The sitemap needs a go_router — pass it to '
              'registerBuoyRoutes(router: ...). Use the Events tab to see '
              'navigation.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: BuoyColors.textSecondary,
                fontSize: 14,
                fontFamily: 'monospace',
                height: 20 / 14,
              ),
            ),
          ),
        ),
      );
    }

    return ColoredBox(
      color: BuoyColors.base,
      child: Column(
        children: [
          _isSearching ? _searchHeader() : _actionsHeader(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                if (_displayGroups.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        'No routes found',
                        style: TextStyle(
                          color: BuoyColors.textSecondary,
                          fontSize: 14,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  )
                else
                  for (final group in _displayGroups) _group(group),
                _metaFooter(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionsHeader() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: BuoyColors.border)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _actionButton(BuoyIcons.home, 'Home', () {
                try {
                  BuoyRoutesController.instance.navigate('/');
                } catch (_) {}
              }),
              _actionWrap('Copy', CopyButton(value: _copyData, size: 16)),
              _actionButton(
                BuoyIcons.refreshCw,
                'Refresh',
                _refresh,
                color: _isRefreshing
                    ? BuoyColors.textMuted
                    : BuoyColors.textSecondary,
              ),
              _actionButton(BuoyIcons.search, 'Search', () {
                setState(() => _isSearching = true);
              }),
            ],
          ),
          const SizedBox(height: 12),
          // 6 stats in a 3-column × 2-row grid (matches RN's flexBasis: "30%"
          // wrap). Measure the ACTUAL available width from LayoutBuilder — the
          // sitemap lives inside a narrower-than-screen modal, so sizing off
          // MediaQuery screen width made the cards too wide and wrapped to 2/row.
          LayoutBuilder(
            builder: (context, constraints) {
              // 3 columns with two 8px gaps between them; -1 leaves a hair of
              // slack so rounding never bumps the third card to the next row.
              final itemWidth = (constraints.maxWidth - 8 * 2) / 3 - 1;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _stat(_stats.total, 'Total', itemWidth),
                  _stat(_stats.static, 'Static', itemWidth),
                  _stat(_stats.dynamic, 'Dynamic', itemWidth),
                  _stat(_stats.catchAll, 'Catch-All', itemWidth),
                  _stat(_stats.layouts, 'Layouts', itemWidth),
                  _stat(_stats.groups, 'Groups', itemWidth),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _actionButton(LucideIcon icon, String label, VoidCallback onTap,
      {Color? color}) {
    return Expanded(
      child: Column(
        children: [
          TouchableOpacity(
            activeOpacity: 0.7,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: BuoyGlyph(icon, size: 16, color: color ?? BuoyColors.textSecondary),
            ),
          ),
          const SizedBox(height: 4),
          _actionLabel(label),
        ],
      ),
    );
  }

  Widget _actionWrap(String label, Widget child) {
    return Expanded(
      child: Column(
        children: [child, const SizedBox(height: 4), _actionLabel(label)],
      ),
    );
  }

  Widget _actionLabel(String label) => Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 8,
          color: BuoyColors.textMuted,
          fontFamily: 'monospace',
          letterSpacing: 0.5,
        ),
      );

  Widget _stat(int value, String label, double width) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 90),
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: BuoyColors.card,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(
              '$value',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: BuoyColors.text,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label.toUpperCase(),
              style: const TextStyle(
                fontSize: 10,
                color: BuoyColors.textMuted,
                fontFamily: 'monospace',
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _searchHeader() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: BuoyColors.border)),
      ),
      child: Row(
        children: [
          const BuoyGlyph(BuoyIcons.search, size: 16, color: BuoyColors.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              autofocus: true,
              autocorrect: false,
              style: const TextStyle(
                color: BuoyColors.text,
                fontSize: 14,
                fontFamily: 'monospace',
              ),
              cursorColor: BuoyColors.primary,
              decoration: const InputDecoration(
                isDense: true,
                isCollapsed: true,
                border: InputBorder.none,
                hintText: 'Search routes...',
                hintStyle: TextStyle(color: BuoyColors.textMuted, fontSize: 14),
              ),
            ),
          ),
          TouchableOpacity(
            activeOpacity: 0.7,
            onTap: () {
              setState(() {
                _isSearching = false;
                _searchQuery = '';
                _searchController.clear();
              });
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                'Done',
                style: TextStyle(
                  color: BuoyColors.primary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _group(RouteGroup group) {
    final isExpanded =
        _searchQuery.isNotEmpty || _expandedGroups.contains(group.title);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TouchableOpacity(
            activeOpacity: 0.7,
            onTap: () => setState(() {
              _expandedGroups = {..._expandedGroups};
              if (!_expandedGroups.remove(group.title)) {
                _expandedGroups.add(group.title);
              }
            }),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: BuoyColors.card,
                border: Border(
                  left: BorderSide(color: BuoyColors.textSecondary, width: 3),
                ),
              ),
              child: Row(
                children: [
                  BuoyGlyph(
                    isExpanded ? BuoyIcons.chevronDown : BuoyIcons.chevronRight,
                    size: 14,
                    color: BuoyColors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      group.title.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: BuoyColors.text,
                        fontFamily: 'monospace',
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3B82F6).hexAlpha(0x15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF3B82F6).hexAlpha(0x40),
                      ),
                    ),
                    child: Text(
                      '${group.routes.length}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF3B82F6),
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (group.description != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: const BoxDecoration(
                color: BuoyColors.input,
                border: Border(
                  left: BorderSide(color: BuoyColors.textSecondary, width: 3),
                ),
              ),
              child: Text(
                group.description!,
                style: const TextStyle(
                  fontSize: 11,
                  color: BuoyColors.textSecondary,
                  fontFamily: 'monospace',
                  height: 16 / 11,
                ),
              ),
            ),
          if (isExpanded)
            for (final route in group.routes) _routeItem(route, 0),
        ],
      ),
    );
  }

  Widget _routeItem(RouteInfo route, int depth) {
    final typeColor = _routeTypeColor(route.type);
    final canNavigate =
        route.type != RouteType.layout && route.type != RouteType.group;
    final hasChildren = route.children.isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(left: depth * 12.0, bottom: 6),
      child: Container(
        decoration: BoxDecoration(
          color: BuoyColors.card,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: BuoyColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Row(
                children: [
                  const SizedBox(width: 18),
                  Expanded(
                    child: Text(
                      route.path,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: BuoyColors.text,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: typeColor.hexAlpha(0x15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: typeColor.hexAlpha(0x40)),
                    ),
                    child: Text(
                      route.type.wireName.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: typeColor,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  CopyButton(value: route.path, size: 14),
                  if (canNavigate) ...[
                    const SizedBox(width: 6),
                    TouchableOpacity(
                      activeOpacity: 0.7,
                      onTap: () => _navigate(route),
                      child: Container(
                        height: 24,
                        padding:
                            const EdgeInsets.symmetric(horizontal: 10),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: BuoyColors.primary.hexAlpha(0x15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: BuoyColors.primary.hexAlpha(0x40),
                          ),
                        ),
                        child: const Text(
                          'Go',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: BuoyColors.primary,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (hasChildren)
              Container(
                margin: const EdgeInsets.only(left: 16, right: 8, bottom: 8),
                decoration: const BoxDecoration(
                  border: Border(
                    left: BorderSide(color: BuoyColors.border, width: 2),
                  ),
                ),
                child: Column(
                  children: [
                    for (final child in route.children) _routeItem(child, depth + 1),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _metaFooter() {
    final ts = BuoyRoutesController.instance.sitemapUpdatedAt;
    final label = ts == null
        ? 'Awaiting route data'
        : 'Updated ${_relative(ts)}';
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: BuoyColors.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: BuoyColors.textSecondary,
              fontFamily: 'monospace',
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: BuoyColors.card,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: BuoyColors.border),
            ),
            child: const Text(
              'Source: flutter',
              style: TextStyle(
                fontSize: 11,
                color: BuoyColors.textSecondary,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _relative(int ms) {
    final diff = DateTime.now().millisecondsSinceEpoch - ms;
    if (diff < 60000) return 'just now';
    if (diff < 3600000) return '${diff ~/ 60000}m ago';
    return '${diff ~/ 3600000}h ago';
  }
}
