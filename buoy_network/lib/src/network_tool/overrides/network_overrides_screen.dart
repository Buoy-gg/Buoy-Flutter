/// Ports packages/network/src/network/components/NetworkOverridesScreen.tsx —
/// the rule list, its master switch, and the route into the editor.
library;

import 'package:buoy_core/buoy_core.dart';
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';

import '../../overrides/override_rule.dart';
import '../../overrides/override_rules_store.dart';
import '../../overrides/presets.dart';
import '../../overrides/resolve_override.dart';
import 'network_override_editor.dart';

/// Plain-language names for the statuses the editor offers, so a row never
/// reads as a bare number.
const Map<int, String> _statusNames = {
  200: 'Success',
  400: 'Bad request',
  401: 'Unauthorized',
  403: 'Forbidden',
  404: 'Not found',
  429: 'Rate limited',
  500: 'Server error',
  503: 'Unavailable',
};

class NetworkOverridesScreen extends StatefulWidget {
  const NetworkOverridesScreen({
    super.key,
    this.pendingDraft,
    this.onPendingConsumed,
    this.applySafeAreaInset = true,
  });

  /// A rule handed over from the request-detail Override button — either a new
  /// draft prefilled from that request, or the existing rule that covers it.
  final OverrideRule? pendingDraft;
  final VoidCallback? onPendingConsumed;

  /// Only a bottom sheet sits on the home indicator; a floating window does
  /// not — same call `_DetailStepper` makes.
  final bool applySafeAreaInset;

  @override
  State<NetworkOverridesScreen> createState() => NetworkOverridesScreenState();
}

class NetworkOverridesScreenState extends State<NetworkOverridesScreen> {
  void Function()? _unsubscribe;
  OverrideRule? _editing;

  /// Whether [_editing] is an existing rule (Save) or a new one (Add).
  bool _editingExisting = false;

  @override
  void initState() {
    super.initState();
    _unsubscribe = OverrideRulesStore.instance.subscribe(() {
      if (mounted) setState(() {});
    });
    // Reaching this screen proves the app renders, so the launch-safety streak
    // has nothing left to guard against.
    OverrideRulesStore.instance.noteHealthyLaunch();
    _consumePending();
  }

