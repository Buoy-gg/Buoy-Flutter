import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../storage.dart';
import '../../sync_client.dart';
import '../../tool.dart';
import '../buoy_theme.dart';
import '../modal/js_modal.dart';
import '../modal/modal_settings.dart';
import '../touchable_opacity.dart';

/// The dev-tools settings modal — port of the RN `DevToolsSettingsModal`:
/// a [JsModal] (bottom-sheet mode, 1/3 screen height, mode/size persisted
/// under `@react_buoy_settings`) with the FLOATING / SETTINGS / PRO tabs as
/// its header.
///
/// Deviations from RN: the global settings cards (shared modal size,
/// expandable window controls) and the dev-only export-config card aren't
/// ported; PRO is display-only (license flow not wired).
class SettingsSheet extends StatefulWidget {
  const SettingsSheet({
    super.key,
    required this.storage,
    required this.tools,
    required this.onClose,
  });

  final BuoyStorage storage;
  final List<BuoyTool> tools;

  /// Requested by the modal chrome (red dot / swipe-down).
  final VoidCallback onClose;

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  static const _tabs = ['floating', 'settings', 'pro'];

  String _tab = 'floating';
  BuoyDevToolsSettings? _settings;

  bool _storageExpanded = false;
  List<String>? _savedKeys;
  bool _clearing = false;
  bool _clearSuccess = false;
  final Set<String> _expandedSettings = {};

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final tab = await widget.storage.loadSettingsActiveTab();
    final settings = await widget.storage.loadDevToolsSettings();
    if (!mounted) return;
    setState(() {
      if (tab != null && _tabs.contains(tab)) _tab = tab;
      _settings = settings;
    });
  }

  void _selectTab(String tab) {
    setState(() => _tab = tab);
    widget.storage.saveSettingsActiveTab(tab);
  }

  void _toggleFloatingTool(String id) {
    final settings = _settings;
    if (settings == null) return;
    setState(() {
      settings.floatingTools[id] = !(settings.floatingTools[id] ?? false);
    });
    widget.storage.saveDevToolsSettings(settings);
  }

  Future<void> _toggleStorageExpanded() async {
    setState(() => _storageExpanded = !_storageExpanded);
    if (_storageExpanded && _savedKeys == null) {
      final keys = await widget.storage.listBuoyKeys();
      if (mounted) setState(() => _savedKeys = keys);
    }
  }

  Future<void> _clearStorage() async {
    if (_clearing) return;
    setState(() {
      _clearing = true;
      _clearSuccess = false;
    });
    await widget.storage.clearBuoyKeys();
    final settings = BuoyDevToolsSettings();
    final keys = await widget.storage.listBuoyKeys();
    if (!mounted) return;
    setState(() {
      _clearing = false;
      _clearSuccess = true;
      _settings = settings;
      _savedKeys = keys;
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _clearSuccess = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final topInset = MediaQuery.viewPaddingOf(context).top;
    // RN: modalHeight = floor(screenHeight * 0.33), modalWidth used for the
    // floating-mode initial position.
    final modalWidth = math.min(screen.width - 32, 400.0);
    return JsModal(
      storage: widget.storage,
      persistenceKey: '@react_buoy_settings',
      initialMode: JsModalMode.bottomSheet,
      initialHeight: (screen.height * 0.33).floorToDouble(),
      initialFloatingPosition: Offset(
        (screen.width - modalWidth) / 2,
        topInset + 20,
      ),
      onClose: widget.onClose,
      headerContent: _tabSelector(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: switch (_tab) {
          'settings' => _settingsTab(),
          'pro' => _proTab(),
          _ => _floatingTab(),
        },
      ),
    );
  }

  /// RN TabSelector: pill container (hover bg, 1px border, radius 6,
  /// padding 2), flex buttons, active = teal-20 bg + teal border.
  Widget _tabSelector() {
    return Padding(
      // Top spacing clears the drag indicator + window controls so the
      // header lands at RN's 56px minHeight.
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      // RN TabSelector: fixed 28px height, hover bg, radius 6, padding 2;
      // buttons flex with 8/3 padding; 12px w600 text, NOT monospace.
      child: Container(
        height: 28,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: BuoyTheme.hover,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: BuoyTheme.border),
        ),
        child: Row(
          children: [
            for (final tab in _tabs)
              Expanded(
                child: TouchableOpacity(
                  onTap: () => _selectTab(tab),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: _tab == tab
                          ? BuoyTheme.teal.withValues(alpha: 0.13)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: _tab == tab
                            ? BuoyTheme.teal
                            : Colors.transparent,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      tab.toUpperCase(),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                        color: _tab == tab ? BuoyTheme.teal : BuoyTheme.muted,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── FLOATING tab ──────────────────────────────────────────────────────

  Widget _floatingTab() {
    final settings = _settings;
    if (settings == null) return const SizedBox.shrink();
    return Column(
      children: [
        for (final tool in widget.tools)
          _ToolCard(
            label: tool.name.toUpperCase(),
            description: tool.description ?? '',
            icon: Icon(tool.icon, size: 16, color: tool.color),
            value: settings.floatingTools[tool.id] ?? false,
            onToggle: () => _toggleFloatingTool(tool.id),
          ),
        _ToolCard(
          label: 'ENV BADGE',
          description: 'Environment badge.',
          icon: const Icon(Icons.public, size: 16, color: BuoyTheme.teal),
          value: settings.floatingTools['environment'] ?? false,
          onToggle: () => _toggleFloatingTool('environment'),
        ),
      ],
    );
  }

  void _toggleGlobalSetting(String key) {
    final settings = _settings;
    if (settings == null) return;
    setState(() {
      if (key == 'enableSharedModalDimensions') {
        settings.enableSharedModalDimensions =
            !settings.enableSharedModalDimensions;
      } else if (key == 'expandableWindowControls') {
        settings.expandableWindowControls = !settings.expandableWindowControls;
      }
    });
    widget.storage.saveDevToolsSettings(settings);
    applyGlobalModalSettings(settings);
  }

  void _toggleSettingExpanded(String key) {
    setState(() {
      if (!_expandedSettings.remove(key)) _expandedSettings.add(key);
    });
  }

  // ── SETTINGS tab ──────────────────────────────────────────────────────

  Widget _settingsTab() {
    final settings = _settings;
    return Column(
      children: [
        _storageCard(),
        _desktopSyncCard(),
        if (settings != null) ...[
          _GlobalSettingCard(
            label: 'SHARED MODAL SIZE',
            category: 'MODAL',
            shortDescription: 'Sync dimensions across all tools',
            fullDescription:
                'When enabled, all tool modals will share the same size and '
                'position. Resizing one modal will affect all others. When '
                'disabled, each tool remembers its own size and position '
                'independently.',
            recommendation:
                "Keep OFF for the best experience. This allows you to "
                "customize each tool's modal size separately. Enable only if "
                'you prefer uniform modal sizes across all dev tools.',
            value: settings.enableSharedModalDimensions,
            expanded: _expandedSettings.contains('enableSharedModalDimensions'),
            onToggle: () => _toggleGlobalSetting('enableSharedModalDimensions'),
            onExpandToggle: () =>
                _toggleSettingExpanded('enableSharedModalDimensions'),
          ),
          _GlobalSettingCard(
            label: 'EXPAND CONTROLS',
            category: 'MODAL',
            shortDescription: 'iPad-style expandable window buttons',
            fullDescription:
                'When enabled, the window control buttons (minimize, toggle '
                'mode, close) start as small dots and expand into larger, '
                'easy-to-tap buttons when pressed — similar to iPad window '
                'controls. When disabled, buttons are directly tappable at '
                'their small size.',
            recommendation:
                'Keep ON for touch devices where the small buttons are hard '
                'to press. Turn OFF if you prefer direct single-tap access '
                '(e.g. when using a mouse or simulator).',
            value: settings.expandableWindowControls,
            expanded: _expandedSettings.contains('expandableWindowControls'),
            onToggle: () => _toggleGlobalSetting('expandableWindowControls'),
            onExpandToggle: () =>
                _toggleSettingExpanded('expandableWindowControls'),
          ),
        ],
      ],
    );
  }

  Widget _storageCard() {
    final keys = _savedKeys;
    return _StatusCard(
      icon: Icons.storage,
      accent: BuoyTheme.teal,
      label: 'STORAGE TYPE',
      badge: 'SHARED PREFERENCES',
      badgeIcon: Icons.check_circle,
      description:
          'Settings persist via the platform preferences store and survive '
          'app restarts.',
      onHeaderTap: _toggleStorageExpanded,
      expanded: _storageExpanded,
      expandedChild: _storageExpanded
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.description,
                      size: 14,
                      color: BuoyTheme.teal,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'SAVED SETTINGS',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                          color: BuoyTheme.teal,
                        ),
                      ),
                    ),
                    Text(
                      keys == null ? '...' : '${keys.length} keys',
                      style: const TextStyle(
                        fontSize: 10,
                        color: BuoyTheme.muted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (keys == null)
                  const Text(
                    'Loading...',
                    style: TextStyle(fontSize: 11, color: BuoyTheme.muted),
                  )
                else if (keys.isEmpty)
                  const Text(
                    'No settings saved yet',
                    style: TextStyle(
                      fontSize: 11,
                      color: BuoyTheme.muted,
                      fontStyle: FontStyle.italic,
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 150),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final key in keys)
                          Container(
                            margin: const EdgeInsets.only(bottom: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: BuoyTheme.hover,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: BuoyTheme.border.withValues(alpha: 0.5),
                              ),
                            ),
                            child: Text(
                              key.replaceFirst('@react_buoy_', ''),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                fontFamily: 'monospace',
                                color: BuoyTheme.textSecondary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            )
          : null,
      footer: TouchableOpacity(
        activeOpacity: 0.7,
        onTap: _clearStorage,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: (_clearSuccess ? BuoyTheme.teal : BuoyTheme.error)
                .withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: (_clearSuccess ? BuoyTheme.teal : BuoyTheme.error)
                  .withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 8,
            children: [
              Icon(
                _clearSuccess ? Icons.check_circle : Icons.delete_outline,
                size: 14,
                color: _clearSuccess
                    ? BuoyTheme.teal
                    : (_clearing ? BuoyTheme.muted : BuoyTheme.error),
              ),
              Text(
                _clearSuccess
                    ? 'CLEARED'
                    : _clearing
                    ? 'CLEARING...'
                    : 'CLEAR ALL SETTINGS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: _clearSuccess
                      ? BuoyTheme.teal
                      : (_clearing ? BuoyTheme.muted : BuoyTheme.error),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _desktopSyncCard() {
    final client = BuoySyncClient.instance;
    if (client == null) return const SizedBox.shrink();
    return ValueListenableBuilder<BuoySyncStatus>(
      valueListenable: client.status,
      builder: (context, status, _) {
        final connected = status.state == BuoySyncState.connected;
        final accent = connected ? BuoyTheme.teal : BuoyTheme.warning;
        return _StatusCard(
          icon: Icons.language,
          accent: accent,
          label: 'DESKTOP SYNC',
          badge: switch (status.state) {
            BuoySyncState.connected => 'CONNECTED',
            BuoySyncState.connecting => 'CONNECTING...',
            BuoySyncState.retrying => 'RETRYING',
          },
          badgeIcon: connected
              ? Icons.check_circle
              : Icons.warning_amber_rounded,
          description: connected
              ? 'Streaming tool data to Buoy Desktop at ${status.targetUrl}'
              : 'Trying to reach Buoy Desktop at ${status.targetUrl} — is '
                    'the desktop app running?',
          footer:
              status.state == BuoySyncState.retrying && status.lastError != null
              ? Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: BuoyTheme.warning.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Last error: ${status.lastError}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: BuoyTheme.textSecondary,
                    ),
                  ),
                )
              : null,
        );
      },
    );
  }

  // ── PRO tab ───────────────────────────────────────────────────────────

  Widget _proTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(
          Icons.bolt,
          'LICENSE STATUS',
          badge: 'Free',
          badgeColor: BuoyTheme.muted,
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 8, 4, 20),
          child: Text(
            'Upgrade to Pro to unlock all features and support development.',
            style: TextStyle(fontSize: 12, color: BuoyTheme.textSecondary),
          ),
        ),
        _sectionHeader(Icons.check_circle, 'PRO FEATURES'),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final feature in const [
                'Advanced Settings',
                'Export Configuration',
                'Team Defaults',
                'Priority Support',
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    spacing: 8,
                    children: [
                      const Icon(
                        Icons.check_circle,
                        size: 14,
                        color: BuoyTheme.teal,
                      ),
                      Text(
                        feature,
                        style: const TextStyle(
                          fontSize: 12,
                          color: BuoyTheme.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        TouchableOpacity(
          activeOpacity: 0.8,
          // License flow not wired yet — press feedback only.
          onTap: () {},
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: BuoyTheme.teal,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 8,
              children: [
                Icon(Icons.bolt, size: 16, color: BuoyTheme.base),
                Text(
                  'Upgrade to Pro',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: BuoyTheme.base,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionHeader(
    IconData icon,
    String title, {
    String? badge,
    Color badgeColor = BuoyTheme.teal,
  }) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            color: BuoyTheme.teal,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Icon(icon, size: 12, color: BuoyTheme.teal),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: BuoyTheme.teal,
            ),
          ),
        ),
        if (badge != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
            ),
            child: Text(
              badge,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: badgeColor,
              ),
            ),
          ),
      ],
    );
  }
}

/// RN `glassCard` tool row: icon chip + name/description + ON/OFF pill.
class _ToolCard extends StatelessWidget {
  const _ToolCard({
    required this.label,
    required this.description,
    required this.icon,
    required this.value,
    required this.onToggle,
  });

  final String label;
  final String description;
  final Widget icon;
  final bool value;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return TouchableOpacity(
      activeOpacity: 0.85,
      onTap: onToggle,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(
          color: value
              ? BuoyTheme.teal.withValues(alpha: 0.03)
              : BuoyTheme.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: value
                ? BuoyTheme.teal.withValues(alpha: 0.31)
                : BuoyTheme.border,
          ),
        ),
        child: Row(
          spacing: 12,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: value
                    ? BuoyTheme.teal.withValues(alpha: 0.13)
                    : BuoyTheme.hover,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(child: icon),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: BuoyTheme.secondary,
                    ),
                  ),
                  if (description.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: BuoyTheme.muted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Container(
              constraints: const BoxConstraints(minWidth: 48),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: value
                    ? BuoyTheme.teal.withValues(alpha: 0.13)
                    : BuoyTheme.hover,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: value ? BuoyTheme.teal : BuoyTheme.border,
                ),
              ),
              child: Text(
                value ? 'ON' : 'OFF',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  color: value ? BuoyTheme.teal : BuoyTheme.muted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// RN `renderGlobalSettingCard`: expandable card with category badge, title,
/// short description (collapsed), ON/OFF pill, chevron; expands to
/// DESCRIPTION + RECOMMENDATION sections with a teal glow border.
class _GlobalSettingCard extends StatelessWidget {
  const _GlobalSettingCard({
    required this.label,
    required this.category,
    required this.shortDescription,
    required this.fullDescription,
    required this.recommendation,
    required this.value,
    required this.expanded,
    required this.onToggle,
    required this.onExpandToggle,
  });

  final String label;
  final String category;
  final String shortDescription;
  final String fullDescription;
  final String recommendation;
  final bool value;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onExpandToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TouchableOpacity(
        activeOpacity: 0.85,
        onTap: onExpandToggle,
        child: Transform.scale(
          scale: expanded ? 1.01 : 1,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: BuoyTheme.card,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: expanded ? BuoyTheme.teal : BuoyTheme.border,
                width: expanded ? 2 : 1,
              ),
              boxShadow: expanded
                  ? [
                      BoxShadow(
                        color: BuoyTheme.teal.withValues(alpha: 0.35),
                        blurRadius: 20,
                      ),
                    ]
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  spacing: 12,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: BuoyTheme.teal.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: BuoyTheme.teal.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Text(
                        category,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: BuoyTheme.teal,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'monospace',
                              color: BuoyTheme.secondary,
                            ),
                          ),
                          if (!expanded)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                shortDescription,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: BuoyTheme.muted,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    TouchableOpacity(
                      activeOpacity: 0.8,
                      onTap: onToggle,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 48),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: value
                              ? BuoyTheme.teal.withValues(alpha: 0.2)
                              : BuoyTheme.hover,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: value
                                ? BuoyTheme.teal.withValues(alpha: 0.53)
                                : BuoyTheme.border,
                          ),
                          boxShadow: value
                              ? [
                                  BoxShadow(
                                    color: BuoyTheme.teal.withValues(
                                      alpha: 0.4,
                                    ),
                                    blurRadius: 8,
                                  ),
                                ]
                              : null,
                        ),
                        child: Text(
                          value ? 'ON' : 'OFF',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                            color: value ? BuoyTheme.teal : BuoyTheme.muted,
                          ),
                        ),
                      ),
                    ),
                    Icon(
                      expanded ? Icons.expand_more : Icons.chevron_right,
                      size: 18,
                      color: const Color(0xFF7F91B2),
                    ),
                  ],
                ),
                if (expanded)
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.only(top: 12),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: BuoyTheme.border.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _section('DESCRIPTION', fullDescription),
                        _section('RECOMMENDATION', recommendation),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: BuoyTheme.teal,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: const TextStyle(
              fontSize: 12,
              height: 18 / 12,
              color: BuoyTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// RN `storageStatusCard`: icon chip, LABEL, colored badge row, description,
/// optional expandable body and footer.
class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.icon,
    required this.accent,
    required this.label,
    required this.badge,
    required this.badgeIcon,
    required this.description,
    this.onHeaderTap,
    this.expanded = false,
    this.expandedChild,
    this.footer,
  });

  final IconData icon;
  final Color accent;
  final String label;
  final String badge;
  final IconData badgeIcon;
  final String description;
  final VoidCallback? onHeaderTap;
  final bool expanded;
  final Widget? expandedChild;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: BuoyTheme.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: expanded ? accent.withValues(alpha: 0.38) : BuoyTheme.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TouchableOpacity(
            activeOpacity: 0.8,
            onTap: onHeaderTap,
            child: Row(
              spacing: 12,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 18, color: accent),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                          color: BuoyTheme.muted,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        spacing: 6,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.13),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: accent.withValues(alpha: 0.38),
                              ),
                            ),
                            child: Text(
                              badge,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                                color: accent,
                              ),
                            ),
                          ),
                          Icon(badgeIcon, size: 14, color: accent),
                        ],
                      ),
                    ],
                  ),
                ),
                if (onHeaderTap != null)
                  Icon(
                    expanded ? Icons.expand_more : Icons.chevron_right,
                    size: 18,
                    color: BuoyTheme.muted,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: const TextStyle(
              fontSize: 11,
              height: 16 / 11,
              color: BuoyTheme.muted,
            ),
          ),
          if (expandedChild != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: BuoyTheme.border.withValues(alpha: 0.5),
                  ),
                ),
              ),
              child: expandedChild,
            ),
          ],
          if (footer != null) ...[const SizedBox(height: 12), footer!],
        ],
      ),
    );
  }
}
