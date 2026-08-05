/// Ports the pin/save controls from
/// packages/network/src/network/components/NetworkHeaderLive.tsx.
library;

import 'package:buoy_core/buoy_core.dart';
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';

import '../../network_capture.dart';
import 'network_saved_store.dart';

/// Rebuilds itself off the saved store so the modal shell never subscribes.
mixin _SavedStoreListener<T extends StatefulWidget> on State<T> {
  void Function()? _unsubscribe;

  @override
  void initState() {
    super.initState();
    _unsubscribe = NetworkSavedStore.instance.subscribe(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _unsubscribe?.call();
    super.dispose();
  }
}

/// The header's bookmark — opens the Saved screen and carries its count.
class NetworkSavedButton extends StatefulWidget {
  const NetworkSavedButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  State<NetworkSavedButton> createState() => _NetworkSavedButtonState();
}

class _NetworkSavedButtonState extends State<NetworkSavedButton>
    with _SavedStoreListener {
  @override
  Widget build(BuildContext context) {
    final count = NetworkSavedStore.instance.state.savedRecords.length;

    return Semantics(
      button: true,
      label: 'Saved requests',
      child: TouchableOpacity(
        activeOpacity: 0.2,
        onTap: widget.onTap,
        child: SizedBox(
          width: 32,
          height: 32,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: headerActionButtonDecoration(),
                child: BuoyGlyph(
                  BuoyIcons.bookmark,
                  size: 14,
                  color: count > 0
                      ? MacOSColors.debug
                      : MacOSColors.textMuted,
                ),
              ),
              if (count > 0)
                Positioned(
                  top: 1,
                  right: 1,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 12),
                    height: 12,
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: MacOSColors.debug,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    // Already in the button's own label; without this a screen
                    // reader reads "Saved requests, 3".
                    child: ExcludeSemantics(
                      child: Text(
                        count > 99 ? '99+' : '$count',
                        style: const TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                          height: 1,
                          color: MacOSColors.backgroundBase,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pin + Save toggles for the request-detail header.
///
/// A self-subscribing leaf for the same reason RN's is: the modal root stays
/// free of subscriptions. The event is resolved at PRESS time rather than held
/// as a prop — the live store has the fresh copy while the request is in
/// flight, and the saved store is the only copy once it has been cleared.
class NetworkDetailPinActions extends StatefulWidget {
  const NetworkDetailPinActions({super.key, required this.eventId});

  final String eventId;

  @override
  State<NetworkDetailPinActions> createState() =>
      _NetworkDetailPinActionsState();
}

class _NetworkDetailPinActionsState extends State<NetworkDetailPinActions>
    with _SavedStoreListener {
  NetworkCaptureEvent? _resolveEvent() =>
      NetworkEventStore.instance.byId(widget.eventId) ??
      NetworkSavedStore.instance.getEventById(widget.eventId);

  @override
  Widget build(BuildContext context) {
    final store = NetworkSavedStore.instance;
    final flags = flagsForEventId(store.state, widget.eventId);
    final atPinCap =
        !flags.pinned && store.state.pinnedEvents.length >= maxPinned;
    final atSavedCap =
        !flags.saved && store.state.savedRecords.length >= maxSaved;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Toggle(
          icon: BuoyIcons.pin,
          active: flags.pinned,
          disabled: atPinCap,
          activeColor: MacOSColors.info,
          label: flags.pinned ? 'Unpin request' : 'Pin request',
          hint: atPinCap ? 'Pin limit reached ($maxPinned)' : null,
          onTap: () {
            final event = _resolveEvent();
            if (event != null) store.togglePin(event);
          },
        ),
        const SizedBox(width: 6),
        _Toggle(
          icon: BuoyIcons.bookmark,
          active: flags.saved,
          disabled: atSavedCap,
          activeColor: MacOSColors.debug,
          label: flags.saved ? 'Remove from saved' : 'Save request',
          hint: atSavedCap ? 'Saved limit reached ($maxSaved)' : null,
          onTap: () {
            final event = _resolveEvent();
            if (event != null) store.toggleSave(event);
          },
        ),
      ],
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.icon,
    required this.active,
    required this.disabled,
    required this.activeColor,
    required this.label,
    required this.onTap,
    this.hint,
  });

  final LucideIcon icon;
  final bool active;
  final bool disabled;
  final Color activeColor;
  final String label;
  final String? hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final button = Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: active
            ? activeColor.hexAlpha(0x1F)
            : MacOSColors.backgroundHover,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: active ? activeColor : MacOSColors.borderDefault,
        ),
      ),
      child: BuoyGlyph(
        icon,
        size: 14,
        color: active
            ? activeColor
            : (disabled ? MacOSColors.textMuted : MacOSColors.textSecondary),
      ),
    );

    if (disabled) {
      return Semantics(
        button: true,
        label: label,
        hint: hint,
        child: Opacity(opacity: 0.55, child: button),
      );
    }
    return Semantics(
      button: true,
      label: label,
      child: TouchableOpacity(
        activeOpacity: 0.2,
        onTap: onTap,
        child: button,
      ),
    );
  }
}
