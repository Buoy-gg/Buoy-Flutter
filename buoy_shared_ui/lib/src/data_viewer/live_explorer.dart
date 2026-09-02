/// Ports packages/shared/src/dataViewer/LiveExplorer.tsx — the LIVE data
/// editor: a recursive JSON tree whose leaves are inputs.
///
/// RN hoisted it from react-query's `Explorer` so every tool edits data
/// through ONE implementation: react-query wraps it with a setQueryData
/// writer, zustand with a merge-only setState writer, storage with a
/// whole-key writer. This Dart port was likewise hoisted from buoy_network's
/// response editor (`BuoyExplorer`, itself a port of the same RQ Explorer),
/// which now wraps this widget with a root writer.
///
/// There is no draft and no Save: each change writes through immediately (or
/// on a short debounce — see [LiveExplorer.debounceMs]) and the app reacts
/// while you type. What a leaf renders as is the ORIGINAL value's type, which
/// keeps edits type-safe without asking anything: strings and numbers get an
/// inline input (numbers with steppers and a numeric keyboard), booleans a
/// one-tap TRUE/FALSE toggle, container members a delete ✕, arrays a clear-[]
/// button. Structural edits this tree can't express (add key, rename) belong
/// to the host's Raw escape hatch, not here.
library;

import 'dart:async';

import 'package:buoy_core/buoy_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'nested_path.dart';

/// How the explorer writes into whatever owns the data. The tree never
/// mutates anything itself — every edit is handed to the host through this.
abstract class LiveEditWriter {
  /// Replace the node at `path` with `value`. Fired per committed change.
  void update(List<String> path, Object? value);

  /// Remove the node at `path`. Null → no delete affordances.
  void Function(List<String> path)? get remove => null;

  /// Per-node removal veto. A merge-only host vetoes depth-1 paths — it can
  /// rewrite a top-level key but never delete one. Default: allowed.
  bool canRemove(List<String> path) => true;
}

/// RN `makeRootWriter`: a writer for plain local data — the host supplies
/// get/set of the whole root.
class RootWriter extends LiveEditWriter {
  RootWriter({
    required this.getRoot,
    required this.setRoot,
    bool Function(List<String> path)? canRemove,
  }) : _canRemove = canRemove;

  final Object? Function() getRoot;
  final ValueChanged<Object?> setRoot;
  final bool Function(List<String> path)? _canRemove;

  @override
  void update(List<String> path, Object? value) =>
      setRoot(updateNestedDataByPath(getRoot(), path, value));

  @override
  void Function(List<String> path)? get remove =>
      (path) => setRoot(deleteNestedDataByPath(getRoot(), path));

  @override
  bool canRemove(List<String> path) => _canRemove?.call(path) ?? true;
}

/// RN chunks long lists into pages of 100 with `[0...99]` expanders.
const int _chunkSize = 100;

/// RN caps how many entries it will even enumerate, for big payloads.
const int _maxEntries = 1000;

/// Section labels drawn with the heavier "main section" treatment.
const Set<String> _mainSectionLabels = {
  'DATA', 'STATE', 'VALUE', 'QUERY', 'QUERYKEY', 'TYPES', 'STATS', 'OPTIONS', 'OBSERVERS',
};

/// One node of the tree. Recursive, exactly as RN is.
class LiveExplorer extends StatefulWidget {
  const LiveExplorer({
    super.key,
    required this.label,
    required this.value,
    this.writer,
    this.editable = false,
    this.dataPath = const [],
    this.itemsDeletable = false,
    this.defaultExpanded = const [],
    this.dataVersion = 0,
    this.debounceMs = 0,
  });

  final String label;
  final Object? value;

  /// Absent writer = read-only tree, exactly like `editable: false`.
  final LiveEditWriter? writer;
  final bool editable;
  final List<String> dataPath;

  /// This node sits inside a container, so it can be removed from it.
  final bool itemsDeletable;

  /// Labels that start expanded (RN `defaultExpanded`).
  final List<String> defaultExpanded;

  /// Bump when the subject changes externally to re-sync focused inputs.
  final int dataVersion;

  /// Trailing debounce for TYPED commits (text/number input). 0 = write per
  /// keystroke (react-query). A cache write is free and unlogged; zustand
  /// and storage writes are RECORDED — events timeline, per-store change
  /// counts — and storage's hit disk, so those hosts pass ~300ms: the input
  /// echoes instantly, the write lands one beat after you stop typing
  /// (flushed on blur/dispose), and "granola" is one recorded change instead
  /// of seven. Discrete gestures — toggle, stepper, delete, clear — always
  /// write immediately.
  final int debounceMs;

