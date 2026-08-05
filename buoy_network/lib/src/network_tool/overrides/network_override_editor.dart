/// Ports packages/network/src/network/components/NetworkOverrideEditor.tsx.
///
/// The rule editor, shaped by one rule: **describe the OUTCOME, not the data
/// model**. Nobody thinks "kind=respond, status=500" — they think "make this
/// fail with a server error". So the whole thing is one grid of outcomes, and
/// everything that only sometimes matters (which requests, what body) hides
/// behind a disclosure that shows its own summary when closed.
///
/// The response body uses [BuoyExplorer], the 1:1 port of RN's Explorer:
/// preview and editor are ONE surface, with no read/edit mode to switch
/// between. `Edit all` still takes a pasted payload, same as RN.
library;

import 'dart:convert';

import 'package:buoy_core/buoy_core.dart';
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../overrides/override_rule.dart';
import '../response_editor/explorer.dart';

/// One selectable outcome. RN calls these OutcomeChips.
class _Outcome {
  const _Outcome(this.label, {this.status, this.kind, this.failKind});
  final String label;
  final int? status;
  final OverrideRuleKind? kind;
  final OverrideFailKind? failKind;
}

/// The grid, in the order RN settled on: the errors people actually test,
/// then the two transport failures, then "leave it alone".
const List<_Outcome> _outcomes = [
  _Outcome('Server error', status: 500),
  _Outcome('Unauthorized', status: 401),
  _Outcome('Not found', status: 404),
  _Outcome('Forbidden', status: 403),
  _Outcome('Rate limited', status: 429),
  _Outcome('Unavailable', status: 503),
  _Outcome('Bad request', status: 400),
  _Outcome('Success', status: 200),
  _Outcome(
    'Offline',
    kind: OverrideRuleKind.fail,
    failKind: OverrideFailKind.network,
  ),
  _Outcome(
    'Timeout',
    kind: OverrideRuleKind.fail,
    failKind: OverrideFailKind.timeout,
  ),
  _Outcome('Real response', kind: OverrideRuleKind.delay),
];

const List<int> _delayPresets = [0, 500, 1000, 3000, 10000];
const List<String> _methods = [
  'Any',
  'GET',
  'POST',
  'PUT',
  'PATCH',
  'DELETE',
];

class NetworkOverrideEditor extends StatefulWidget {
  const NetworkOverrideEditor({
    super.key,
    required this.draft,
    required this.onSave,
    required this.onCancel,
    required this.saveLabel,
    this.applySafeAreaInset = true,
  });

  final OverrideRule draft;
  final ValueChanged<OverrideRule> onSave;
  final VoidCallback onCancel;
  final String saveLabel;

  /// Only a bottom sheet sits on the home indicator; a floating window does
  /// not, and padding by it there just wastes a row of the editor.
  final bool applySafeAreaInset;

  @override
  State<NetworkOverrideEditor> createState() => _NetworkOverrideEditorState();
}

class _NetworkOverrideEditorState extends State<NetworkOverrideEditor> {
  late OverrideRule _draft;
  late final TextEditingController _patternController;

  bool _appliesOpen = false;
  bool _bodyOpen = false;

  /// The "Edit all" buffer — deliberately NOT seeded with the current body. An
  /// override body can be hundreds of KB, and pre-filling a text field with it
  /// makes the field unusable to the person who only wants to paste.
  TextEditingController? _rawController;

  Object? _bodyTree;
  bool _bodyIsJson = false;

  @override
  void initState() {
    super.initState();
    _draft = widget.draft;
    _patternController = TextEditingController(text: _draft.urlPattern);
    _decodeBody();
  }

  @override
  void dispose() {
    _patternController.dispose();
    _rawController?.dispose();
    super.dispose();
  }

  void _decodeBody() {
    final body = (_draft.body ?? '').trim();
    if (body.isEmpty) {
      _bodyTree = null;
      _bodyIsJson = false;
      return;
    }
    try {
      _bodyTree = jsonDecode(body);
      _bodyIsJson = true;
    } catch (_) {
      _bodyTree = null;
      _bodyIsJson = false;
    }
  }

  void _patch(OverrideRule next) => setState(() => _draft = next);

  /// Write the edited tree back as the rule's body text.
  void _commitTree(Object? tree) {
    setState(() {
      _bodyTree = tree;
      _draft = _draft.copyWith(
        body: const JsonEncoder.withIndent('  ').convert(tree),
      );
    });
  }

