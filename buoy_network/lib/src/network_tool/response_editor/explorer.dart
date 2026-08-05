/// Ports packages/network/src/network/components/response-editor/Explorer.tsx
/// — the response-body tree, where preview and editor are ONE surface.
///
/// A 1:1 port of the React Query tool's `Explorer`, deliberately: that is the
/// interaction that already works. There is no read mode and no edit mode, and
/// no button that swaps one for the other. A string renders AS its input, a
/// boolean AS its toggle, and typing into what you are reading is the edit.
///
/// The only thing that differs from the RN original is where an edit LANDS:
/// there it is `queryClient.setQueryData(...)`, here it is [ResponseEditorScope]'s
/// `onChange`, which turns the rebuilt body into an override rule.
///
/// Layout numbers are RN's, inline where they matter.
library;

import 'package:buoy_core/buoy_core.dart';
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'nested_data.dart';

/// RN chunks long lists into pages of 100 with `[0...99]` expanders.
const int _chunkSize = 100;

/// RN caps how many entries it will even enumerate, for big payloads.
const int _maxEntries = 1000;

/// The RN `ResponseEditorContext`: the whole document plus one way to replace
/// it. Every edit rebuilds the root and hands it up.
class ResponseEditorScope extends InheritedWidget {
  const ResponseEditorScope({
    super.key,
    required this.root,
    required this.onChange,
    required super.child,
  });

  final Object? root;
  final ValueChanged<Object?> onChange;

  static ResponseEditorScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ResponseEditorScope>();

  @override
  bool updateShouldNotify(ResponseEditorScope oldWidget) =>
      !identical(oldWidget.root, root) || oldWidget.onChange != onChange;
}

/// One node of the tree. Recursive, exactly as RN is.
class BuoyExplorer extends StatefulWidget {
  const BuoyExplorer({
    super.key,
    required this.label,
    required this.value,
    this.dataPath = const [],
    this.editable = false,
    this.itemsDeletable = false,
    this.defaultExpanded = const [],
  });

  final String label;
  final Object? value;
  final List<String> dataPath;
  final bool editable;

  /// This node sits inside a container, so it can be removed from it.
  final bool itemsDeletable;

  /// Labels that start expanded (RN's `defaultExpanded`).
  final List<String> defaultExpanded;

  @override
  State<BuoyExplorer> createState() => _BuoyExplorerState();
}

class _BuoyExplorerState extends State<BuoyExplorer> {
  late bool _expanded;
  final Set<int> _expandedPages = {};
  final FocusNode _focus = FocusNode();
  TextEditingController? _controller;
  bool _isRowFocused = false;

  @override
  void initState() {
    super.initState();
    _expanded = widget.defaultExpanded.contains(widget.label);
    _focus.addListener(() {
      if (mounted) setState(() => _isRowFocused = _focus.hasFocus);
    });
    _syncController();
  }

  @override
  void didUpdateWidget(BuoyExplorer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // ⚠️ Only sync from an EXTERNAL change, never from our own typing.
    //
    // RN carries the same warning on its `useEffect`: syncing on every render
    // races the edit. You type "5101", the root rebuilds, the effect re-runs
    // while `value` is still the old 5100, and it writes 5100 back over what
    // you just typed. Comparing against the controller's current text is the
    // Flutter equivalent of RN's "do not put localInputValue in the deps".
    if (oldWidget.value != widget.value || oldWidget.label != widget.label) {
      _syncController();
    }
  }

