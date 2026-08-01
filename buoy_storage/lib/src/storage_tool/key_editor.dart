/// Ports packages/storage/src/storage/hooks/useTreeDraft.ts and
/// hooks/useKeyEditor.ts — the two hooks the RN editor is built out of, as one
/// [ChangeNotifier] pair the editor screen listens to.
///
/// **The draft.** A local copy of a storage value, edited in place and written
/// ONCE. Applying each tree op straight to the device was the obvious first cut
/// and it behaves badly for two compounding reasons:
///
/// 1. **Every op is a round trip.** The write lands, the device emits a storage
///    event, and the browser re-reads every backend — so a six-tap reorder is
///    six writes and six full refreshes, rebuilding the tree under the user
///    mid-gesture.
/// 2. **The highlight and the value fall out of step.** Selection is local and
///    moves instantly; the value it points at only catches up when the round
///    trip completes, so for a beat the highlight sits on the old contents.
///
/// Buffering fixes both, and it's what every editor that owns a document does.
/// The trade is that the buffer can go stale if the app writes the same key
/// while you're editing — the same last-write-wins a text editor has, and
/// [TreeDraft.isDirty] at least makes it visible that you're holding unsaved
/// changes.
///
/// **The editor.** Everything editing a key involves, minus how it looks: one
/// buffered draft, one write on save, a selection the structural actions
/// operate on, a modal for typing a value, and a guard so closing can't
/// silently drop unsaved work. Keeping the rules here means presentation can
/// change without moving the things that would actually hurt — whether a
/// boolean opens an editor, whether a failed write closes the editor anyway,
/// what "dirty" means.
library;

import 'dart:convert';

import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/foundation.dart';

/// A local draft of a value, edited by op and written once.
class TreeDraft extends ChangeNotifier {
  TreeDraft({required Object? liveValue, Future<void> Function(String raw)? save})
    : _live = liveValue,
      _save = save;

  final Object? _live;
  final Future<void> Function(String raw)? _save;

  Object? _draft;
  bool _isEditing = false;
  bool _isSaving = false;
  String? _error;
  SelectionAfterOp _selectPath = const SelectionUnchanged();

  /// The value as it was when editing began. Compared against for dirtiness
  /// rather than against the live value, which can move underneath us if the
  /// app writes the same key — that would otherwise flip a clean draft to dirty.
  String _baseline = '';

  /// True while the tree is in edit mode.
  bool get isEditing => _isEditing;

  /// What the tree should render — the draft while editing, else the live value.
  Object? get value => _isEditing ? _draft : _live;

  /// True when the draft differs from what's stored.
  bool get isDirty => _isEditing && _encode(_draft) != _baseline;

  /// True while the single write is in flight.
  bool get isSaving => _isSaving;

  /// Error from the last save attempt, or null.
  String? get error => _error;

  /// Where the tree should move its highlight after the last op.
  SelectionAfterOp get selectPath => _selectPath;

  void begin() {
    _draft = _live;
    _baseline = _encode(_live);
    _selectPath = const SelectionUnchanged();
    _error = null;
    _isEditing = true;
    notifyListeners();
  }

  /// Apply one op to the DRAFT. Nothing is written.
  void apply(JsonOp op) {
    // Purely local — this is the whole point. No write, so no event, no
    // snapshot, no refresh, and the tree rebuilds from state synchronously.
    _draft = applyJsonOp(_draft, op);
    final next = selectionPathAfterOp(op);
    if (next is! SelectionUnchanged) _selectPath = next;
    notifyListeners();
  }

  /// Move the highlight explicitly, for the ops that CREATE a node.
  /// [selectionPathAfterOp] handles the ones that move or delete a node, but it
  /// can't handle these — it doesn't see the container, so it can't know an
  /// append landed at index 3.
  void selectAt(List<String> path) {
    _selectPath = SelectionAfterOp(path);
    notifyListeners();
  }