  bool _isSelected(_Outcome outcome) {
    if (outcome.kind == OverrideRuleKind.delay) {
      return _draft.kind == OverrideRuleKind.delay;
    }
    if (outcome.kind == OverrideRuleKind.fail) {
      return _draft.kind == OverrideRuleKind.fail &&
          (_draft.failKind ?? OverrideFailKind.network) == outcome.failKind;
    }
    return _draft.kind == OverrideRuleKind.respond &&
        _draft.status == outcome.status;
  }

  /// True when the rule uses a status the grid doesn't offer — the trailing
  /// "Custom" tile then shows the number instead of the word.
  bool get _isCustomStatus =>
      _draft.kind == OverrideRuleKind.respond &&
      !_outcomes.any(
        (o) => o.status != null && o.status == _draft.status,
      );

  void _selectOutcome(_Outcome outcome) {
    if (outcome.kind == OverrideRuleKind.delay) {
      _patch(_draft.copyWith(kind: OverrideRuleKind.delay));
      return;
    }
    if (outcome.kind == OverrideRuleKind.fail) {
      _patch(
        _draft.copyWith(
          kind: OverrideRuleKind.fail,
          failKind: outcome.failKind,
        ),
      );
      return;
    }
    _patch(
      _draft.copyWith(
        kind: OverrideRuleKind.respond,
        status: outcome.status,
        statusText: null,
      ),
    );
  }

  Future<void> _promptNumber({
    required String title,
    required String hint,
    required int? initial,
    required int min,
    required int max,
    required ValueChanged<int> onSubmit,
  }) async {
    final controller = TextEditingController(text: initial?.toString() ?? '');
    final value = await showDialog<int>(
      context: context,
      builder: (context) => _NumberPrompt(
        title: title,
        hint: hint,
        controller: controller,
        min: min,
        max: max,
      ),
    );
    controller.dispose();
    if (value != null) onSubmit(value);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = widget.applySafeAreaInset
        ? MediaQuery.viewPaddingOf(context).bottom
        : 0.0;

    return Column(
      children: [
        Expanded(
          child: ListView(
            // RN scrollContent: padding 12, paddingBottom 24.
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            // The gaps are RN's, resolved. RN sets `gap: 4` on the scroll
            // content and then pads each block itself — `outcomeGrid` carries
            // paddingVertical 10, `field` carries 6 — so the visible rhythm is
            // 4+10 above and below the grid, 4+6 around the labelled rows.
            children: [
              _appliesTo(),
              const SizedBox(height: 14),
              _outcomeGrid(),
              const SizedBox(height: 14),
              if (_draft.kind == OverrideRuleKind.respond) ...[
                _responseBody(),
                const SizedBox(height: 10),
              ],
              _delayRow(),
              const SizedBox(height: 16),
              _firesRow(),
            ],
          ),
        ),
        _footer(bottomInset),
      ],
    );
  }

  // ── Applies to ─────────────────────────────────────────────────────────────