  void _syncController() {
    final value = widget.value;
    if (value is String || value is num) {
      final text = value.toString();
      final controller = _controller ??= TextEditingController(text: text);
      if (controller.text != text) {
        controller.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
      }
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller?.dispose();
    super.dispose();
  }

  // ── Value shape ────────────────────────────────────────────────────────────

  String get _valueType {
    final value = widget.value;
    if (value is List) return 'array';
    if (value is Map) return 'object';
    if (value is String) return 'string';
    if (value is num) return 'number';
    if (value is bool) return 'boolean';
    return 'null';
  }

  List<({String label, Object? value})> get _subEntries {
    final value = widget.value;
    if (value is List) {
      final limited = value.length > _maxEntries
          ? value.sublist(0, _maxEntries)
          : value;
      return [
        for (var i = 0; i < limited.length; i++)
          (label: i.toString(), value: limited[i]),
      ];
    }
    if (value is Map) {
      final entries = value.entries.take(_maxEntries);
      return [
        for (final entry in entries)
          (label: entry.key.toString(), value: entry.value),
      ];
    }
    return const [];
  }

  // ── Edits ──────────────────────────────────────────────────────────────────

  ResponseEditorScope? get _editor => ResponseEditorScope.maybeOf(context);

  void _commit(Object? nextRoot) => _editor?.onChange(nextRoot);

  void _handleTextChange(String text) {
    final editor = _editor;
    if (editor == null) return;
    if (_valueType == 'number') {
      final parsed = num.tryParse(text);
      // A half-typed number ("-", "1.") isn't an error — RN drops the edit and
      // leaves the field alone until it parses.
      if (parsed == null) return;
      _commit(updateNestedDataByPath(editor.root, widget.dataPath, parsed));
      return;
    }
    _commit(updateNestedDataByPath(editor.root, widget.dataPath, text));
  }

  void _step(int delta) {
    final current = num.tryParse(_controller?.text ?? '') ?? 0;
    final next = (current + delta).toString();
    _controller?.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    _handleTextChange(next);
  }

  void _delete() {
    final editor = _editor;
    if (editor == null) return;
    _commit(deleteNestedDataByPath(editor.root, widget.dataPath));
  }

  void _toggleBool() {
    final editor = _editor;
    if (editor == null) return;
    final current = widget.value is bool ? widget.value! as bool : false;
    _commit(updateNestedDataByPath(editor.root, widget.dataPath, !current));
  }

  void _clearArray() {
    final editor = _editor;
    if (editor == null) return;
    _commit(updateNestedDataByPath(editor.root, widget.dataPath, <Object?>[]));
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final entries = _subEntries;
    // RN branches on `subEntryPages.length`: a container renders the expander
    // row, everything else renders a leaf.
    return entries.isEmpty ? _leaf() : _container(entries);
  }

  Widget _container(List<({String label, Object? value})> entries) {
    final pages = <List<({String label, Object? value})>>[
      for (var i = 0; i < entries.length; i += _chunkSize)
        entries.sublist(
          i,
          i + _chunkSize > entries.length ? entries.length : i + _chunkSize,
        ),
    ];
    final editable = widget.editable && _editor != null;

    return Padding(
      // RN minWidthWrapper: marginVertical 0.5.
      padding: const EdgeInsets.symmetric(vertical: 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            // RN flexRowItemsCenterGap: padV 3 / padH 6 / marginV 1 / r4 /
            // card@66 with a 0.5 border at textSecondary@1A.
            margin: const EdgeInsets.symmetric(vertical: 1),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: BuoyColors.card.hexAlpha(0x66),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: BuoyColors.textSecondary.hexAlpha(0x1A),
                width: 0.5,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TouchableOpacity(
                    activeOpacity: 0.6,
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: Row(
                      children: [
                        _Expander(expanded: _expanded),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            widget.label,
                            overflow: TextOverflow.ellipsis,
                            // RN labelText: 10 / w600 / mono / tracking 0.4.
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'monospace',
                              letterSpacing: 0.4,
                              color: BuoyColors.textSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${entries.length} '
                          '${entries.length > 1 ? 'items' : 'item'}',
                          // RN textGray500: 10 / w400 / mono / opacity 0.7.
                          style: TextStyle(
                            fontSize: 10,
                            fontFamily: 'monospace',
                            color: BuoyColors.textMuted.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (editable) ...[
                  if (widget.itemsDeletable)
                    _IconAction(
                      icon: BuoyIcons.trash2,
                      color: BuoyColors.error,
                      label: 'Delete item',
                      onTap: _delete,
                    ),
                  if (_valueType == 'array')
                    _TextAction(
                      text: '[]',
                      color: BuoyColors.warning,
                      label: 'Remove all items',
                      onTap: _clearArray,
                    ),
                ],
              ],
            ),
          ),
          if (_expanded)
            if (pages.length == 1)
              _indented([
                for (var i = 0; i < pages.first.length; i++)
                  BuoyExplorer(
                    key: ValueKey('${pages.first[i].label}-$i'),
                    label: pages.first[i].label,
                    value: pages.first[i].value,
                    editable: widget.editable,
                    defaultExpanded: widget.defaultExpanded,
                    dataPath: [...widget.dataPath, pages.first[i].label],
                    // Anything inside a container can be removed from it.
                    itemsDeletable: true,
                  ),
              ])
            else
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var page = 0; page < pages.length; page++)
                      _page(page, pages[page]),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _page(int index, List<({String label, Object? value})> entries) {
    final open = _expandedPages.contains(index);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TouchableOpacity(
          activeOpacity: 0.6,
          onTap: () => setState(() {
            open ? _expandedPages.remove(index) : _expandedPages.add(index);
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                _Expander(expanded: open),
                const SizedBox(width: 6),
                Text(
                  '[${index * _chunkSize}...'
                  '${index * _chunkSize + _chunkSize - 1}]',
                  style: const TextStyle(
                    fontSize: 10,
                    fontFamily: 'monospace',
                    color: BuoyColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (open)
          _indented([
            for (final entry in entries)
              BuoyExplorer(
                key: ValueKey(entry.label),
                label: entry.label,
                value: entry.value,
                editable: widget.editable,
                defaultExpanded: widget.defaultExpanded,
                dataPath: [...widget.dataPath, entry.label],
                itemsDeletable: true,
              ),
          ]),
      ],
    );
  }

  /// RN singleEntryContainer: the 1.5px left guide line that makes nesting
  /// readable without indenting everything off the screen.
  Widget _indented(List<Widget> children) => Container(
    margin: const EdgeInsets.only(left: 2, top: 2),
    padding: const EdgeInsets.only(left: 8),
    decoration: BoxDecoration(
      border: Border(
        left: BorderSide(
          color: BuoyColors.textSecondary.hexAlpha(0x40),
          width: 1.5,
        ),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );

  // ── Leaves ─────────────────────────────────────────────────────────────────

  Widget _leaf() {
    final editable = widget.editable && _editor != null;
    final type = _valueType;

    if (editable && (type == 'string' || type == 'number')) {
      return _inputLeaf(isNumber: type == 'number');
    }
    if (editable && type == 'boolean') return _booleanLeaf();
    return _readOnlyLeaf();
  }

  /// A string or number: the value IS the input. No edit affordance, because
  /// there is nothing to switch into.
  Widget _inputLeaf({required bool isNumber}) {
    return Padding(
      // RN CyberpunkInput container: marginVertical 3.
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _leafLabel(),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 34),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _isRowFocused
                      ? BuoyColors.primary
                      : BuoyColors.textMuted.hexAlpha(0x66),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focus,
                      autocorrect: false,
                      enableSuggestions: false,
                      keyboardType: isNumber
                          ? const TextInputType.numberWithOptions(
                              signed: true,
                              decimal: true,
                            )
                          : TextInputType.text,
                      inputFormatters: isNumber
                          ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]'))]
                          : null,
                      onChanged: _handleTextChange,
                      // RN input: padH 10 / padV 6 / mono 12 / text.
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        fontWeight: isNumber
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: BuoyColors.text,
                      ),
                      cursorColor: BuoyColors.primary,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                      ),
                    ),
                  ),
                  if (isNumber) ...[
                    _StepButton(
                      icon: BuoyIcons.chevronUp,
                      focused: _isRowFocused,
                      onTap: () => _step(1),
                    ),
                    const SizedBox(width: 2),
                    _StepButton(
                      icon: BuoyIcons.chevronDown,
                      focused: _isRowFocused,
                      onTap: () => _step(-1),
                    ),
                    const SizedBox(width: 4),
                  ],
                  if (widget.itemsDeletable) ...[
                    _IconAction(
                      icon: BuoyIcons.trash2,
                      color: BuoyColors.error,
                      label: 'Delete item',
                      onTap: _delete,
                    ),
                    const SizedBox(width: 4),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A boolean: the value IS the toggle.
  Widget _booleanLeaf() {
    final on = widget.value == true;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          _leafLabel(),
          const SizedBox(width: 8),
          TouchableOpacity(
            activeOpacity: 0.8,
            onTap: _toggleBool,
            child: Container(
              // RN toggleBadge: padH 6 / padV 3 / r4.
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: (on ? BuoyColors.primary : BuoyColors.textMuted)
                    .hexAlpha(0x1A),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: (on ? BuoyColors.primary : BuoyColors.textMuted)
                      .hexAlpha(0x4D),
                ),
              ),
              child: Text(
                on ? 'TRUE' : 'FALSE',
                // RN toggleBadgeText: 9 / w700 / tracking 0.8 / mono.
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                  letterSpacing: 0.8,
                  fontFamily: 'monospace',
                  color: on ? BuoyColors.primary : BuoyColors.textSecondary,
                ),
              ),
            ),
          ),
          const Spacer(),
          if (widget.itemsDeletable)
            _IconAction(
              icon: BuoyIcons.trash2,
              color: BuoyColors.error,
              label: 'Delete item',
              onTap: _delete,
            ),
        ],
      ),
    );
  }

