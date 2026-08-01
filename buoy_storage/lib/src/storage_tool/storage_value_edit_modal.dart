/// Ports packages/storage/src/storage/components/StorageValueEditModal.tsx.
///
/// Editing one value: a panel at the top of the screen, with Cancel and Save.
///
/// This started as a pushed full screen and that was more ceremony than the
/// task deserves — changing one string is the most ordinary thing in this tool,
/// and it shouldn't cost a navigation. A modal is what people expect, and the
/// reason it's pinned to the TOP rather than centred is the keyboard: a centred
/// panel gets shoved up or covered the moment the field focuses, and a bottom
/// sheet is simply underneath it. At the top it stays put and stays readable.
///
/// The field is multiline for anything textual. Stored values are routinely
/// tokens, URLs and serialized blobs, and a single line shows you roughly forty
/// characters of them, scrolling sideways — which is how you edit the wrong
/// part of a string without noticing.
///
/// Type is preserved by construction: the ORIGINAL value's type picks the
/// editor AND decides how the draft is read back, so editing a number can only
/// produce a number. Raw JSON — the escape hatch for containers — re-checks the
/// parsed result and refuses a different shape.
///
/// Nothing here writes. `onSave` hands the value to whoever owns it.
///
/// RN numerics preserved: card radius 14 / padding 14 / gap 8, field maxHeight
/// 240, input radius 10 / padH 12 / padV 10, multiline minHeight 110 (raw 180),
/// buttons minHeight 44 with the save flex 1.4, boolean tiles minHeight 64.
library;

import 'dart:convert';

import 'package:buoy_core/buoy_core.dart';
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';

/// How this value gets edited. Driven by the value's own type, which is also
/// what makes the result type-safe without asking the user to declare anything.
enum _EditorMode { text, number, boolean, raw }

_EditorMode _modeFor(Object? value) {
  if (value is bool) return _EditorMode.boolean;
  if (value is num) return _EditorMode.number;
  if (value is Map || value is List) return _EditorMode.raw;
  return _EditorMode.text;
}

String _initialText(Object? value, _EditorMode mode) {
  if (mode == _EditorMode.raw) {
    return const JsonEncoder.withIndent('  ').convert(value);
  }
  if (value == null) return '';
  return '$value';
}

String _hintFor(_EditorMode mode, String type) => switch (mode) {
  _EditorMode.number =>
    'Numeric only — anything else is refused, so this stays a number.',
  _EditorMode.raw =>
    'Raw JSON. Must stay ${type == 'array' ? 'an array' : 'an object'} — '
        'a different shape is refused.',
  _ => 'Saves as a string. The type never changes here.',
};

class StorageValueEditModal extends StatefulWidget {
  const StorageValueEditModal({
    super.key,
    required this.path,
    required this.value,
    required this.onSave,
    required this.onCancel,
    this.saveLabel = 'Save',
    this.busy = false,
  });

  /// Path into the value being edited — labels the panel, never used to write.
  final List<String> path;
  final Object? value;
  final ValueChanged<Object?> onSave;
  final VoidCallback onCancel;

  /// "Save" when this writes, "Apply" when it only updates a draft.
  final String saveLabel;

  /// Disables the controls while a write is in flight.
  final bool busy;

  @override
  State<StorageValueEditModal> createState() => _StorageValueEditModalState();
}