  Widget _appliesTo() {
    final methods = _draft.methods;
    final summary =
        '${methods == null || methods.isEmpty ? 'Any' : methods.join('/')}  '
        '${_draft.urlPattern.isEmpty ? 'every request' : _draft.urlPattern}';

    return _Disclosure(
      title: 'Applies to',
      summary: _appliesOpen ? null : summary,
      open: _appliesOpen,
      onToggle: () => setState(() => _appliesOpen = !_appliesOpen),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Spelled out because "applies to" is not self-evident, and a rule
          // that matches more than you meant is this feature's quiet failure.
          const Text(
            'Which requests this rule catches. `*` matches anything, and the '
            'pattern is compared against the whole URL.',
            style: TextStyle(fontSize: 11, color: MacOSColors.textMuted),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _patternController,
            autocorrect: false,
            style: const TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              color: MacOSColors.textPrimary,
            ),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'https://api.example.com/v1/users*',
              hintStyle: const TextStyle(
                fontSize: 12,
                color: MacOSColors.textMuted,
              ),
              filled: true,
              fillColor: MacOSColors.backgroundInput,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: MacOSColors.borderDefault),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: MacOSColors.borderDefault),
              ),
            ),
            onChanged: (value) =>
                _draft = _draft.copyWith(urlPattern: value),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final method in _methods)
                _Chip(
                  label: method,
                  selected: method == 'Any'
                      ? (_draft.methods?.isEmpty ?? true)
                      : (_draft.methods?.contains(method) ?? false),
                  onTap: () => _patch(
                    _draft.copyWith(
                      methods: method == 'Any' ? null : [method],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Outcome grid ───────────────────────────────────────────────────────────

  Widget _outcomeGrid() {
    // RN outcomeGrid: gap 6.
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final outcome in _outcomes)
          _OutcomeChip(
            label: outcome.label,
            status: outcome.status,
            selected: _isSelected(outcome),
            onTap: () => _selectOutcome(outcome),
          ),
        _OutcomeChip(
          label: _isCustomStatus ? '${_draft.status}' : 'Custom',
          selected: _isCustomStatus,
          muted: !_isCustomStatus,
          onTap: () => _promptNumber(
            title: 'Custom status code',
            hint: '$statusMin–$statusMax',
            initial: _draft.status,
            min: statusMin,
            max: statusMax,
            onSubmit: (value) => _patch(
              _draft.copyWith(
                kind: OverrideRuleKind.respond,
                status: value,
                statusText: null,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Response body ──────────────────────────────────────────────────────────

  Widget _responseBody() {
    final body = _draft.body ?? '';
    final summary = body.trim().isEmpty
        ? 'Empty'
        : '${body.split('\n').length} line'
              '${body.split('\n').length == 1 ? '' : 's'}';

    return _Disclosure(
      title: 'Response body',
      summary: _bodyOpen ? null : summary,
      open: _bodyOpen,
      onToggle: () => setState(() => _bodyOpen = !_bodyOpen),
      child: _rawController != null ? _rawEditor() : _treeEditor(),
    );
  }

  Widget _treeEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_bodyIsJson)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: SingleChildScrollView(
              // The scope is the whole document plus one way to replace it;
              // every leaf edit rebuilds the root and lands here.
              child: ResponseEditorScope(
                root: _bodyTree,
                onChange: _commitTree,
                child: BuoyExplorer(
                  label: 'root',
                  value: _bodyTree,
                  editable: true,
                  defaultExpanded: const ['root'],
                ),
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              (_draft.body ?? '').trim().isEmpty
                  ? 'No body yet.'
                  : "This body isn't JSON, so there's no tree to show.",
              style: const TextStyle(
                fontSize: 11,
                color: MacOSColors.textMuted,
              ),
            ),
          ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TouchableOpacity(
            activeOpacity: 0.2,
            onTap: () => setState(() {
              _rawController = TextEditingController();
            }),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'Edit all',
                // RN textButtonLabel: 11 / w600 / info.
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: MacOSColors.info,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _rawEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _rawController,
          maxLines: 8,
          autocorrect: false,
          style: const TextStyle(
            fontSize: 12,
            fontFamily: 'monospace',
            color: MacOSColors.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: 'Paste a new body…',
            hintStyle: const TextStyle(
              fontSize: 12,
              color: MacOSColors.textMuted,
            ),
            filled: true,
            fillColor: MacOSColors.backgroundInput,
            contentPadding: const EdgeInsets.all(10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: MacOSColors.borderDefault),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TouchableOpacity(
              activeOpacity: 0.2,
              onTap: () => setState(() {
                _rawController?.dispose();
                _rawController = null;
              }),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    fontSize: 12,
                    color: MacOSColors.textSecondary,
                  ),
                ),
              ),
            ),
            TouchableOpacity(
              activeOpacity: 0.2,
              onTap: () {
                final next = _rawController?.text ?? '';
                setState(() {
                  // Pretty-print when it parses, so the tree view can take over
                  // from here; keep it verbatim when it doesn't.
                  try {
                    _draft = _draft.copyWith(
                      body: const JsonEncoder.withIndent(
                        '  ',
                      ).convert(jsonDecode(next)),
                    );
                  } catch (_) {
                    _draft = _draft.copyWith(body: next);
                  }
                  _rawController?.dispose();
                  _rawController = null;
                  _decodeBody();
                });
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Text(
                  'Apply',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: MacOSColors.info,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Delay / Fires ──────────────────────────────────────────────────────────

  Widget _delayRow() {
    final delay = _draft.delayMs ?? 0;
    final isPreset = _delayPresets.contains(delay);
    return _LabelledRow(
      label: 'DELAY',
      children: [
        for (final preset in _delayPresets)
          _Chip(
            label: preset == 0
                ? 'None'
                : (preset % 1000 == 0
                      ? '${preset ~/ 1000}s'
                      : '${preset / 1000}s'),
            selected: delay == preset,
            onTap: () => _patch(_draft.copyWith(delayMs: preset)),
          ),
        _Chip(
          label: isPreset ? 'Custom' : '${delay / 1000}s',
          selected: !isPreset,
          onTap: () => _promptNumber(
            title: 'Custom delay in seconds',
            hint: 'seconds',
            initial: delay ~/ 1000,
            min: 0,
            max: 300,
            onSubmit: (value) =>
                _patch(_draft.copyWith(delayMs: value * 1000)),
          ),
        ),
      ],
    );
  }

  Widget _firesRow() {
    final times = _draft.times;
    final alternate = _draft.alternate;
    final isCustom = !alternate && times != null && times != 1;

    return _LabelledRow(
      label: 'FIRES',
      // Named for the confusion it removes: `times` and `alternate` are
      // unrelated fields that both answer "how often", so they live in one row.
      hint:
          "A limited rule switches itself off once it's used up. Every other "
          'alternates forever — the first request through, the next overridden.',
      children: [
        _Chip(
          label: 'Always',
          selected: times == null && !alternate,
          onTap: () =>
              _patch(_draft.copyWith(times: null, alternate: false)),
        ),
        _Chip(
          label: 'Once',
          selected: times == 1 && !alternate,
          onTap: () => _patch(_draft.copyWith(times: 1, alternate: false)),
        ),
        _Chip(
          label: 'Every other',
          selected: alternate,
          onTap: () => _patch(_draft.copyWith(times: null, alternate: true)),
        ),
        _Chip(
          label: isCustom ? '$times×' : 'Custom',
          selected: isCustom,
          onTap: () => _promptNumber(
            title: 'Custom number of times',
            hint: 'times',
            initial: times,
            min: 1,
            max: 999,
            onSubmit: (value) =>
                _patch(_draft.copyWith(times: value, alternate: false)),
          ),
        ),
      ],
    );
  }

  // ── Footer ─────────────────────────────────────────────────────────────────

  Widget _footer(double bottomInset) {
    final canSave = _draft.urlPattern.trim().isNotEmpty;
    return Container(
      // RN footer: padding 12. The bottom inset is added on top because the
      // home indicator eats a fixed-height footer otherwise; the floor keeps
      // the buttons off the very edge on devices with no inset.
      padding: EdgeInsets.fromLTRB(
        12,
        12,
        12,
        12 + (bottomInset > 0 ? bottomInset : 0),
      ),
      decoration: const BoxDecoration(
        color: MacOSColors.backgroundBase,
        border: Border(top: BorderSide(color: MacOSColors.borderDefault)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _FooterButton(
              label: 'Cancel',
              onTap: widget.onCancel,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _FooterButton(
              label: widget.saveLabel,
              primary: true,
              disabled: !canSave,
              onTap: () => widget.onSave(
                _draft.copyWith(urlPattern: _draft.urlPattern.trim()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Small building blocks ────────────────────────────────────────────────────

class _Disclosure extends StatelessWidget {
  const _Disclosure({
    required this.title,
    required this.open,
    required this.onToggle,
    required this.child,
    this.summary,
  });

  final String title;
  final String? summary;
  final bool open;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      // RN: radius 6 / bg background.card / border.default.
      decoration: BoxDecoration(
        color: MacOSColors.backgroundCard,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: MacOSColors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            label: title,
            child: TouchableOpacity(
              activeOpacity: 0.8,
              onTap: onToggle,
              child: Padding(
                // RN: padH 10 / padV 10, gap 6.
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    BuoyGlyph(
                      open ? BuoyIcons.chevronDown : BuoyIcons.chevronRight,
                      size: 12,
                      color: MacOSColors.textMuted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      title,
                      // RN: fontSize 12 / weight 600.
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: MacOSColors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    if (summary != null)
                      Flexible(
                        child: Text(
                          summary!,
                          textAlign: TextAlign.right,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: MacOSColors.textMuted,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (open)
            Padding(
              // RN disclosureBody: padH 10 / padBottom 10.
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: child,
            ),
        ],
      ),
    );
  }
}

class _LabelledRow extends StatelessWidget {
  const _LabelledRow({
    required this.label,
    required this.children,
    this.hint,
  });

  final String label;
  final String? hint;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          // RN subLabel: 10 / w700 / letterSpacing 0.6 / text.muted.
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: MacOSColors.textMuted,
          ),
        ),
        if (hint != null) ...[
          // RN `field` uses a uniform gap: 8 between label, hint and chips.
          const SizedBox(height: 8),
          Text(
            hint!,
            // RN subHint: 10 / lineHeight 14.
            style: const TextStyle(
              fontSize: 10,
              height: 14 / 10,
              color: MacOSColors.textMuted,
            ),
          ),
        ],
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: children),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: TouchableOpacity(
        activeOpacity: 0.2,
        onTap: onTap,
        // RN: padH 10 / padV 6 / radius 5 / bg background.base, active info@1F.
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? MacOSColors.info.hexAlpha(0x1F)
                : MacOSColors.backgroundBase,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: selected ? MacOSColors.info : MacOSColors.borderDefault,
            ),
          ),
          child: Text(
            label,
            // RN: fontSize 11 / weight 600 / text.secondary.
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: selected ? MacOSColors.info : MacOSColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// The outcome tiles. Deliberately NEUTRAL rather than tinted by meaning: in
/// this theme colour carries data, so four red chips would shout louder than
/// the real status badge they're describing.
class _OutcomeChip extends StatelessWidget {
  const _OutcomeChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.status,
    this.muted = false,
  });

  final String label;
  final int? status;
  final bool selected;
  final bool muted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: status == null ? label : '$label $status',
      child: TouchableOpacity(
        activeOpacity: 0.2,
        onTap: onTap,
        // RN: padH 10 / padV 9 / radius 6 / bg background.card / border
        // border.default. Active swaps to the accent at 1F alpha.
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? MacOSColors.info.hexAlpha(0x1F)
                : MacOSColors.backgroundCard,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected ? MacOSColors.info : MacOSColors.borderDefault,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                // RN: fontSize 12 / weight 600 / text.primary.
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? MacOSColors.info
                      : (muted
                            ? MacOSColors.textMuted
                            : MacOSColors.textPrimary),
                ),
              ),
              if (status != null) ...[
                const SizedBox(width: 6),
                Text(
                  '$status',
                  // RN: fontSize 10 / weight 700 / text.muted, accent when on.
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: selected ? MacOSColors.info : MacOSColors.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FooterButton extends StatelessWidget {
  const _FooterButton({
    required this.label,
    required this.onTap,
    this.primary = false,
    this.disabled = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool primary;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    // RN footerButton: padV 11 / radius 6. Cancel = background.card +
    // text.secondary at w600; Save = info@22 + info at w700.
    final button = Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: primary
            ? MacOSColors.info.hexAlpha(0x22)
            : MacOSColors.backgroundCard,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: primary ? MacOSColors.info : MacOSColors.borderDefault,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: primary ? FontWeight.w700 : FontWeight.w600,
          color: primary ? MacOSColors.info : MacOSColors.textSecondary,
        ),
      ),
    );
    if (disabled) return Opacity(opacity: 0.4, child: button);
    return Semantics(
      button: true,
      label: label,
      child: TouchableOpacity(
        activeOpacity: 0.7,
        onTap: onTap,
        child: button,
      ),
    );
  }
}

/// Number entry, pinned to the top of the screen so the keyboard can't cover
/// the field the way a centred dialog would.
class _NumberPrompt extends StatelessWidget {
  const _NumberPrompt({
    required this.title,
    required this.hint,
    required this.controller,
    required this.min,
    required this.max,
  });

  final String title;
  final String hint;
  final TextEditingController controller;
  final int min;
  final int max;

  @override
  Widget build(BuildContext context) {
    void submit() {
      final parsed = int.tryParse(controller.text.trim());
      if (parsed == null) return;
      Navigator.of(context).pop(parsed.clamp(min, max));
    }

    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
      backgroundColor: MacOSColors.backgroundCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: MacOSColors.borderInput),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: MacOSColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onSubmitted: (_) => submit(),
              style: const TextStyle(
                fontSize: 14,
                color: MacOSColors.textPrimary,
              ),
              decoration: InputDecoration(
                isDense: true,
                hintText: hint,
                hintStyle: const TextStyle(color: MacOSColors.textMuted),
                filled: true,
                fillColor: MacOSColors.backgroundInput,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(
                    color: MacOSColors.borderDefault,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _FooterButton(
                    label: 'Cancel',
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _FooterButton(
                    label: 'Set',
                    primary: true,
                    onTap: submit,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
