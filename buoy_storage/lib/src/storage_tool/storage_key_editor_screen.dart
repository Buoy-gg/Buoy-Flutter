/// Ports packages/storage/src/storage/components/StorageKeyEditorScreen.tsx and
/// StorageScalarKeyEditor.tsx.
///
/// Editing a key, on a screen of its own.
///
/// Editing used to happen inside the expanded card in the key list: a tree a
/// few rows tall, an action bar wrapped onto three lines, and the rest of the
/// list still scrolling underneath. Every control was competing for the same
/// ~200px.
///
/// So the card now offers ONE edit button and the actual work happens here,
/// with the whole viewport: the tree gets the height, the six structural
/// actions get thumb-sized tiles docked at the bottom where they're always in
/// the same place, and manual JSON editing — the escape hatch, not the main
/// path — moves to a single button in the top-right corner.
///
/// Typing a value happens in a modal pinned to the top of the screen, over the
/// tree rather than instead of it — see [StorageValueEditModal].
///
/// Flutter deviation (structural, not visual): Buoy mounts its dev tools in
/// `MaterialApp.builder`, i.e. ABOVE the app's Navigator, so RN's `Alert.alert`
/// has no Navigator to push onto. The unsaved-changes and failed-save prompts
/// are in-tree overlays instead, following the precedent in
/// buoy_perf_monitor's perf_dialogs.dart.
library;

import 'package:buoy_core/buoy_core.dart';
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';

import 'key_editor.dart';
import 'storage_alert.dart';
import 'storage_models.dart';
import 'storage_value_edit_modal.dart';
import 'storage_value_type.dart';

/// A container and a scalar are different editors, not one editor with a flag.
///
/// A tree of one row is not a tree, so a scalar key skips the whole structural
/// editor and gets just the value modal. Splitting here keeps each editor's
/// state to what it actually needs — see [_StorageScalarKeyEditor].
class StorageKeyEditorScreen extends StatelessWidget {
  const StorageKeyEditorScreen({
    super.key,
    required this.storageKey,
    required this.onSave,
    required this.onClose,
    this.applySafeAreaInset = false,
  });

  final StorageKeyInfo storageKey;

  /// Performs the write. Throwing keeps the work on screen.
  final Future<void> Function(String raw) onSave;

  /// Leave the editor. Called only once any unsaved work is resolved.
  final VoidCallback onClose;

  /// Pad the docked controls past the home indicator.
  ///
  /// These screens put their primary buttons flush against the bottom edge, so
  /// without this the last row of tiles sits under the gesture bar. Off in a
  /// floating window, whose own bottom edge is nowhere near the screen's.
  final bool applySafeAreaInset;

  @override
  Widget build(BuildContext context) {
    final value = storageKey.value;
    return value is Map || value is List
        ? _StorageTreeEditor(
            storageKey: storageKey,
            value: value,
            onSave: onSave,
            onClose: onClose,
            applySafeAreaInset: applySafeAreaInset,
          )
        : _StorageScalarKeyEditor(
            storageKey: storageKey,
            value: value,
            onSave: onSave,
            onClose: onClose,
          );
  }
}

/* ------------------------------------------------------------------ *
 * Containers — tree + structural actions, buffered into a draft.
 * ------------------------------------------------------------------ */

class _StorageTreeEditor extends StatefulWidget {
  const _StorageTreeEditor({
    required this.storageKey,
    required this.value,
    required this.onSave,
    required this.onClose,
    required this.applySafeAreaInset,
  });

  final StorageKeyInfo storageKey;
  final Object? value;
  final Future<void> Function(String raw) onSave;
  final VoidCallback onClose;
  final bool applySafeAreaInset;

  @override
  State<_StorageTreeEditor> createState() => _StorageTreeEditorState();
}

class _StorageTreeEditorState extends State<_StorageTreeEditor> {
  late final KeyEditorController _editor = KeyEditorController(
    value: widget.value,
    save: widget.onSave,
    onClose: widget.onClose,
    confirmDiscard: (choices) => setState(() => _discardPrompt = choices),
  );

  /// Set while the unsaved-changes prompt is up (RN's `Alert.alert`).
  DiscardChoices? _discardPrompt;

  @override
  void dispose() {
    _editor.dispose();
    super.dispose();
  }

