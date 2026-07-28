/// Ports packages/route-events/src/components/NavigationStack.tsx.
///
/// Visualizes the current navigation stack (mounted screens, focused route)
/// newest-first, with Back / Go / Pop-To actions per expanded card. Reads the
/// live [NavigationStackStore] and drives navigation through
/// [BuoyRoutesController]. Reports its serialized copy payload up so the copy
/// button can live in the shared modal navbar (RN onCopyValueChange).
///
/// Deviation (logged): no Pro gating and no destructive confirmation dialog —
/// the action runs directly (briefing precedent: PRO UI display-only).
library;

import 'dart:convert';

import 'package:buoy_core/buoy_core.dart' show TouchableOpacity;
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';

import '../routes_capture.dart';
import '../routes_controller.dart';

class NavigationStackView extends StatefulWidget {
  const NavigationStackView({super.key, required this.onCopyValueChange});

  final ValueChanged<String> onCopyValueChange;

  @override
  State<NavigationStackView> createState() => _NavigationStackViewState();
}

class _NavigationStackViewState extends State<NavigationStackView> {
  int? _expandedIndex;
  void Function()? _unsubscribe;
  List<StackDisplayItem> _stack = const [];

  @override
  void initState() {
    super.initState();
    _stack = NavigationStackStore.instance.getStack();
    // Defer the initial copy-value report: it calls the parent's
    // onCopyValueChange (which setStates RoutesModal), and initState runs while
    // RoutesModal is still building — a synchronous call throws "setState during
    // build". Post-frame is safe.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reportCopy();
    });
    _unsubscribe = NavigationStackStore.instance.subscribe(() {
      if (!mounted) return;
      setState(() => _stack = NavigationStackStore.instance.getStack());
      _reportCopy();
    });
  }

  @override
  void dispose() {
    _unsubscribe?.call();
    super.dispose();
  }

  void _reportCopy() {
    final data = [
      for (final item in _stack)
        {
          'pathname': item.pathname,
          'name': item.name,
          'params': item.params,
          'isFocused': item.isFocused,
        },
    ];
    widget.onCopyValueChange(const JsonEncoder.withIndent('  ').convert(data));
  }

  int get _depth => _stack.length;
  bool get _isAtRoot => _depth <= 1;

  @override
  Widget build(BuildContext context) {
    if (_stack.isEmpty) {
      return const ColoredBox(
        color: BuoyColors.base,
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'No navigation stack',
                  style: TextStyle(
                    color: BuoyColors.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Navigate to a route to see the stack',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: BuoyColors.textSecondary,
                    fontSize: 14,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Render top-of-stack first (RN [...stack].reverse()).
    final reversed = [
      for (var i = _stack.length - 1; i >= 0; i--) i,
    ];

    return ColoredBox(
      color: BuoyColors.base,
      child: ListView(
        padding: const EdgeInsets.all(8),
        children: [
          for (final actualIndex in reversed) _card(_stack[actualIndex], actualIndex),
        ],
      ),
    );
  }

  Widget _card(StackDisplayItem item, int actualIndex) {
    final isExpanded = _expandedIndex == actualIndex;
    final hasParams = item.params.isNotEmpty;
    final focusColor = item.isFocused ? BuoyColors.success : BuoyColors.info;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        decoration: BoxDecoration(
          color: BuoyColors.card,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isExpanded ? BuoyColors.primary : BuoyColors.border,
            width: isExpanded ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TouchableOpacity(
              activeOpacity: 0.7,
              onTap: () => setState(
                () => _expandedIndex = isExpanded ? null : actualIndex,
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 20,
                      child: BuoyGlyph(
                        isExpanded ? BuoyIcons.chevronDown : BuoyIcons.chevronRight,
                        size: 14,
                        color: BuoyColors.textSecondary,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        item.pathname,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: BuoyColors.text,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    CopyButton(value: item.pathname, size: 14),
                    const SizedBox(width: 8),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: focusColor.hexAlpha(0x15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: focusColor.hexAlpha(0x40)),
                      ),
                      child: Text(
                        item.isFocused ? 'FOCUSED' : 'MOUNTED',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: focusColor,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (isExpanded) _expanded(item, actualIndex, hasParams),
          ],
        ),
      ),
    );
  }

  Widget _expanded(StackDisplayItem item, int actualIndex, bool hasParams) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: BuoyColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _detail('Route Name:', item.name),
          const SizedBox(height: 8),
          _detail('Position:', '$actualIndex / ${_depth - 1}'),
          if (hasParams) ...[
            const SizedBox(height: 8),
            DataViewer(data: item.params, showTypeFilter: false),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              _action(
                label: 'Back',
                help: 'Go back one screen',
                disabled: _isAtRoot,
                onTap: () => BuoyRoutesController.instance.goBack(),
              ),
              const SizedBox(width: 6),
              _action(
                label: 'Go',
                help: 'Navigate to this route',
                disabled: item.isFocused,
                onTap: () =>
                    BuoyRoutesController.instance.navigateToIndex(item.index),
              ),
              const SizedBox(width: 6),
              _action(
                label: 'Pop To',
                help: 'Remove screens above this',
                disabled: item.isFocused || actualIndex == _depth - 1,
                onTap: () =>
                    BuoyRoutesController.instance.popToIndex(item.index),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _detail(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: BuoyColors.textSecondary,
            fontFamily: 'monospace',
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            color: BuoyColors.text,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }

  Widget _action({
    required String label,
    required String help,
    required bool disabled,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Column(
        children: [
          TouchableOpacity(
            activeOpacity: disabled ? 1 : 0.7,
            onTap: disabled ? null : onTap,
            child: Opacity(
              opacity: disabled ? 0.5 : 1,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                decoration: BoxDecoration(
                  color: BuoyColors.input,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: disabled ? BuoyColors.textMuted : BuoyColors.text,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            help,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 9,
              color: BuoyColors.textSecondary,
              fontFamily: 'monospace',
              height: 12 / 9,
            ),
          ),
        ],
      ),
    );
  }
}