  /// null, or a non-editable tree: shown, not editable.
  Widget _readOnlyLeaf() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        children: [
          Text(
            widget.label,
            // RN text344054: 9 / w600 / mono / tracking 0.4 / opacity 0.8.
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
              letterSpacing: 0.4,
              color: BuoyColors.textSecondary.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 34),
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: BuoyColors.textMuted.hexAlpha(0x66)),
              ),
              child: Text(
                _display(widget.value),
                style: const TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: BuoyColors.text,
                ),
              ),
            ),
          ),
          if (widget.editable && widget.itemsDeletable && _editor != null) ...[
            const SizedBox(width: 6),
            _IconAction(
              icon: BuoyIcons.trash2,
              color: BuoyColors.error,
              label: 'Delete item',
              onTap: _delete,
            ),
          ],
        ],
      ),
    );
  }

  Widget _leafLabel() => SizedBox(
    // RN label: minWidth 60 so the inputs line up down the column.
    width: 60,
    child: Text(
      widget.label.toUpperCase(),
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        fontFamily: 'monospace',
        letterSpacing: 0.5,
        color: _isRowFocused ? BuoyColors.primary : BuoyColors.textMuted,
      ),
    ),
  );

  static String _display(Object? value) {
    if (value == null) return 'null';
    if (value is String) return '"$value"';
    return value.toString();
  }
}