  @override
  State<LiveExplorer> createState() => _LiveExplorerState();
}

class _LiveExplorerState extends State<LiveExplorer> {
  late bool _expanded;
  final Set<int> _expandedPages = {};
  final FocusNode _focus = FocusNode();
  TextEditingController? _controller;
  bool _isRowFocused = false;

  // Debounced-commit machinery for TYPED input. The pending edit is flushed
  // by the timer, by blur, and by dispose — whichever comes first — so a
  // half-typed value can't be lost, only briefly deferred.
  ({List<String> path, Object? value})? _pending;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _expanded = widget.defaultExpanded.contains(widget.label);
    _focus.addListener(() {
      if (!mounted) return;
      // The pending debounced edit rides along with focus leaving the field.
      if (!_focus.hasFocus) _flushPending();
      setState(() => _isRowFocused = _focus.hasFocus);
    });
    _syncController();
  }

  @override
  void didUpdateWidget(LiveExplorer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // ⚠️ Only sync from an EXTERNAL change, never from our own typing.
    //
    // RN carries the same warning on its `useEffect`: syncing on every render
    // races the edit. You type "5101", the root rebuilds, the effect re-runs
    // while `value` is still the old 5100, and it writes 5100 back over what
    // you just typed. Comparing against the controller's current text is the
    // Flutter equivalent of RN's "do not put localInputValue in the deps".
    if (oldWidget.value != widget.value ||
        oldWidget.label != widget.label ||
        oldWidget.dataVersion != widget.dataVersion) {
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
    _flushPending();
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
      final limited = value.length > _maxEntries ? value.sublist(0, _maxEntries) : value;
      return [
        for (var i = 0; i < limited.length; i++) (label: i.toString(), value: limited[i]),
      ];
    }
    if (value is Map) {
      return [
        for (final entry in value.entries.take(_maxEntries))
          (label: entry.key.toString(), value: entry.value),
      ];
    }
    return const [];
  }

  bool get _isMainSection => _mainSectionLabels.contains(widget.label.toUpperCase());

  // ── Edits ──────────────────────────────────────────────────────────────────

  LiveEditWriter? get _writer => widget.editable ? widget.writer : null;

  /// Whether THIS node may be removed: the parent said its members are
  /// deletable, the writer can delete at all, and the writer doesn't veto
  /// this path.
  bool get _removalAllowed {
    final writer = _writer;
    return widget.itemsDeletable &&
        writer != null &&
        writer.remove != null &&
        writer.canRemove(widget.dataPath);
  }

  void _flushPending() {
    _timer?.cancel();
    _timer = null;
    final pending = _pending;
    _pending = null;
    if (pending != null) _writer?.update(pending.path, pending.value);
  }

  void _handleTextChange(String text) {
    final writer = _writer;
    if (writer == null) return;
    final Object? next;
    if (_valueType == 'number') {
      final parsed = num.tryParse(text);
      // A half-typed number ("-", "1.") isn't an error — RN drops the edit and
      // leaves the field alone until it parses.
      if (parsed == null) return;
      next = parsed;
    } else {
      next = text;
    }
    final ms = widget.debounceMs;
    if (ms > 0) {
      _pending = (path: widget.dataPath, value: next);
      _timer?.cancel();
      _timer = Timer(Duration(milliseconds: ms), _flushPending);
    } else {
      writer.update(widget.dataPath, next);
    }
  }

  /// Steppers are a decision, not typing — commit immediately.
  void _step(int delta) {
    final current = num.tryParse(_controller?.text ?? '') ?? 0;
    final next = current + delta;
    final text = next.toString();
    _controller?.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _pending = null;
    _timer?.cancel();
    _timer = null;
    _writer?.update(widget.dataPath, next);
  }

  void _delete() => _writer?.remove?.call(widget.dataPath);

  void _toggleBool() {
    final current = widget.value is bool ? widget.value! as bool : false;
    _writer?.update(widget.dataPath, !current);
  }

  void _clearArray() => _writer?.update(widget.dataPath, <Object?>[]);

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
        entries.sublist(i, i + _chunkSize > entries.length ? entries.length : i + _chunkSize),
    ];
    final editable = _writer != null;
    final main = _isMainSection;

    return Padding(
      // RN minWidthWrapper: marginVertical 0.5.
      padding: const EdgeInsets.symmetric(vertical: 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            // RN flexRowItemsCenterGap: padV 3 / padH 6 / marginV 1 / r4 /
            // surface@66 with a 0.5 border at textSecondary@1A; main sections
            // (RN flexRowItemsCenterGapMain) sit on surfaceElevated@80.
            margin: const EdgeInsets.symmetric(vertical: 1),
            padding: EdgeInsets.symmetric(horizontal: main ? 8 : 6, vertical: main ? 5 : 3),
            decoration: BoxDecoration(
              color: main
                  ? NightColor.surfaceElevated.withAlphaByte(0x80)
                  : NightColor.surface.withAlphaByte(0x66),
              borderRadius: BorderRadius.circular(main ? 6 : 4),
              border: Border.all(
                color: NightColor.textSecondary.withAlphaByte(main ? 0x33 : 0x1A),
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
                        _Expander(expanded: _expanded, focused: _isRowFocused, main: main),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            widget.label,
                            overflow: TextOverflow.ellipsis,
                            // RN labelText: 10 / w600 / mono / tracking 0.4;
                            // labelTextMain: 11 / w700 / tracking 0.6 / text.
                            style: TextStyle(
                              fontSize: main ? 11 : 10,
                              fontWeight: main ? FontWeight.w700 : FontWeight.w600,
                              fontFamily: 'monospace',
                              letterSpacing: main ? 0.6 : 0.4,
                              color: _isRowFocused
                                  ? NightColor.accent
                                  : main
                                      ? NightColor.text
                                      : NightColor.textSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${entries.length} ${entries.length > 1 ? 'items' : 'item'}',
                          // RN textGray500: 10 / w400 / mono / opacity 0.7.
                          style: TextStyle(
                            fontSize: 10,
                            fontFamily: 'monospace',
                            color: NightColor.textTertiary.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (editable) ...[
                  if (_removalAllowed)
                    _IconAction(
                      icon: BuoyIcons.trash2,
                      color: NightColor.danger,
                      label: 'Delete item',
                      focused: _isRowFocused,
                      onTap: _delete,
                    ),
                  if (_valueType == 'array')
                    _TextAction(
                      text: '[]',
                      color: NightColor.warning,
                      label: 'Remove all items',
                      focused: _isRowFocused,
                      onTap: _clearArray,
                    ),
                ],
              ],
            ),
          ),
          if (_expanded)
            if (pages.length == 1)
              _indented(main, [
                for (var i = 0; i < pages.first.length; i++)
                  _child(pages.first[i], key: '${pages.first[i].label}-$i'),
              ])
            else
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [for (var page = 0; page < pages.length; page++) _page(page, pages[page])],
                ),
              ),
        ],
      ),
    );
  }

  Widget _child(({String label, Object? value}) entry, {required String key}) => LiveExplorer(
        key: ValueKey(key),
        label: entry.label,
        value: entry.value,
        writer: widget.writer,
        editable: widget.editable,
        defaultExpanded: widget.defaultExpanded,
        dataPath: [...widget.dataPath, entry.label],
        // Anything inside a container can be removed from it.
        itemsDeletable: true,
        dataVersion: widget.dataVersion,
        debounceMs: widget.debounceMs,
      );

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
                  '[${index * _chunkSize}...${index * _chunkSize + _chunkSize - 1}]',
                  style: const TextStyle(
                    fontSize: 10,
                    fontFamily: 'monospace',
                    color: NightColor.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (open) _indented(false, [for (final entry in entries) _child(entry, key: entry.label)]),
      ],
    );
  }

  /// RN singleEntryContainer: the 1.5px left guide line that makes nesting
  /// readable without indenting everything off the screen.
  Widget _indented(bool main, List<Widget> children) => Container(
        margin: EdgeInsets.only(left: main ? 4 : 2, top: 2),
        padding: EdgeInsets.only(left: main ? 10 : 8),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: NightColor.textSecondary.withAlphaByte(main ? 0x4D : 0x40),
              width: 1.5,
            ),
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );

  // ── Leaves ─────────────────────────────────────────────────────────────────

  Widget _leaf() {
    final editable = _writer != null;
    final type = _valueType;
    if (editable && (type == 'string' || type == 'number')) {
      return _inputLeaf(isNumber: type == 'number');
    }
    if (editable && type == 'boolean') return _booleanLeaf();
    return _readOnlyLeaf();
  }

  /// A string or number: the value IS the input. No edit affordance, because
  /// there is nothing to switch into. (RN CyberpunkInput.)
  Widget _inputLeaf({required bool isNumber}) {
    return Padding(
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
                color: NightColor.surfaceElevated,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _isRowFocused ? NightColor.accent : NightColor.border,
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
                          ? const TextInputType.numberWithOptions(signed: true, decimal: true)
                          : TextInputType.text,
                      inputFormatters:
                          isNumber ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]'))] : null,
                      onChanged: _handleTextChange,
                      // RN input: padH 10 / padV 6 / mono 12 / text.
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        fontWeight: isNumber ? FontWeight.w600 : FontWeight.w400,
                        color: NightColor.text,
                      ),
                      cursorColor: NightColor.accent,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      ),
                    ),
                  ),
                  if (isNumber) ...[
                    _StepButton(icon: BuoyIcons.chevronUp, focused: _isRowFocused, onTap: () => _step(1)),
                    const SizedBox(width: 2),
                    _StepButton(icon: BuoyIcons.chevronDown, focused: _isRowFocused, onTap: () => _step(-1)),
                    const SizedBox(width: 4),
                  ],
                  if (_removalAllowed) ...[
                    _IconAction(
                      icon: BuoyIcons.trash2,
                      color: NightColor.danger,
                      label: 'Delete item',
                      focused: _isRowFocused,
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
              // RN toggleBadge: padH 6 / padV 3 / r4 / marginLeft 6.
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: (on ? NightColor.accent : NightColor.textTertiary).withAlphaByte(0x1A),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: (on ? NightColor.accent : NightColor.textTertiary).withAlphaByte(0x4D),
                ),
              ),
              child: Text(
                on ? 'TRUE' : 'FALSE',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                  letterSpacing: 0.8,
                  fontFamily: 'monospace',
                  color: on ? NightColor.accent : NightColor.textSecondary,
                ),
              ),
            ),
          ),
          const Spacer(),
          if (_removalAllowed)
            _IconAction(
              icon: BuoyIcons.trash2,
              color: NightColor.danger,
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
              color: NightColor.textSecondary.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 34),
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: NightColor.border),
              ),
              child: Text(
                _display(widget.value),
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: NightColor.text),
              ),
            ),
          ),
          if (_removalAllowed) ...[
            const SizedBox(width: 6),
            _IconAction(
              icon: BuoyIcons.trash2,
              color: NightColor.danger,
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
            color: _isRowFocused ? NightColor.accent : NightColor.textTertiary,
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
  const _Expander({required this.expanded, this.focused = false, this.main = false});

  final bool expanded;
  final bool focused;
  final bool main;

  @override
  Widget build(BuildContext context) {
    final size = main ? 20.0 : 18.0;
    return Container(
      // RN expanderIcon: 18×18 / r3 / textSecondary@14 fill (main 20 / r4).
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: NightColor.textSecondary.withAlphaByte(main ? 0x1F : 0x14),
        borderRadius: BorderRadius.circular(main ? 4 : 3),
      ),
      child: BuoyGlyph(
        expanded ? BuoyIcons.chevronDown : BuoyIcons.chevronRight,
        size: main ? 14 : 12,
        color: focused
            ? NightColor.accent
            : main
                ? NightColor.text
                : NightColor.textSecondary,
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
    this.focused = false,
  });

  final LucideIcon icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: TouchableOpacity(
        activeOpacity: 0.7,
        onTap: onTap,
        child: Container(
          // RN deleteButton: 28×28 / r6 / colour@1A on colour@4D.
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withAlphaByte(focused ? 0x26 : 0x1A),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withAlphaByte(focused ? 0x80 : 0x4D)),
          ),
          child: BuoyGlyph(icon, size: 14, color: focused ? color : color.withAlphaByte(0xCC)),
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
    this.focused = false,
  });

  final String text;
  final Color color;
  final String label;
  final VoidCallback onTap;
  final bool focused;

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
            color: color.withAlphaByte(focused ? 0x26 : 0x1A),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withAlphaByte(focused ? 0x80 : 0x4D)),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
              color: focused ? color : color.withAlphaByte(0xCC),
            ),
          ),
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.focused, required this.onTap});

  final LucideIcon icon;
  final bool focused;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TouchableOpacity(
      activeOpacity: 0.7,
      onTap: onTap,
      child: Container(
        // RN controlButton: 28×28 / r6 / textTertiary@33 border.
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: focused ? NightColor.accent.withAlphaByte(0x66) : NightColor.textTertiary.withAlphaByte(0x33),
          ),
        ),
        child: BuoyGlyph(icon, size: 14, color: focused ? NightColor.accent : NightColor.textTertiary),
      ),
    );
  }
}
