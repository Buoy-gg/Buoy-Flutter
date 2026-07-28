import 'package:flutter/material.dart';

import 'package:buoy_core/buoy_core.dart';
import '../macos_colors.dart';
import 'filter_components.dart';
import 'section_header.dart';

/// Port of shared-ui's DynamicFilterView in the shapes the network tool
/// uses: facet-card grids (status/method/content-type or preset/include/
/// format), the EXCLUDE FILTERS card w/ add-pattern input + extra content,
/// AVAILABLE ITEMS suggestions, HOW IT WORKS, and a PREVIEW card.

class FilterOption {
  const FilterOption({
    required this.id,
    required this.label,
    this.count,
    this.icon,
    this.color,
    this.isActive = false,
    this.isMethodBadge = false,
    this.value,
  });

  final String id;
  final String label;
  final int? count;
  final LucideIcon? icon;
  final Color? color;
  final bool isActive;

  /// Method sections render a colored text badge instead of an icon.
  final bool isMethodBadge;
  final Object? value;
}

class FilterSectionConfig {
  const FilterSectionConfig({
    required this.id,
    required this.title,
    required this.options,
  });

  final String id;
  final String title;
  final List<FilterOption> options;
}

class DynamicFilterView extends StatefulWidget {
  const DynamicFilterView({
    super.key,
    this.sections = const [],
    this.onFilterChange,
    // Exclude-filters card
    this.addFilterEnabled = false,
    this.addFilterTitle = 'EXCLUDE FILTERS',
    this.addFilterPlaceholder = 'Enter pattern to exclude...',
    this.addFilterExtra,
    this.activePatterns = const [],
    this.onPatternAdd,
    this.onPatternRemove,
    this.patternMetaBuilder,
    // Available items card
    this.availableItemsEnabled = false,
    this.availableItemsTitle = 'AVAILABLE ITEMS',
    this.availableItemsEmptyMessage = 'No items available',
    this.availableItems = const [],
    // How-it-works card
    this.howItWorksEnabled = false,
    this.howItWorksTitle = 'HOW FILTERS WORK',
    this.howItWorksDescription = '',
    this.howItWorksExamples = const [],
    // Preview card
    this.previewEnabled = false,
    this.previewTitle = 'PREVIEW',
    this.previewBuilder,
    this.previewHeaderActions,
  });

  final List<FilterSectionConfig> sections;
  final void Function(String optionId, Object? value)? onFilterChange;

  final bool addFilterEnabled;
  final String addFilterTitle;
  final String addFilterPlaceholder;

  /// Rendered above the pattern input when open (the CONTAINS/EXACT toggle).
  final WidgetBuilder? addFilterExtra;
  final List<String> activePatterns;
  final ValueChanged<String>? onPatternAdd;
  final ValueChanged<String>? onPatternRemove;
  final Widget Function(String pattern)? patternMetaBuilder;

  final bool availableItemsEnabled;
  final String availableItemsTitle;
  final String availableItemsEmptyMessage;
  final List<String> availableItems;

  final bool howItWorksEnabled;
  final String howItWorksTitle;
  final String howItWorksDescription;
  final List<String> howItWorksExamples;

  final bool previewEnabled;
  final String previewTitle;
  final WidgetBuilder? previewBuilder;
  final List<Widget> Function(BuildContext)? previewHeaderActions;

  @override
  State<DynamicFilterView> createState() => _DynamicFilterViewState();
}

class _DynamicFilterViewState extends State<DynamicFilterView> {
  bool _showAddInput = false;