// ── Small parts ──────────────────────────────────────────────────────────────

class _Expander extends StatelessWidget {
  const _Expander({required this.expanded});

  final bool expanded;

  @override
  Widget build(BuildContext context) {
    return Container(
      // RN expanderIcon: 18×18 / r3 / textSecondary@14 fill.
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: BuoyColors.textSecondary.hexAlpha(0x14),
        borderRadius: BorderRadius.circular(3),
      ),
      child: BuoyGlyph(
        expanded ? BuoyIcons.chevronDown : BuoyIcons.chevronRight,
        size: 12,
        color: BuoyColors.textSecondary,
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final LucideIcon icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: TouchableOpacity(
        activeOpacity: 0.7,
        onTap: onTap,
        child: Container(
          // RN deleteButton: 28×28 / r6 / error@1A on error@4D.
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.hexAlpha(0x1A),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.hexAlpha(0x4D)),
          ),
          child: BuoyGlyph(icon, size: 14, color: color.hexAlpha(0xCC)),
        ),
      ),
    );
  }
}

class _TextAction extends StatelessWidget {
  const _TextAction({
    required this.text,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final String text;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: TouchableOpacity(
        activeOpacity: 0.7,
        onTap: onTap,
        child: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          margin: const EdgeInsets.only(left: 4),
          decoration: BoxDecoration(
            color: color.hexAlpha(0x1A),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.hexAlpha(0x4D)),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
              color: color.hexAlpha(0xCC),
            ),
          ),
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.focused,
    required this.onTap,
  });

  final LucideIcon icon;
  final bool focused;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TouchableOpacity(
      activeOpacity: 0.7,
      onTap: onTap,
      child: Container(
        // RN controlButton: 28×28 / r6 / textMuted@33 border.
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: focused
                ? BuoyColors.primary.hexAlpha(0x66)
                : BuoyColors.textMuted.hexAlpha(0x33),
          ),
        ),
        child: BuoyGlyph(
          icon,
          size: 14,
          color: focused ? BuoyColors.primary : BuoyColors.textMuted,
        ),
      ),
    );
  }
}