  void _dismissPrompt() => setState(() => _discardPrompt = null);

  @override
  Widget build(BuildContext context) {
    final bottomInset = widget.applySafeAreaInset
        ? MediaQuery.viewPaddingOf(context).bottom
        : 0.0;

    return ListenableBuilder(
      listenable: _editor,
      builder: (context, _) {
        final draft = _editor.draft;
        final valuePath = _editor.valuePath;

        return ColoredBox(
          color: MacOSColors.backgroundBase,
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _EditorHeader(
                    storageKey: widget.storageKey,
                    state: draft.isSaving
                        ? 'Saving…'
                        : draft.isDirty
                        ? 'Draft · unsaved'
                        : 'In sync with device',
                    dirty: draft.isDirty,
                    onClose: _editor.requestClose,
                    // Manual editing of the WHOLE value — everything else on
                    // this screen is structural, so raw JSON gets a corner
                    // rather than a tile.
                    onRaw: _editor.openRawEditor,
                  ),
                  _metaRow(draft.value),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: MacOSColors.backgroundCard,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: MacOSColors.borderDefault,
                              ),
                            ),
                            padding: const EdgeInsets.all(6),
                            child: DataViewer(
                              data: draft.value,
                              initialExpanded: true,
                              // Type filtering is a READING aid: the filtered
                              // view is a projection whose row paths don't
                              // address the real document, so the explorer
                              // stops reporting selection while one is active.
                              // An editor whose actions silently go dead isn't
                              // worth the filter.
                              showTypeFilter: false,
                              onSelectionChange: _editor.setSelection,
                              selectPath: draft.selectPath,
                              onRequestInlineEdit: (selection) =>
                                  _editor.openValueEditor(selection.path),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.fromLTRB(4, 8, 4, 0),
                            child: Text(
                              'Tap a row to select it · double-tap to edit its '
                              'value',
                              style: TextStyle(
                                color: MacOSColors.textMuted,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (draft.error != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                      child: Text(
                        draft.error!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: MacOSColors.error,
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  // Dock and commit row share one footer so the safe-area
                  // padding under them carries the footer's own background
                  // rather than the page's, and so the inset lands below
                  // whichever of the two is last.
                  Container(
                    color: MacOSColors.backgroundCard,
                    padding: EdgeInsets.only(bottom: bottomInset),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DataTreeActionDock(
                          root: draft.value,
                          selection: _editor.selection,
                          onEdit: draft.apply,
                          onSelectPath: draft.selectAt,
                          // Booleans never reach this — the dock applies their
                          // flip directly.
                          onEditValue: () => _editor.openValueEditor(
                            _editor.selection?.path ?? const [],
                          ),
                        ),
                        if (draft.isDirty) _commitRow(draft),
                      ],
                    ),
                  ),
                ],
              ),

              // Overlays the tree rather than replacing it, so you can still
              // see what you're editing and where it sits.
              if (valuePath != null)
                StorageValueEditModal(
                  key: ValueKey(valuePath.join(' ')),
                  path: valuePath,
                  value: getAtPath(draft.value, valuePath),
                  onSave: _editor.applyValue,
                  onCancel: _editor.closeValueEditor,
                  // It only reaches the draft here — the single write happens
                  // on Save.
                  saveLabel: 'Apply',
                ),

              if (_discardPrompt case final choices?)
                StorageAlert(
                  title: 'Unsaved changes',
                  message:
                      '"${widget.storageKey.key}" has edits that haven\'t been '
                      'written to the device.',
                  cancelLabel: 'Keep editing',
                  onCancel: _dismissPrompt,
                  actions: [
                    StorageAlertAction(
                      label: 'Discard',
                      destructive: true,
                      onPressed: () {
                        _dismissPrompt();
                        choices.discard();
                      },
                    ),
                    StorageAlertAction(
                      label: 'Save',
                      onPressed: () {
                        _dismissPrompt();
                        choices.save();
                      },
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _metaRow(Object? value) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: Row(
      children: [
        PillBadge(
          color: getStorageTypeColor(widget.storageKey.storageType),
          child: Text(getStorageTypeLabel(widget.storageKey.storageType)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _summarize(value),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: MacOSColors.textMuted,
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    ),
  );

  Widget _commitRow(TreeDraft draft) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 2, 10, 12),
    child: Row(
      children: [
        Expanded(
          flex: 10,
          child: _FooterButton(
            label: 'Discard',
            onTap: draft.isSaving ? null : draft.discard,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 16,
          child: _FooterButton(
            label: draft.isSaving ? 'Saving…' : 'Save changes',
            primary: true,
            onTap: draft.isSaving ? null : _editor.saveAndClose,
          ),
        ),
      ],
    ),
  );
}

/* ------------------------------------------------------------------ *
 * Scalars — one value, one write, no draft.
 * ------------------------------------------------------------------ */

/// Editing a key whose value is a single string, number or boolean.
///
/// A tree of one row is not a tree, so there's nothing here to select, reorder
/// or append to — which means none of the structural editor applies. And with
/// one edit producing one write, there's nothing to buffer either: a draft
/// would only add a step between typing the value and storing it.
///
/// So this is just the value modal over whatever the user was looking at.
/// Changing one string shouldn't black out the screen it came from.
class _StorageScalarKeyEditor extends StatefulWidget {
  const _StorageScalarKeyEditor({
    required this.storageKey,
    required this.value,
    required this.onSave,
    required this.onClose,
  });

  final StorageKeyInfo storageKey;
  final Object? value;
  final Future<void> Function(String raw) onSave;
  final VoidCallback onClose;

  @override
  State<_StorageScalarKeyEditor> createState() =>
      _StorageScalarKeyEditorState();
}

class _StorageScalarKeyEditorState extends State<_StorageScalarKeyEditor> {
  bool _saving = false;
  String? _failure;

  void _save(Object? next) {
    if (_saving) return;
    setState(() => _saving = true);
    widget
        .onSave(jsonEncodeValue(next))
        .then((_) => widget.onClose())
        .catchError((Object e) {
          if (!mounted) return;
          setState(() {
            _saving = false;
            _failure = messageOfStorageError(e);
          });
        });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        StorageValueEditModal(
          path: [widget.storageKey.key],
          value: widget.value,
          onSave: _save,
          onCancel: widget.onClose,
          busy: _saving,
        ),
        if (_failure != null)
          StorageAlert(
            title: 'Couldn\'t save',
            message: _failure,
            cancelLabel: 'OK',
            onCancel: () => setState(() => _failure = null),
            actions: const [],
          ),
      ],
    );
  }
}

/* ------------------------------------------------------------------ *
 * Shared pieces
 * ------------------------------------------------------------------ */

class _EditorHeader extends StatelessWidget {
  const _EditorHeader({
    required this.storageKey,
    required this.state,
    required this.dirty,
    required this.onClose,
    required this.onRaw,
  });

  final StorageKeyInfo storageKey;
  final String state;
  final bool dirty;
  final VoidCallback onClose;
  final VoidCallback onRaw;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: MacOSColors.borderDefault)),
      ),
      child: Row(
        children: [
          TouchableOpacity(
            activeOpacity: 0.6,
            onTap: onClose,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: BuoyGlyph(
                BuoyIcons.x,
                size: 16,
                color: MacOSColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              children: [
                Text(
                  storageKey.key,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: MacOSColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  state,
                  style: TextStyle(
                    color: dirty ? MacOSColors.warning : MacOSColors.textMuted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TouchableOpacity(
            activeOpacity: 0.6,
            onTap: onRaw,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  BuoyGlyph(
                    BuoyIcons.braces,
                    size: 16,
                    color: MacOSColors.info,
                  ),
                  SizedBox(width: 4),
                  Text(
                    'Raw',
                    style: TextStyle(
                      color: MacOSColors.info,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
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
}

class _FooterButton extends StatelessWidget {
  const _FooterButton({required this.label, this.onTap, this.primary = false});

  final String label;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: TouchableOpacity(
        activeOpacity: 0.6,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 46),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: primary ? MacOSColors.success : null,
            borderRadius: BorderRadius.circular(12),
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

/// `array · 3 items` — what the header says the draft currently is.
String _summarize(Object? value) {
  if (value is List) {
    return 'array · ${value.length} item${value.length == 1 ? '' : 's'}';
  }
  if (value is Map) {
    return 'object · ${value.length} key${value.length == 1 ? '' : 's'}';
  }
  return typeLabel(value);
}
