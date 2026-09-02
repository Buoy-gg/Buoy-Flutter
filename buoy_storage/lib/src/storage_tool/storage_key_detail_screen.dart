/// Ports packages/storage/src/storage/components/StorageKeyDetailScreen.tsx —
/// one storage key, on a screen of its own, pointed at a stored value.
///
/// Tapping a key card's Edit opens this instead of the draft-and-Save editor.
/// Top to bottom:
///
///   1. VALUE EDITOR — the shared [LiveExplorer]. No draft, no Save: an edit
///      re-serializes the whole value and writes it as you make it. Typing
///      commits on a short debounce (~300ms, flushed on blur) so a word is one
///      storage write, not one per keystroke — storage writes hit disk and
///      land in the events timeline, which is the one way this tool differs
///      from RQ's unlogged cache writes. A scalar key is just the root leaf's
///      input; a boolean key is a one-tap toggle.
///   2. KEY DETAILS — status, backend, MMKV instance, updates (with the road
///      to history).
///   3. VALUE EXPLORER — the serialized string exactly as the backend holds it.
///   4. Housekeeping: pin, hide.
///
/// THE ROUND-TRIP WRINKLE: a storage write is async — write, refresh,
/// refreshed prop. Between an edit and its echo, `storageKey.value` is STALE,
/// so basing the next edit on the prop would silently revert the previous
/// one (edit qty, then name, and qty snaps back). [_lastWritten] holds the
/// most recent written document and is the base for every edit until the
/// prop catches up to it — last-write-wins against the app, exactly once,
/// and never against the editor itself.
///
/// The Raw escape hatch — whole-value JSON for what live rows can't express
/// (add a key, restructure, edit a null) — is the existing
/// [StorageValueEditModal] at path `[]`, one validated write.
library;

import 'dart:convert';

import 'package:buoy_core/buoy_core.dart';
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';

import 'storage_alert.dart';
import 'storage_models.dart';
import 'storage_value_edit_modal.dart';
import 'storage_value_type.dart';

/// RN `TYPING_COMMIT_MS`.
const int _typingCommitMs = 300;

class StorageKeyDetailScreen extends StatefulWidget {
  const StorageKeyDetailScreen({
    super.key,
    required this.storageKey,
    required this.onSave,
    this.editBlockedReason,
    this.eventCount,
    this.onViewHistory,
    this.onHideKey,
    this.isPinned = false,
    this.onTogglePin,
    this.applySafeAreaInset = false,
  });

  final StorageKeyInfo storageKey;

  /// Performs the write of a JSON-serialized whole value. Throwing surfaces
  /// the failure and rolls the editor's base back to what is actually stored.
  final Future<void> Function(String raw) onSave;

  /// Non-null = read-only, with the reason shown in the editor's footer.
  final String? editBlockedReason;
  final int? eventCount;
  final VoidCallback? onViewHistory;
  final ValueChanged<StorageKeyInfo>? onHideKey;
  final bool isPinned;
  final ValueChanged<String>? onTogglePin;
  final bool applySafeAreaInset;

  @override
  State<StorageKeyDetailScreen> createState() => _StorageKeyDetailScreenState();
}

class _StorageKeyDetailScreenState extends State<StorageKeyDetailScreen> {
  bool _rawOpen = false;

  /// Bumped after a Raw-hatch apply so the explorer re-syncs focused inputs.
  int _rawVersion = 0;
  String? _saveFailure;

  /// The most recent document THIS screen wrote, until the refreshed prop
  /// catches up to it. Held as its serialized form so "caught up" is one
  /// string compare against the same serialization the write used.
  ({String raw, Object? value})? _lastWritten;

  bool get _canEdit => widget.editBlockedReason == null;

  String get _propRaw {
    final v = widget.storageKey.value;
    return v is String ? v : jsonEncode(v);
  }

  Object? get _baseValue {
    final last = _lastWritten;
    if (last != null && last.raw == _propRaw) {
      // The device echoed our write back — the prop is current again.
      _lastWritten = null;
      return widget.storageKey.value;
    }
    return last != null ? last.value : widget.storageKey.value;
  }