class _StorageValueEditModalState extends State<StorageValueEditModal> {
  late final _EditorMode _mode = _modeFor(widget.value);
  late final String _type = typeLabel(widget.value);
  late final TextEditingController _controller = TextEditingController(
    text: _initialText(widget.value, _mode),
  );
  late final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
    if (_mode != _EditorMode.boolean) {
      // Autofocus, matching RN's `autoFocus` — the panel exists to be typed in.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Advisory only — [_commit] re-derives it, so a disabled button and a
  /// refused save can never disagree about what's valid.
  String? get _error => _validate(_controller.text, _mode, _type);

  void _commit() {
    if (widget.busy || _validate(_controller.text, _mode, _type) != null) return;
    widget.onSave(_parse(_controller.text, _mode, widget.value));
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    final blocked = widget.busy || error != null;

    return Positioned.fill(
      child: Stack(
        children: [
          // Tapping outside cancels, which is the expected way out of a modal.
          // It's safe here because nothing has been written yet.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.busy ? null : widget.onCancel,
              child: const ColoredBox(color: Color(0x8C000000)),
            ),
          ),
          // Pinned to the top so the keyboard can't reach it.
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: GestureDetector(
                onTap: () {},
                child: Container(
                  decoration: BoxDecoration(
                    color: MacOSColors.backgroundCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: MacOSColors.borderDefault),
                  ),
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _header(),
                      const SizedBox(height: 8),
                      Text(
                        breadcrumb(widget.path),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: MacOSColors.textMuted,
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_mode == _EditorMode.boolean)
                        _BooleanChoice(
                          current: widget.value == true,
                          onPick: widget.onSave,
                        )
                      else
                        _field(error != null),
                      const SizedBox(height: 8),
                      Text(
                        error ?? _hintFor(_mode, _type),
                        style: TextStyle(
                          color: error != null
                              ? MacOSColors.error
                              : MacOSColors.textMuted,
                          fontSize: 11,
                          height: 1.45,
                          fontFamily: error != null ? 'monospace' : null,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _actions(blocked),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() => Row(
    children: [
      const Expanded(
        child: Text(
          'Edit value',
          style: TextStyle(
            color: MacOSColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      const SizedBox(width: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: MacOSColors.backgroundHover,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          _type,
          style: const TextStyle(
            color: MacOSColors.warning,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            fontFamily: 'monospace',
          ),
        ),
      ),
    ],
  );

  /// Caps the panel's height so a huge blob can't push the buttons off-screen.
  Widget _field(bool invalid) {
    final isNumber = _mode == _EditorMode.number;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 240),
      child: SingleChildScrollView(
        child: TextField(
          controller: _controller,
          focusNode: _focus,
          enabled: !widget.busy,
          autocorrect: false,
          enableSuggestions: false,
          // Multiline for anything textual: stored values are long more often
          // than they're short, and a single line hides that.
          maxLines: isNumber ? 1 : null,
          minLines: isNumber ? 1 : (_mode == _EditorMode.raw ? 9 : 5),
          keyboardType: isNumber
              ? const TextInputType.numberWithOptions(signed: true, decimal: true)
              : TextInputType.multiline,
          onSubmitted: isNumber ? (_) => _commit() : null,
          style: TextStyle(
            color: MacOSColors.textPrimary,
            fontSize: _mode == _EditorMode.raw ? 12 : 14,
            height: _mode == _EditorMode.raw ? 1.5 : 1.4,
            fontFamily: 'monospace',
          ),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: MacOSColors.backgroundInput,
            hintText: _mode == _EditorMode.raw ? '{ }' : 'value',
            hintStyle: const TextStyle(
              color: MacOSColors.textMuted,
              fontSize: 14,
              fontFamily: 'monospace',
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            border: _border(invalid),
            enabledBorder: _border(invalid),
            focusedBorder: _border(invalid),
            disabledBorder: _border(invalid),
          ),
        ),
      ),
    );
  }

  OutlineInputBorder _border(bool invalid) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: BorderSide(
      color: invalid ? MacOSColors.error : MacOSColors.borderInput,
    ),
  );

  /// A boolean commits from its choice — an extra Save would be a button press
  /// with no decision left in it.
  Widget _actions(bool blocked) => Row(
    children: [
      // 10 : 14 is RN's `flex: 1` / `flex: 1.4` split — Flutter's flex is an int.
      Expanded(
        flex: 10,
        child: _Button(
          label: 'Cancel',
          onTap: widget.busy ? null : widget.onCancel,
        ),
      ),
      if (_mode != _EditorMode.boolean) ...[
        const SizedBox(width: 8),
        Expanded(
          flex: 14,
          child: _Button(
            label: widget.busy ? 'Saving…' : widget.saveLabel,
            primary: true,
            onTap: blocked ? null : _commit,
          ),
        ),
      ],
    ],
  );
}

class _BooleanChoice extends StatelessWidget {
  const _BooleanChoice({required this.current, required this.onPick});

  final bool current;
  final ValueChanged<bool> onPick;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final option in const [true, false]) ...[
          if (option == false) const SizedBox(width: 10),
          Expanded(
            child: TouchableOpacity(
              activeOpacity: 0.6,
              onTap: () => onPick(option),
              child: Container(
                constraints: const BoxConstraints(minHeight: 64),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: current == option
                      ? MacOSColors.warning.hexAlpha(0x18)
                      : MacOSColors.backgroundBase,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: current == option
                        ? MacOSColors.warning
                        : MacOSColors.borderDefault,
                  ),
                ),
                child: Text(
                  option ? 'true' : 'false',
                  style: TextStyle(
                    color: current == option
                        ? MacOSColors.warning
                        : MacOSColors.textMuted,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Button extends StatelessWidget {
  const _Button({required this.label, this.onTap, this.primary = false});

  final String label;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Opacity(
      opacity: disabled ? (primary ? 0.35 : 0.5) : 1,
      child: TouchableOpacity(
        activeOpacity: 0.6,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: primary ? MacOSColors.success : null,
            borderRadius: BorderRadius.circular(10),
            border: primary
                ? null
                : Border.all(color: MacOSColors.borderDefault),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: primary
                  ? MacOSColors.backgroundBase
                  : MacOSColors.textSecondary,
              fontSize: primary ? 15 : 14,
              fontWeight: primary ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// Null when the draft is applicable, else why it isn't.
String? _validate(String text, _EditorMode mode, String type) {
  if (mode == _EditorMode.number) {
    if (text.trim().isEmpty) return 'Enter a number.';
    if (num.tryParse(text.trim()) == null) return '"$text" isn\'t a number.';
    return null;
  }
  if (mode == _EditorMode.raw) {
    final Object? parsed;
    try {
      parsed = jsonDecode(text);
    } catch (e) {
      return '$e';
    }
    if (typeLabel(parsed) != type) {
      return 'Must stay $type — that parses as ${typeLabel(parsed)}.';
    }
    return null;
  }
  return null;
}

Object? _parse(String text, _EditorMode mode, Object? original) {
  if (mode == _EditorMode.number) return num.parse(text.trim());
  if (mode == _EditorMode.raw) return jsonDecode(text);
  // An emptied field on a null keeps it null rather than silently minting an
  // empty string, which would change the type this promised to preserve.
  if (original == null && text.isEmpty) return null;
  return text;
}
