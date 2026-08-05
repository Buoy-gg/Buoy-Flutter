/// Ports packages/network/src/network/components/NetworkOverrideHeaderButton.tsx
/// — the Override action in the request-detail header.
library;

import 'package:buoy_core/buoy_core.dart';
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';

import '../../network_capture.dart';
import '../../overrides/match_rule.dart';
import '../../overrides/override_rule.dart';
import '../../overrides/override_rules_store.dart';
import '../../overrides/presets.dart';
import '../../overrides/resolve_override.dart';

/// A labelled word rather than an icon: every other control in this header is a
/// glyph, and glyphs are fine for things you already know. This is the least
/// familiar action in the tool, and "Override" spelled out is the entire
/// explanation.
///
/// It lights up while a rule covers the request you're looking at — the same
/// warning tint the OVERRIDDEN strip and the toolbar flask use, because "you
/// are not seeing the truth" is one idea and should look like one.
///
/// Tapping it goes straight to the Overrides screen with the rule open: a new
/// one prefilled from this request, or the existing one if something already
/// covers it. One destination, so there's never a question of where the thing
/// you just made went.
class NetworkOverrideHeaderButton extends StatefulWidget {
  const NetworkOverrideHeaderButton({
    super.key,
    required this.event,
    required this.onOpen,
  });

  final NetworkCaptureEvent event;
  final ValueChanged<OverrideRule> onOpen;

  @override
  State<NetworkOverrideHeaderButton> createState() =>
      _NetworkOverrideHeaderButtonState();
}

class _NetworkOverrideHeaderButtonState
    extends State<NetworkOverrideHeaderButton> {
  void Function()? _unsubscribe;

  @override
  void initState() {
    super.initState();
    // Self-subscribing so the detail header doesn't rebuild with the rule list.
    _unsubscribe = OverrideRulesStore.instance.subscribe(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _unsubscribe?.call();
    super.dispose();
  }

  OverrideRule? get _existing {
    for (final rule in OverrideRulesStore.instance.rules) {
      if (!rule.enabled || isSpent(rule)) continue;
      if (ruleMatches(rule, widget.event.url, widget.event.method)) return rule;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final existing = _existing;
    final active = existing != null;

    return Semantics(
      button: true,
      label: active
          ? 'Edit the override on this request'
          : 'Override this request',
      child: TouchableOpacity(
        activeOpacity: 0.7,
        // Editing what's already there, rather than stacking a second rule the
        // first would shadow — first enabled match wins.
        onTap: () =>
            widget.onOpen(existing ?? draftFromEvent(widget.event)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: active
                ? MacOSColors.warningBackground
                : MacOSColors.backgroundInput,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: active
                  ? MacOSColors.warning.hexAlpha(0x77)
                  : MacOSColors.borderInput,
            ),
          ),
          child: Text(
            'Override',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: active ? MacOSColors.warning : MacOSColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
