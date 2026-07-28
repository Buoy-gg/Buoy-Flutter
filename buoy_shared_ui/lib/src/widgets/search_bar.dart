import 'package:flutter/material.dart';

import 'package:buoy_core/buoy_core.dart';

import '../game_ui_colors.dart';

/// Ports packages/shared/src/ui/components/SearchBar.tsx — the search field with
/// clear button, optional filter button, and a suggestions/recent dropdown.
/// gameUI-themed (resolves to the macOS palette via [GameUIColors]).
///
/// RN numerics: bar bg panel, radius 8, padH 12 / padV 8, gap 8, border
/// transparent; focused border `primary40`. Search icon 16 secondary; input
/// font 14. Clear X 14; filter button bg `primary20` radius 4 pad 4.
///
/// Deviation: the RN suggestions box is absolutely positioned over following
/// content; here it renders in normal flow beneath the bar (Flutter overlay
/// positioning is heavier and this component is not yet used by a shipped tool).
class BuoySearchBar extends StatefulWidget {
  const BuoySearchBar({
    super.key,
    required this.value,
    required this.onChange,
    this.onClear,
    this.placeholder = 'Search...',
    this.suggestions = const [],
    this.recentSearches = const [],
    this.showFilters = false,
    this.onFilterPress,
    this.autoFocus = false,
    this.onSubmit,
  });

  final String value;
  final ValueChanged<String> onChange;
  final VoidCallback? onClear;
  final String placeholder;
  final List<String> suggestions;
  final List<String> recentSearches;
  final bool showFilters;
  final VoidCallback? onFilterPress;
  final bool autoFocus;
  final VoidCallback? onSubmit;

  @override
  State<BuoySearchBar> createState() => _BuoySearchBarState();
}

class _BuoySearchBarState extends State<BuoySearchBar> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value);
  final FocusNode _focusNode = FocusNode();
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      setState(() => _isFocused = _focusNode.hasFocus);
    });
  }

  @override
  void didUpdateWidget(BuoySearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleClear() {
    _controller.clear();
    widget.onChange('');
    widget.onClear?.call();
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    final filtered = [
      for (final s in widget.suggestions)
        if (s.toLowerCase().contains(value.toLowerCase())) s,
    ];
    final showSuggestions = _isFocused &&
        (filtered.isNotEmpty ||
            (value.isEmpty && widget.recentSearches.isNotEmpty));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: GameUIColors.panel,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isFocused
                  ? GameUIColors.primary.withValues(alpha: 0x40 / 255)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              const BuoyGlyph(BuoyIcons.search,
                  size: 16, color: GameUIColors.secondary),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  autofocus: widget.autoFocus,
                  autocorrect: false,
                  enableSuggestions: false,
                  onChanged: widget.onChange,
                  onSubmitted: (_) => widget.onSubmit?.call(),
                  style: const TextStyle(
                    fontSize: 14,
                    color: GameUIColors.text,
                  ),
                  cursorColor: GameUIColors.primary,
                  decoration: InputDecoration(
                    isDense: true,
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: widget.placeholder,
                    hintStyle: const TextStyle(
                      fontSize: 14,
                      color: GameUIColors.tertiary,
                    ),
                  ),
                ),
              ),
              if (value.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: TouchableOpacity(
                    activeOpacity: 0.2,
                    onTap: _handleClear,
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: BuoyGlyph(BuoyIcons.x,
                          size: 14, color: GameUIColors.secondary),
                    ),
                  ),
                ),
              if (widget.showFilters)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: TouchableOpacity(
                    activeOpacity: 0.2,
                    onTap: widget.onFilterPress,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: GameUIColors.primary.withValues(alpha: 0x20 / 255),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const BuoyGlyph(BuoyIcons.filter,
                          size: 14, color: GameUIColors.primary),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (showSuggestions) _suggestions(value, filtered),
      ],
    );
  }

  Widget _suggestions(String value, List<String> filtered) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(vertical: 4),
      constraints: const BoxConstraints(maxHeight: 200),
      decoration: BoxDecoration(
        color: GameUIColors.panel,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (value.isEmpty && widget.recentSearches.isNotEmpty) ...[
              _title('Recent'),
              for (final search in widget.recentSearches.take(5))
                _item(BuoyIcons.clock, search),
            ],
            if (filtered.isNotEmpty) ...[
              if (value.isNotEmpty) _title('Suggestions'),
              for (final s in filtered.take(5)) _item(BuoyIcons.search, s),
            ],
          ],
        ),
      ),
    );
  }

  Widget _title(String text) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: GameUIColors.secondary,
          ),
        ),
      );

  Widget _item(LucideIcon icon, String text) => TouchableOpacity(
        activeOpacity: 0.2,
        onTap: () {
          _controller.text = text;
          widget.onChange(text);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              BuoyGlyph(icon, size: 12, color: GameUIColors.tertiary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: GameUIColors.text,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}