  @override
  Widget build(BuildContext context) {
    final suggested = [
      for (final item in widget.availableItems)
        if (!widget.activePatterns.any((p) => item.contains(p))) item,
    ];

    return ColoredBox(
      color: BuoyColors.base,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          for (final section in widget.sections) _facetSection(section),
          if (widget.addFilterEnabled) _excludeFiltersCard(),
          if (widget.availableItemsEnabled) _availableItemsCard(suggested),
          if (widget.howItWorksEnabled) _howItWorksCard(),
          if (widget.previewEnabled) _previewCard(),
        ],
      ),
    );
  }

  // ── Facet grid section ────────────────────────────────────────────────

  Widget _facetSection(FilterSectionConfig section) {
    if (section.options.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: section.title),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in section.options) _facetCard(option),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _facetCard(FilterOption option) {
    final active = option.isActive;
    return TouchableOpacity(
      activeOpacity: 0.2,
      onTap: () => widget.onFilterChange?.call(option.id, option.value),
      child: Container(
        width: 72,
        constraints: const BoxConstraints(minHeight: 68),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: active
              ? BuoyColors.primary.hexAlpha(0x33)
              : BuoyColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active ? BuoyColors.primary : BuoyColors.border,
            width: active ? 2 : 1,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: BuoyColors.primary.withValues(alpha: 0.3),
                    blurRadius: 8,
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (option.icon != null)
              BuoyGlyph(option.icon, size: 24, color: option.color)
            else if (option.isMethodBadge)
              Container(
                constraints: const BoxConstraints(minWidth: 48, maxWidth: 60),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: (option.color ?? BuoyColors.textMuted).hexAlpha(0x20),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  option.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                    fontFamily: 'monospace',
                    color: option.color,
                  ),
                ),
              ),
            if (option.count != null)
              Padding(
                padding: const EdgeInsets.only(top: 3, bottom: 1),
                child: Text(
                  '${option.count}',
                  style: option.count == 0
                      ? const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          fontFamily: 'monospace',
                          color: BuoyColors.textMuted,
                        )
                      : const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'monospace',
                          color: BuoyColors.text,
                        ),
                ),
              ),
            // RN hides the label for icon-less method cards (badge repeats it).
            if (!option.isMethodBadge || option.icon != null)
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _capitalize(option.label),
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: BuoyColors.text,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  // ── Cards ─────────────────────────────────────────────────────────────

  // Background fill (color + radius) — no border. When a rounded card CLIPS its
  // children (Clip.antiAlias), Flutter clips to the OUTER edge of the shape, so
  // a child with a solid background (SectionHeader's base fill) paints over the
  // border at the corners and the rounded border reads as "cut off". Drawing the
  // border as a foregroundDecoration instead paints it OVER the child, so the
  // corners stay intact — the RN parity is `overflow: hidden` + a real border.
  BoxDecoration _cardFill(Color color) => BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(16),
  );

  BoxDecoration _cardBorder(Color color) => BoxDecoration(
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: color),
  );

  Widget _excludeFiltersCard() {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      decoration: _cardFill(BuoyColors.card),
      foregroundDecoration: _cardBorder(BuoyColors.border),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            icon: BuoyIcons.filter,
            title: widget.addFilterTitle,
            badgeCount:
                widget.activePatterns.isNotEmpty ? widget.activePatterns.length : null,
          ),
          const Padding(
            padding: EdgeInsets.only(left: 16, right: 16, top: 8),
            child: Text(
              'Hide queries matching these patterns from the list.',
              style: TextStyle(
                fontSize: 10,
                height: 1.4,
                color: BuoyColors.textSecondary,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: !_showAddInput
                ? AddFilterButton(
                    onPress: () => setState(() => _showAddInput = true),
                    label: 'Add exclude pattern',
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.addFilterExtra != null)
                        widget.addFilterExtra!(context),
                      AddFilterInput(
                        placeholder: widget.addFilterPlaceholder,
                        onSubmit: (pattern) {
                          widget.onPatternAdd?.call(pattern);
                          setState(() => _showAddInput = false);
                        },
                        onCancel: () => setState(() => _showAddInput = false),
                      ),
                    ],
                  ),
          ),
          if (widget.activePatterns.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 150),
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
              child: SingleChildScrollView(
                child: FilterList(
                  filters: widget.activePatterns,
                  onRemoveFilter: (p) => widget.onPatternRemove?.call(p),
                  itemMetaBuilder: widget.patternMetaBuilder,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _availableItemsCard(List<String> suggested) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      decoration: _cardFill(BuoyColors.card),
      foregroundDecoration: _cardBorder(BuoyColors.border),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            icon: BuoyIcons.plus,
            title: widget.availableItemsTitle,
            badgeCount: suggested.length,
          ),
          Container(
            constraints: const BoxConstraints(maxHeight: 150),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: suggested.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: Text(
                        widget.availableItemsEmptyMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                          color: BuoyColors.textMuted,
                        ),
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    child: Column(
                      children: [
                        for (final item in suggested)
                          Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: TouchableOpacity(
                              activeOpacity: 0.2,
                              onTap: () => widget.onPatternAdd?.call(item),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: BuoyColors.hover,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: BuoyColors.border),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        item,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontFamily: 'monospace',
                                          color: BuoyColors.text,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const BuoyGlyph(
                                      BuoyIcons.plus,
                                      size: 12,
                                      color: BuoyColors.primary,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _howItWorksCard() {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      decoration: _cardFill(BuoyColors.card),
      foregroundDecoration: _cardBorder(BuoyColors.border),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            icon: BuoyIcons.filter,
            iconColor: BuoyColors.textSecondary,
            title: widget.howItWorksTitle,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Text(
              widget.howItWorksDescription,
              style: const TextStyle(
                fontSize: 11,
                height: 16 / 11,
                fontFamily: 'monospace',
                color: BuoyColors.textSecondary,
              ),
            ),
          ),
          if (widget.howItWorksExamples.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: BuoyColors.border)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(bottom: 6),
                    child: Text(
                      'EXAMPLES:',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                        fontFamily: 'monospace',
                        color: BuoyColors.textMuted,
                      ),
                    ),
                  ),
                  for (final example in widget.howItWorksExamples)
                    Text(
                      example,
                      style: const TextStyle(
                        fontSize: 10,
                        height: 1.6,
                        fontFamily: 'monospace',
                        color: BuoyColors.textMuted,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _previewCard() {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      decoration: _cardFill(BuoyColors.hover),
      foregroundDecoration: _cardBorder(BuoyColors.borderStrong),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            icon: BuoyIcons.eye,
            title: widget.previewTitle,
            actions: widget.previewHeaderActions?.call(context),
          ),
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: BoxDecoration(
              color: BuoyColors.base,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: BuoyColors.border),
            ),
            child: widget.previewBuilder?.call(context),
          ),
        ],
      ),
    );
  }
}