  @override
  void didUpdateWidget(NetworkOverridesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pendingDraft != oldWidget.pendingDraft) _consumePending();
  }

  @override
  void dispose() {
    _unsubscribe?.call();
    super.dispose();
  }

  void _consumePending() {
    final pending = widget.pendingDraft;
    if (pending == null) return;
    final exists = OverrideRulesStore.instance.rules.any(
      (rule) => rule.id == pending.id,
    );
    setState(() {
      _editing = pending;
      _editingExisting = exists;
    });
    widget.onPendingConsumed?.call();
  }

  /// True when this screen is showing the editor — the modal header asks, so it
  /// can offer Back rather than the list's own chrome.
  bool get isEditing => _editing != null;

  void closeEditor() => setState(() => _editing = null);

  void _openRule(OverrideRule rule) => setState(() {
    _editing = rule;
    _editingExisting = true;
  });

  void _openNew() => setState(() {
    _editing = blankDraft();
    _editingExisting = false;
  });

  void _save(OverrideRule draft) {
    if (draft.urlPattern.trim().isEmpty) return;
    OverrideRulesStore.instance.upsertRule(draft);
    if (draft.enabled) {
      // Arm the master switch. Deliberately creating a rule and having it sit
      // inert because overrides happen to be paused is the silent failure this
      // feature can least afford.
      OverrideRulesStore.instance.setEnabled(true);
    }
    setState(() => _editing = null);
  }

  @override
  Widget build(BuildContext context) {
    final store = OverrideRulesStore.instance;

    if (_editing != null) {
      return NetworkOverrideEditor(
        // Keyed by rule id so switching rules rebuilds the editor's own state
        // (the pattern controller, the decoded body) instead of carrying the
        // previous rule's into the next one.
        key: ValueKey(_editing!.id),
        applySafeAreaInset: widget.applySafeAreaInset,
        draft: _editing!,
        saveLabel: _editingExisting ? 'Save' : 'Add',
        onSave: _save,
        onCancel: closeEditor,
      );
    }

    final rules = store.rules;
    final activeCount = store.activeCount;
    final bottomInset = widget.applySafeAreaInset
        ? MediaQuery.viewPaddingOf(context).bottom
        : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (rules.isNotEmpty || store.autoPaused) _masterBar(store, activeCount),
        _listHeader(rules.length),
        Expanded(
          child: rules.isEmpty
              ? const EmptyState(
                  icon: BuoyIcons.flaskConical,
                  title: 'Nothing overridden',
                  description:
                      'Open any request and tap Override, or + to write a rule.',
                )
              : ListView.separated(
                  // The last rule would otherwise sit under the home
                  // indicator, where it can be seen but not tapped.
                  padding: EdgeInsets.fromLTRB(12, 0, 12, 16 + bottomInset),
                  itemCount: rules.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) => _RuleRow(
                    rule: rules[index],
                    onTap: () => _openRule(rules[index]),
                    onToggle: () => store.setRuleEnabled(
                      rules[index].id,
                      !rules[index].enabled,
                    ),
                    onRemove: () => store.removeRule(rules[index].id),
                  ),
                ),
        ),
      ],
    );
  }

  /// One bar, not two. RN tried a separate "overrides are on" banner and a
  /// separate master switch; merging them means the state and the way to change
  /// it are the same object.
  Widget _masterBar(OverrideRulesStore store, int activeCount) {
    final on = store.enabled && activeCount > 0;
    final label = store.autoPaused
        ? 'Overrides paused — they were on for $maxUntouchedLaunches launches'
        : on
        ? '$activeCount override${activeCount == 1 ? '' : 's'} ${activeCount == 1 ? 'is' : 'are'} on'
        : 'Overrides are off';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: on || store.autoPaused
            ? MacOSColors.warningBackground
            : MacOSColors.backgroundCard,
        border: const Border(
          bottom: BorderSide(color: MacOSColors.borderDefault),
        ),
      ),
      child: Row(
        children: [
          BuoyGlyph(
            BuoyIcons.alertTriangle,
            size: 14,
            color: on || store.autoPaused
                ? MacOSColors.warning
                : MacOSColors.textMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: on || store.autoPaused
                    ? MacOSColors.warning
                    : MacOSColors.textSecondary,
              ),
            ),
          ),
          TouchableOpacity(
            activeOpacity: 0.7,
            onTap: () => store.setEnabled(!on),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: MacOSColors.backgroundBase,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: MacOSColors.borderDefault),
              ),
              child: Text(
                on
                    ? 'Turn all off'
                    : (store.autoPaused ? 'Turn back on' : 'Turn on'),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: MacOSColors.textPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _listHeader(int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Row(
        children: [
          Text(
            count == 0 ? '' : '$count RULE${count == 1 ? '' : 'S'}',
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: MacOSColors.textMuted,
            ),
          ),
          const Spacer(),
          Semantics(
            button: true,
            label: 'New override rule',
            child: TouchableOpacity(
              activeOpacity: 0.2,
              onTap: _openNew,
              child: Container(
                width: 32,
                height: 32,
                decoration: headerActionButtonDecoration(),
                child: const BuoyGlyph(
                  BuoyIcons.plus,
                  size: 14,
                  color: MacOSColors.info,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A rule, in two lines: what it does, and what it catches.
///
/// Deliberately slim. An earlier RN pass gave each rule a card with a header, a
/// pattern block and a button row; five rules filled the screen and the list
/// stopped being scannable, which is the only job a list has.
class _RuleRow extends StatelessWidget {
  const _RuleRow({
    required this.rule,
    required this.onTap,
    required this.onToggle,
    required this.onRemove,
  });

  final OverrideRule rule;
  final VoidCallback onTap;
  final VoidCallback onToggle;
  final VoidCallback onRemove;

  String get _outcomeLabel {
    switch (rule.kind) {
      case OverrideRuleKind.delay:
        return 'Real response';
      case OverrideRuleKind.fail:
        return rule.failKind == OverrideFailKind.timeout ? 'Timeout' : 'Offline';
      case OverrideRuleKind.respond:
        final status = rule.status ?? 200;
        final name = _statusNames[status];
        return name == null ? '$status' : '$status';
    }
  }

  @override
  Widget build(BuildContext context) {
    final spent = isSpent(rule);
    final live = rule.enabled && !spent;
    final methods = rule.methods;

    final detail = [
      methods == null || methods.isEmpty ? 'Any' : methods.join('/'),
      rule.urlPattern,
    ].join(' ');

    return TouchableOpacity(
      activeOpacity: 0.8,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: MacOSColors.backgroundCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: live
                ? MacOSColors.warning.hexAlpha(0x40)
                : MacOSColors.borderDefault,
          ),
        ),
        child: Row(
          children: [
            Semantics(
              button: true,
              label: live ? 'Turn rule off' : 'Turn rule on',
              child: TouchableOpacity(
                activeOpacity: 0.2,
                onTap: onToggle,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: live
                          ? MacOSColors.warning
                          : MacOSColors.borderInput,
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: live
                            ? MacOSColors.warning
                            : Colors.transparent,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rule.name?.isNotEmpty == true
                        ? '${rule.name} · $_outcomeLabel'
                        : _outcomeLabel,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: live
                          ? MacOSColors.textPrimary
                          : MacOSColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: MacOSColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Hits, not a chevron: the number is the only thing that tells you
            // whether the rule you wrote is actually catching anything.
            Text(
              spent ? 'spent' : '${rule.hits}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: rule.hits > 0 && live
                    ? MacOSColors.warning
                    : MacOSColors.textMuted,
              ),
            ),
            const SizedBox(width: 8),
            Semantics(
              button: true,
              label: 'Delete rule',
              child: TouchableOpacity(
                activeOpacity: 0.2,
                onTap: onRemove,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: BuoyGlyph(
                    BuoyIcons.trash2,
                    size: 14,
                    color: MacOSColors.textMuted,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