  /// Write the draft to storage and leave edit mode. No-op write when clean.
  ///
  /// Resolves `true` when the value is safely stored and `false` when the write
  /// was refused — it never throws, because a failed save is a state this class
  /// handles (it keeps edit mode open and sets [error]). Callers that navigate
  /// away on save MUST check the result, or they'll close over a draft that was
  /// never written and show the user nothing.
  Future<bool> commit() async {
    final save = _save;
    if (!isDirty || save == null) {
      discard();
      return true;
    }
    _isSaving = true;
    _error = null;
    notifyListeners();
    try {
      await save(_encode(_draft));
      discard();
      return true;
    } catch (e) {
      // Stay in edit mode so the work isn't lost to a failed write.
      _error = _messageOf(e);
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  /// Throw the draft away and leave edit mode.
  void discard() {
    _isEditing = false;
    _draft = null;
    _selectPath = const SelectionUnchanged();
    _error = null;
    notifyListeners();
  }

  static String _encode(Object? value) {
    try {
      return jsonEncode(value);
    } catch (_) {
      // Not JSON-encodable, so it can't be compared structurally either. A
      // stable string keeps `isDirty` honest instead of throwing mid-keystroke.
      return '$value';
    }
  }
}

/// What the host should do about unsaved work — the host owns the prompt
/// because a phone wants an alert and a docked panel may not.
class DiscardChoices {
  const DiscardChoices({required this.save, required this.discard});

  final VoidCallback save;
  final VoidCallback discard;
}

/// The editor's rules: draft + selection + which node the value modal is on.
class KeyEditorController extends ChangeNotifier {
  KeyEditorController({
    required Object? value,
    required Future<void> Function(String raw) save,
    required this.onClose,
    required this.confirmDiscard,
  }) : draft = TreeDraft(liveValue: value, save: save) {
    draft.addListener(notifyListeners);
    // Seed the draft ONCE, when the editor opens — re-seeding would reset it
    // mid-edit and discard the user's work every time the key list refreshes
    // underneath us.
    draft.begin();
  }

  final TreeDraft draft;
  final VoidCallback onClose;

  /// Asks the user what to do about unsaved work. Called only when dirty.
  final void Function(DiscardChoices choices) confirmDiscard;

  /// The tree row the structural actions apply to.
  DataTreeSelection? selection;

  /// Which node the value modal is open on. Null means it's closed.
  List<String>? valuePath;

  void setSelection(DataTreeSelection? next) {
    selection = next;
    notifyListeners();
  }

  /// "Change this node". For a boolean that's a flip rather than a modal — the
  /// same rule [treeActionsFor] applies to the action controls, so the gesture
  /// and the button can't mean different things.
  void openValueEditor(List<String> path) {
    final current = getAtPath(draft.value, path);
    if (current is bool) {
      draft.apply(JsonReplaceOp(path, !current));
      return;
    }
    valuePath = path;
    notifyListeners();
  }

  void closeValueEditor() {
    valuePath = null;
    notifyListeners();
  }

  /// Take the modal's result into the draft.
  void applyValue(Object? next) {
    draft.apply(JsonReplaceOp(valuePath ?? const [], next));
    valuePath = null;
    notifyListeners();
  }

  /// Open the modal on the whole value — the manual/raw JSON escape hatch.
  void openRawEditor() {
    valuePath = const [];
    notifyListeners();
  }

  /// Write, and leave only if the write landed.
  ///
  /// [TreeDraft.commit] resolves false and keeps the draft on screen when the
  /// device refuses it; closing anyway would throw the work away while showing
  /// an error nobody ever sees.
  void saveAndClose() {
    draft.commit().then((saved) {
      if (saved) onClose();
    });
  }

  /// Leave, resolving unsaved work first.
  void requestClose() {
    if (!draft.isDirty) {
      onClose();
      return;
    }
    // The draft is the only copy of this work, so closing over it silently is
    // the one way this editor can lose something the user can't get back.
    confirmDiscard(
      DiscardChoices(
        save: saveAndClose,
        discard: () {
          draft.discard();
          onClose();
        },
      ),
    );
  }

  @override
  void dispose() {
    draft.removeListener(notifyListeners);
    draft.dispose();
    super.dispose();
  }
}

/// A thrown object's message without the `Exception: ` / `Bad state: ` prefix
/// noise — these reach the user verbatim.
String messageOfStorageError(Object error) {
  if (error is StateError) return error.message;
  if (error is ArgumentError) return '${error.message}';
  return '$error';
}

String _messageOf(Object error) => messageOfStorageError(error);

/// Serialize an edited value the way every caller of `setStorageValue` does.
/// A value that won't encode can't be written either, so this throws rather
/// than inventing a string the backend would then store.
String jsonEncodeValue(Object? value) => jsonEncode(value);