  void _write(Object? next) {
    final raw = jsonEncode(next);
    setState(() => _lastWritten = (raw: raw, value: next));
    widget.onSave(raw).catchError((Object e) {
      // The write was refused (a dead backend, a type mismatch) — the base
      // must fall back to what's actually stored, or the tree keeps showing
      // an edit that never landed.
      if (!mounted) return;
      setState(() {
        _lastWritten = null;
        _saveFailure = e.toString();
      });
    });
  }

  late final LiveEditWriter _writer = _StorageWriter(this);

  @override
  Widget build(BuildContext context) {
    final key = widget.storageKey;
    final config = _statusConfig(key.status);
    final bottomInset = widget.applySafeAreaInset ? MediaQuery.paddingOf(context).bottom : 0.0;
    final base = _baseValue;

    return Stack(
      children: [
        ListView(
          padding: EdgeInsets.fromLTRB(8, 8, 8, 24 + bottomInset),
          children: [
            // 1 — Value Editor: live, at the top.
            _EditorCard(
              header: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('VALUE EDITOR', style: _accentHeader),
                  if (_canEdit)
                    TouchableOpacity(
                      activeOpacity: 0.7,
                      onTap: () => setState(() => _rawOpen = true),
                      child: Semantics(
                        button: true,
                        label: 'Edit raw JSON',
                        child: Row(
                          spacing: 4,
                          children: const [
                            BuoyGlyph(BuoyIcons.braces, size: 13, color: NightColor.accent),
                            Text(
                              'Raw',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: NightColor.accent,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LiveExplorer(
                    label: 'Value',
                    value: base,
                    editable: _canEdit,
                    writer: _canEdit ? _writer : null,
                    defaultExpanded: const ['Value'],
                    dataVersion: _rawVersion,
                    debounceMs: _typingCommitMs,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 8, left: 4),
                    child: Text(
                      _canEdit
                          ? "Edits write to the device as you make them — undo lives in the key's history."
                          : widget.editBlockedReason!,
                      style: TextStyle(
                        fontSize: 10,
                        fontStyle: FontStyle.italic,
                        color: _canEdit ? NightColor.textTertiary : NightColor.warning,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 2 — Key Details.
            _PlainCard(
              title: 'Key Details',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 6,
                children: [
                  _infoRow('Status:', [
                    PillBadge(color: config.color, size: PillBadgeSize.sm, child: Text(config.label)),
                    _dim(config.sublabel),
                  ]),
                  _infoRow('Storage:', [
                    PillBadge(
                      color: getStorageTypeColor(key.storageType),
                      size: PillBadgeSize.sm,
                      child: Text(getStorageTypeLabel(key.storageType)),
                    ),
                    _dim(getValueTypeLabel(key.value)),
                  ]),
                  if (key.storageType == 'mmkv' && key.instanceId != null)
                    _infoRow('Instance:', [
                      PillBadge(
                        color: NightColor.info,
                        size: PillBadgeSize.sm,
                        child: Text(key.instanceId!),
                      ),
                    ]),
                  if (widget.eventCount != null)
                    _infoRow('Updates:', [
                      PillBadge(
                        color: MacOSColors.warning,
                        size: PillBadgeSize.sm,
                        child: Text('${widget.eventCount}'),
                      ),
                      if (widget.onViewHistory != null)
                        TouchableOpacity(
                          activeOpacity: 0.7,
                          onTap: widget.onViewHistory,
                          child: const Text(
                            'view history →',
                            style: TextStyle(fontSize: 11, color: NightColor.accent),
                          ),
                        ),
                    ]),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 3 — The serialized string exactly as the backend holds it.
            _PlainCard(
              title: 'Value Explorer',
              child: SelectableText(
                _propRaw,
                style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: NightColor.textSecondary,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 4 — Housekeeping.
            if (widget.onTogglePin != null || widget.onHideKey != null)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (widget.onTogglePin != null)
                    _ActionChip(
                      label: widget.isPinned ? 'Unpin' : 'Pin to top',
                      icon: BuoyIcons.pin,
                      color: NightColor.accent,
                      active: widget.isPinned,
                      onTap: () => widget.onTogglePin!(key.key),
                    ),
                  if (widget.onHideKey != null)
                    _ActionChip(
                      label: 'Hide from list',
                      icon: BuoyIcons.eyeOff,
                      color: NightColor.warning,
                      onTap: () => widget.onHideKey!(key),
                    ),
                ],
              ),
          ],
        ),

        if (_rawOpen && _canEdit)
          StorageValueEditModal(
            path: const [],
            value: base,
            saveLabel: 'Apply',
            onSave: (next) {
              _write(next);
              setState(() {
                _rawVersion++;
                _rawOpen = false;
              });
            },
            onCancel: () => setState(() => _rawOpen = false),
          ),

        if (_saveFailure case final failure?)
          StorageAlert(
            title: "Couldn't save",
            message: failure,
            cancelLabel: 'OK',
            actions: const [],
            onCancel: () => setState(() => _saveFailure = null),
          ),
      ],
    );
  }

  static const _accentHeader = TextStyle(
    fontWeight: FontWeight.w600,
    fontSize: 12,
    color: NightColor.accent,
    letterSpacing: 0.5,
    fontFamily: 'monospace',
  );

  Widget _infoRow(String label, List<Widget> children) => Row(
        spacing: 8,
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: NightColor.textSecondary,
                fontFamily: 'monospace',
              ),
            ),
          ),
          ...children,
        ],
      );

  Widget _dim(String text) => Text(
        text,
        style: const TextStyle(fontSize: 11, color: NightColor.textTertiary),
      );

  static ({Color color, String label, String sublabel}) _statusConfig(String status) =>
      switch (status) {
        'required_present' => (color: MacOSColors.success, label: 'Valid', sublabel: 'Required'),
        'required_missing' => (color: MacOSColors.error, label: 'Missing', sublabel: 'Required'),
        'required_wrong_value' => (color: MacOSColors.warning, label: 'Wrong', sublabel: 'Invalid value'),
        'required_wrong_type' => (color: MacOSColors.info, label: 'Type Error', sublabel: 'Wrong type'),
        _ => (color: MacOSColors.debug, label: 'Set', sublabel: 'Optional'),
      };
}

/// Storage replaces the whole key on every write, so any node may go.
class _StorageWriter extends LiveEditWriter {
  _StorageWriter(this.state);
  final _StorageKeyDetailScreenState state;

  @override
  void update(List<String> path, Object? value) {
    final next = path.isEmpty ? value : updateNestedDataByPath(state._baseValue, path, value);
    state._write(next);
  }

  @override
  void Function(List<String> path)? get remove => (path) {
        if (path.isEmpty) return;
        state._write(deleteNestedDataByPath(state._baseValue, path));
      };
}

/// RN editorContainer: night surface, r6, accent@4D border, accent header
/// band (accent@1A, bottom border accent@33).
class _EditorCard extends StatelessWidget {
  const _EditorCard({required this.header, required this.child});
  final Widget header;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: NightColor.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: NightColor.accent.withAlphaByte(0x4D)),
        boxShadow: [BoxShadow(color: NightColor.accent.withValues(alpha: 0.1), blurRadius: 6)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: NightColor.accent.withAlphaByte(0x1A),
              border: Border(bottom: BorderSide(color: NightColor.accent.withAlphaByte(0x33))),
            ),
            child: header,
          ),
          Padding(padding: const EdgeInsets.all(10), child: child),
        ],
      ),
    );
  }
}

class _PlainCard extends StatelessWidget {
  const _PlainCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: NightColor.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: NightColor.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              color: NightColor.surfaceElevated,
              border: Border(bottom: BorderSide(color: NightColor.border)),
            ),
            child: Text(
              title.toUpperCase(),
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12,
                color: NightColor.textSecondary,
                letterSpacing: 0.5,
                fontFamily: 'monospace',
              ),
            ),
          ),
          Padding(padding: const EdgeInsets.all(12), child: child),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.active = false,
  });
  final String label;
  final LucideIcon icon;
  final Color color;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return TouchableOpacity(
      activeOpacity: 0.7,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? color.withAlphaByte(0x1A) : NightColor.surfaceElevated,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: active ? color.withAlphaByte(0x66) : NightColor.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [
            BuoyGlyph(icon, size: 12, color: color),
            Text(
              label,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
