/// Ports packages/images/src/components/ImagesListFooter.tsx — the list
/// screen's action bar: mass simulations applied to EVERY mounted image at once
/// (error / loading / blank), mass hard-reload, flash everything, restore all,
/// plus the global network-simulation modes (Normal / Offline / Cold).
library;

import 'package:buoy_core/buoy_core.dart' show TouchableOpacity;
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';

import '../images_actions.dart';

class ImagesListFooter extends StatefulWidget {
  const ImagesListFooter({super.key});

  @override
  State<ImagesListFooter> createState() => _ImagesListFooterState();
}

class _ImagesListFooterState extends State<ImagesListFooter> {
  String? _message;
  void Function()? _unsubscribe;

  @override
  void initState() {
    super.initState();
    _unsubscribe = ImagesActions.instance.subscribeActions(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _unsubscribe?.call();
    super.dispose();
  }

  void _massOverride(OverrideSource source, String label) {
    final count = ImagesActions.instance.setOverrideForAllMounted(source, label);
    setState(() {
      _message = count > 0
          ? '$label on $count image${count == 1 ? '' : 's'} — Restore all to undo'
          : 'No mounted images';
    });
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.viewPaddingOf(context);
    final network = ImagesActions.instance.networkMode;

    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 12, 10 + insets.bottom),
      decoration: const BoxDecoration(
        color: MacOSColors.backgroundBase,
        border: Border(top: BorderSide(color: MacOSColors.borderDefault)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _message ?? 'MASS ACTIONS — every image on screen',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _message != null ? MacOSColors.info : MacOSColors.textMuted,
              fontSize: _message != null ? 10 : 9,
              fontWeight: _message != null ? FontWeight.w400 : FontWeight.w700,
              letterSpacing: _message != null ? 0 : 0.8,
              fontFamily: _message != null ? 'monospace' : null,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _massButton('Error',
                  () => _massOverride(const OverrideSource(OverrideKind.error), 'Forced error')),
              const SizedBox(width: 6),
              _massButton('Loading',
                  () => _massOverride(const OverrideSource(OverrideKind.hang), 'Forced loading')),
              const SizedBox(width: 6),
              _massButton('Blank',
                  () => _massOverride(const OverrideSource(OverrideKind.blank), 'Blanked')),
              const SizedBox(width: 6),
              _massButton('Reload', () {
                setState(() => _message = '…');
                final r = ImagesActions.instance.hardReloadAllMounted();
                setState(() => _message = r.message);
              }),
              const SizedBox(width: 6),
              _massButton('Find', () {
                final count = ImagesActions.instance.flashAllMounted();
                setState(() =>
                    _message = 'Flashing $count image${count == 1 ? '' : 's'} (2.5s)');
              }),
              const SizedBox(width: 6),
              _massButton('Restore', () {
                final count = ImagesActions.instance.clearAllOverrides();
                setState(() => _message = count > 0
                    ? 'Restored $count image${count == 1 ? '' : 's'}'
                    : 'No overrides active');
              }, accent: true),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Padding(
                padding: EdgeInsets.only(right: 2),
                child: Text(
                  'NET',
                  style: TextStyle(
                    color: MacOSColors.textMuted,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              for (final mode in NetworkMode.values) ...[
                const SizedBox(width: 6),
                _netButton(mode, network == mode),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _massButton(String label, VoidCallback onTap, {bool accent = false}) {
    return Expanded(
      child: TouchableOpacity(
        activeOpacity: 0.7,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: MacOSColors.backgroundCard,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: MacOSColors.borderDefault, width: 0.5),
          ),
          child: Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
              color: accent ? MacOSColors.warning : MacOSColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _netButton(NetworkMode mode, bool active) {
    final label = switch (mode) {
      NetworkMode.normal => 'Normal',
      NetworkMode.offline => 'Offline',
      NetworkMode.cold => 'Cold',
    };
    return Expanded(
      child: TouchableOpacity(
        activeOpacity: 0.7,
        onTap: () {
          ImagesActions.instance.setNetworkMode(mode);
          setState(() {
            _message = switch (mode) {
              NetworkMode.normal =>
                'Network simulation off — tap RELOAD to load normally again',
              NetworkMode.offline =>
                'Offline: network images FAIL — tap RELOAD to apply on-screen',
              NetworkMode.cold =>
                'Cold (bypass caches) — tap RELOAD: everything refetches',
            };
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active
                ? MacOSColors.infoBackground
                : MacOSColors.backgroundCard,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: active ? MacOSColors.info : MacOSColors.borderDefault,
              width: active ? 1 : 0.5,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
              color: active ? MacOSColors.info : MacOSColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
