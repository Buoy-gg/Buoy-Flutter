/// Ports packages/jotai/src/jotai/components/JotaiEventFilterView.tsx — the
/// ignore-pattern editor. Tap a registered provider to toggle it as a filter,
/// or type a substring pattern. Patterns hide matching providers from both the
/// Providers and Events tabs.
library;

import 'package:flutter/material.dart';

import 'package:buoy_core/buoy_core.dart';
import 'package:buoy_shared_ui/buoy_shared_ui.dart';

import '../riverpod_types.dart';

class ProviderFilterView extends StatefulWidget {
  const ProviderFilterView({
    super.key,
    required this.ignoredPatterns,
    required this.onTogglePattern,
    required this.onAddPattern,
    required this.providers,
  });

  final Set<String> ignoredPatterns;
  final void Function(String) onTogglePattern;
  final void Function(String) onAddPattern;
  final List<ProviderInfo> providers;

  @override
  State<ProviderFilterView> createState() => _ProviderFilterViewState();
}

class _ProviderFilterViewState extends State<ProviderFilterView> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    final trimmed = _controller.text.trim();
    if (trimmed.isNotEmpty && !widget.ignoredPatterns.contains(trimmed)) {
      widget.onAddPattern(trimmed);
      _controller.clear();
    }
  }

  bool _isFiltered(String label) => widget.ignoredPatterns
      .any((p) => label.toLowerCase().contains(p.toLowerCase()));

  Color? _colorForPattern(String pattern) {
    for (final p in widget.providers) {
      if (p.label.toLowerCase().contains(pattern.toLowerCase())) {
        return Color(p.color);
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: BuoyColors.base,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _section(
            title: 'REGISTERED PROVIDERS',
            children: [
              if (widget.providers.isEmpty)
                const Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Text('No providers registered yet.',
                      style: TextStyle(
                          fontSize: 11,
                          color: MacOSColors.textMuted,
                          fontFamily: 'monospace')),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    children: [
                      for (final provider in widget.providers)
                        _providerRow(provider),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: _patternInput(),
              ),
            ],
          ),
          if (widget.ignoredPatterns.isNotEmpty) ...[
            const SizedBox(height: 16),
            _section(
              title: 'ACTIVE FILTERS',
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    children: [
                      for (final pattern in widget.ignoredPatterns)
                        _activeFilterRow(pattern),
                    ],
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          _section(
            title: 'HOW PROVIDER FILTERS WORK',
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  'Patterns hide matching providers from both the Providers tab '
                  'and the Events tab. Tap a provider above to quickly add it '
                  'as a filter.',
                  style: TextStyle(
                      fontSize: 11,
                      color: BuoyColors.textSecondary,
                      height: 16 / 11,
                      fontFamily: 'monospace'),
                ),
              ),
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: BuoyColors.border)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Padding(
                      padding: EdgeInsets.only(bottom: 6),
                      child: Text('EXAMPLES:',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: BuoyColors.textMuted,
                              fontFamily: 'monospace',
                              letterSpacing: 0.5)),
                    ),
                    _Example('• count -> hides countProvider from both tabs'),
                    _Example('• auth -> hides authProvider, authStatusProvider'),
                    _Example('• pokemon -> hides pokemonCard, pokemonDetail'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _section({required String title, required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: BuoyColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BuoyColors.border),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            icon: BuoyIcons.filter,
            iconColor: BuoyColors.textSecondary,
            title: title,
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _providerRow(ProviderInfo provider) {
    final color = Color(provider.color);
    final filtered = _isFiltered(provider.label);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TouchableOpacity(
        activeOpacity: 0.7,
        onTap: () => widget.onTogglePattern(provider.label),
        child: Opacity(
          opacity: filtered ? 0.45 : 1,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: BuoyColors.hover,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: BuoyColors.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(provider.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                          decoration: filtered
                              ? TextDecoration.lineThrough
                              : null,
                          color:
                              filtered ? MacOSColors.textMuted : color)),
                ),
                Text(filtered ? 'filtered' : '+ add',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                        color:
                            filtered ? MacOSColors.textDisabled : color)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _activeFilterRow(String pattern) {
    final color = _colorForPattern(pattern);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TouchableOpacity(
        activeOpacity: 0.8,
        onTap: () => widget.onTogglePattern(pattern),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: BuoyColors.hover,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: BuoyColors.border),
          ),
          child: Row(
            children: [
              if (color != null) ...[
                Container(
                  width: 7,
                  height: 7,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(pattern,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: color ?? BuoyColors.text)),
              ),
              BuoyGlyph(BuoyIcons.x,
                  size: 12, color: BuoyColors.primary.hexAlpha(0x80)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _patternInput() {
    return TextField(
      controller: _controller,
      focusNode: _focus,
      autocorrect: false,
      onSubmitted: (_) => _submit(),
      style: const TextStyle(
          fontSize: 12, color: BuoyColors.text, fontFamily: 'monospace'),
      cursorColor: BuoyColors.primary,
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Type a pattern and press Enter...',
        hintStyle: const TextStyle(
            fontSize: 12,
            color: MacOSColors.textMuted,
            fontFamily: 'monospace'),
        filled: true,
        fillColor: BuoyColors.input,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:
              BorderSide(color: BuoyColors.primary.hexAlpha(0x40)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:
              BorderSide(color: BuoyColors.primary.hexAlpha(0x80)),
        ),
      ),
    );
  }
}

class _Example extends StatelessWidget {
  const _Example(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          fontSize: 10,
          color: BuoyColors.textMuted,
          fontFamily: 'monospace',
          height: 16 / 10));
}
