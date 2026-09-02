import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../buoy.dart';
import '../../icons/buoy_icon_painter.dart';
import '../../icons/buoy_icons.dart';
import '../../license/keygen.dart';
import '../../license/license_manager.dart';
import '../../storage.dart';
import '../../sync_client.dart';
import '../../tool.dart';
import '../modal/js_modal.dart';
import '../modal/modal_settings.dart';
import '../night/night_primitives.dart';
import '../night/night_theme.dart';
import '../touchable_opacity.dart';

/// The shared background switcher (RN `BackgroundSwitcher`), mounted in the
/// SETTINGS tab's Background card. Lives in buoy_shared_ui with the presets,
/// so it reaches this sheet through a seam — `installToolBackground()` sets
/// it. Null = the Background section is not shown (bare-core install).
WidgetBuilder? backgroundSwitcherBuilder;

/// The dev-tools settings modal — port of the RN `DevToolsSettingsModal` in
/// its night form: a [JsModal] (bottom-sheet mode, 1/3 screen height,
/// mode/size persisted under `@react_buoy_settings`) with a [NightSegmented]
/// Floating / Settings / Pro header, and each tab as labelled [NightCard]
/// sections of hairline-separated rows.
///
/// Deviations from RN: no dev-only export-config card; the Upgrade button is
/// display-only (no licence-entry modal yet — the key comes from
/// `BuoyDevTools(licenseKey:)`); no Live Sky scrubber (no Flutter renderer).
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
  bool _syncExpanded = false;
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
      headerContent: _header(),
      child: Padding(
        // RN scrollContainer: gutter 16, top 8, bottom 24, gap 24.
        padding: const EdgeInsets.fromLTRB(Night.gutter, 8, Night.gutter, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Night.groupGap,
          children: switch (_tab) {
            'settings' => _settingsSections(),
            'pro' => _proSections(),
            _ => _floatingSections(),
          },
        ),
      ),
    );
  }

  /// RN headerRow: the NightSegmented tabs, gutter padding, 8 below.
  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Night.gutter, 0, Night.gutter, 8),
      child: NightSegmented(
        tabs: const [
          (key: 'floating', label: 'Floating'),
          (key: 'settings', label: 'Settings'),
          (key: 'pro', label: 'Pro'),
        ],
        activeKey: _tab,
        onChange: _selectTab,
      ),
    );
  }

  /// RN renderSection: uppercase label, card, optional footnote under it.
  Widget _section(String label, Widget card, {Widget? footnote}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [NightSectionLabel(label), card, ?footnote],
    );
  }

  // ── FLOATING tab ──────────────────────────────────────────────────────

  List<Widget> _floatingSections() {
    final settings = _settings;
    if (settings == null) return const [SizedBox.shrink()];
    return [
      _section(
        'Floating Tools',
        NightCard(
          child: NightRows(
            children: [
              for (final tool in widget.tools)
                _toolRow(
                  icon: tool.icon(18, tool.color),
                  label: tool.name,
                  description: tool.description ?? '',
                  value: settings.floatingTools[tool.id] ?? false,
                  onToggle: () => _toggleFloatingTool(tool.id),
                ),
              _toolRow(
                icon: const BuoyGlyph(BuoyIcons.globe, size: 18, color: NightColor.accent),
                label: 'Env Badge',
                description: 'Environment badge.',
                value: settings.floatingTools['environment'] ?? false,
                onToggle: () => _toggleFloatingTool('environment'),
              ),
            ],
          ),
        ),
        footnote: const NightFootnote(
          'Tools switched on here appear in the floating bubble row.',
        ),
      ),
    ];
  }

  /// RN renderToolRow: glyph (24 slot), name + one-line description, switch.
  /// Row: gap 12, padH 16, padV 12.
  Widget _toolRow({
    required Widget icon,
    required String label,
    required String description,
    required bool value,
    required VoidCallback onToggle,
  }) {
    return TouchableOpacity(
      activeOpacity: 0.7,
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Night.rowPadH, vertical: 12),
        child: Row(
          spacing: 12,
          children: [
            SizedBox(width: 24, child: Center(child: icon)),
            Expanded(child: _rowInfo(label, description)),
            NightSwitch(value: value, onChanged: (_) => onToggle()),
          ],
        ),
      ),
    );
  }

  /// RN rowInfo: label 15/500 text, caption 12 tertiary, gap 2.
  Widget _rowInfo(String label, String? caption, {int? captionLines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: 2,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: NightColor.text,
            fontSize: NightFont.row,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (caption != null && caption.isNotEmpty)
          Text(
            caption,
            maxLines: captionLines,
            overflow: captionLines == null ? null : TextOverflow.ellipsis,
            style: const TextStyle(color: NightColor.textTertiary, fontSize: NightFont.label),
          ),
      ],
    );
  }

  // ── SETTINGS tab ──────────────────────────────────────────────────────

  List<Widget> _settingsSections() {
    final settings = _settings;
    final switcher = backgroundSwitcherBuilder;
    return [
      // Tool background — the shipping mount of the shared background
      // switcher. It writes to shared-ui's persisted store, so the pick
      // applies to every tool modal at once.
      if (switcher != null)
        _section(
          'Background',
          NightCard(padded: true, child: Builder(builder: switcher)),
        ),
      _section('Storage', _storageCard()),
      if (BuoySyncClient.instance != null) _section('Desktop Sync', _desktopSyncCard()),
      if (settings != null)
        _section(
          'Modal Behavior',
          NightCard(
            child: NightRows(
              children: [
                _globalSettingRow(
                  'enableSharedModalDimensions',
                  'Shared Modal Size',
                  'Sync dimensions across all tools',
                  'When enabled, all tool modals will share the same size and '
                      'position. Resizing one modal will affect all others. When '
                      'disabled, each tool remembers its own size and position '
                      'independently.',
                  "Keep OFF for the best experience. This allows you to "
                      "customize each tool's modal size separately.",
                  settings.enableSharedModalDimensions,
                ),
                _globalSettingRow(
                  'expandableWindowControls',
                  'Expand Controls',
                  'iPad-style expandable window buttons',
                  'When enabled, the window control buttons (minimize, toggle '
                      'mode, close) start as small dots and expand into larger, '
                      'easy-to-tap buttons when pressed. When disabled, buttons '
                      'are directly tappable at their small size.',
                  'Keep ON for touch devices where the small buttons are hard '
                      'to press. Turn OFF if you prefer direct single-tap access.',
                  settings.expandableWindowControls,
                ),
              ],
            ),
          ),
        ),
    ];
  }

  /// RN settingRow: gap 10, padH 16, padV 14, minHeight 52.
  Widget _settingRow({
    required List<Widget> children,
    VoidCallback? onTap,
    String? semanticsLabel,
  }) {
    final row = Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: Night.rowPadH, vertical: Night.rowPadV),
      child: Row(spacing: 10, children: children),
    );
    if (onTap == null) return row;
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: TouchableOpacity(activeOpacity: 0.7, onTap: onTap, child: row),
    );
  }

  /// RN settingRowBody: padH 16, padBottom 14, gap 6; text 13 secondary
  /// (lineHeight 1.45), hint 13 tertiary.
  Widget _rowBody(List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Night.rowPadH, 0, Night.rowPadH, Night.rowPadV),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 6,
        children: children,
      ),
    );
  }

  static const _bodyText = TextStyle(
    color: NightColor.textSecondary,
    fontSize: NightFont.caption,
    height: 1.45,
  );
  static const _bodyHint = TextStyle(
    color: NightColor.textTertiary,
    fontSize: NightFont.caption,
    height: 1.45,
  );

  Widget _chevron(bool expanded) => BuoyGlyph(
        expanded ? BuoyIcons.chevronDown : BuoyIcons.chevronRight,
        size: 16,
        color: NightColor.textTertiary,
      );

  /// RN renderGlobalSettingRow: name + one-line hint, switch, and a
  /// tap-to-expand body holding the full description and recommendation.
  Widget _globalSettingRow(
    String key,
    String label,
    String shortDescription,
    String fullDescription,
    String recommendation,
    bool value,
  ) {
    final expanded = _expandedSettings.contains(key);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _settingRow(
          onTap: () => _toggleSettingExpanded(key),
          semanticsLabel: label,
          children: [
            Expanded(
              child: _rowInfo(label, shortDescription, captionLines: expanded ? null : 1),
            ),
            NightSwitch(value: value, onChanged: (_) => _toggleGlobalSetting(key)),
          ],
        ),
        if (expanded)
          _rowBody([
            Text(fullDescription, style: _bodyText),
            Text(recommendation, style: _bodyHint),
          ]),
      ],
    );
  }

  /// Storage — backend status, saved keys, and the clear action. Flutter's
  /// backend is always shared_preferences (RN's filesystem / asyncstorage /
  /// memory ladder has no analogue), so the badge is a constant.
  Widget _storageCard() {
    final keys = _savedKeys;
    return NightCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _settingRow(
            onTap: _toggleStorageExpanded,
            semanticsLabel: 'Storage Type',
            children: [
              Expanded(child: _rowInfo('Storage Type', null)),
              const NightBadge('Shared Preferences', tone: NightBadgeTone.accent),
              _chevron(_storageExpanded),
            ],
          ),
          if (_storageExpanded) ...[
            _rowBody(const [
              Text(
                'Settings persist via the platform preferences store and '
                'survive app restarts.',
                style: _bodyText,
              ),
            ]),
            const NightSeparator(),
            // RN storageExpanded: padH 16, padV 12, gap 8.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Night.rowPadH, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 8,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'SAVED SETTINGS',
                          style: TextStyle(
                            color: NightColor.textSecondary,
                            fontSize: NightFont.micro,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      Text(
                        keys == null ? '…' : '${keys.length} keys',
                        style: const TextStyle(color: NightColor.textTertiary, fontSize: NightFont.micro),
                      ),
                    ],
                  ),
                  if (keys == null)
                    const Text('Loading…', style: _keyEmpty)
                  else if (keys.isEmpty)
                    const Text('No settings saved yet', style: _keyEmpty)
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 150),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final key in keys)
                              Container(
                                margin: const EdgeInsets.only(bottom: 4),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                decoration: BoxDecoration(
                                  color: NightColor.surfaceElevated,
                                  borderRadius: BorderRadius.circular(NightRadius.segment),
                                ),
                                child: Text(
                                  key.replaceFirst('@react_buoy_', ''),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: NightColor.textSecondary,
                                    fontSize: NightFont.micro,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // The destructive action lives inside the expansion on purpose —
            // expand-then-tap is two deliberate steps. RN cardButtonWrap.
            Padding(
              padding: const EdgeInsets.fromLTRB(Night.cardPad, 10, Night.cardPad, Night.cardPad),
              child: NightButton(
                label: _clearSuccess
                    ? 'Cleared'
                    : _clearing
                        ? 'Clearing…'
                        : 'Clear All Settings',
                variant: _clearSuccess ? NightButtonVariant.secondary : NightButtonVariant.destructive,
                size: NightButtonSize.md,
                disabled: _clearing,
                onTap: _clearStorage,
                icon: BuoyGlyph(
                  _clearSuccess ? BuoyIcons.checkCircle : BuoyIcons.trash2,
                  size: 15,
                  color: _clearSuccess
                      ? NightColor.accent
                      : _clearing
                          ? NightColor.textTertiary
                          : NightColor.danger,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static const _keyEmpty = TextStyle(
    color: NightColor.textTertiary,
    fontSize: NightFont.caption,
    fontStyle: FontStyle.italic,
  );

  /// Desktop sync — hidden until the client exists (see the caller).
  Widget _desktopSyncCard() {
    final client = BuoySyncClient.instance!;
    return ValueListenableBuilder<BuoySyncStatus>(
      valueListenable: client.status,
      builder: (context, status, _) {
        final connected = status.state == BuoySyncState.connected;
        return NightCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _settingRow(
                onTap: () => setState(() => _syncExpanded = !_syncExpanded),
                semanticsLabel: 'Buoy Desktop',
                children: [
                  Expanded(child: _rowInfo('Buoy Desktop', null)),
                  switch (status.state) {
                    BuoySyncState.connected => const NightBadge('Connected', tone: NightBadgeTone.accent),
                    BuoySyncState.connecting => const NightBadge('Connecting…'),
                    BuoySyncState.retrying => const NightBadge('Retrying', tone: NightBadgeTone.warning),
                  },
                  _chevron(_syncExpanded),
                ],
              ),
              if (_syncExpanded)
                _rowBody([
                  Text.rich(
                    TextSpan(
                      style: _bodyText,
                      children: [
                        TextSpan(
                          text: connected
                              ? 'Streaming tool data to Buoy Desktop at '
                              : 'Trying to reach Buoy Desktop at ',
                        ),
                        TextSpan(
                          text: status.targetUrl,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: NightFont.label,
                            color: NightColor.textSecondary,
                          ),
                        ),
                        if (!connected)
                          const TextSpan(
                            text: ' — is the desktop app running? Override with the '
                                'socketUrl option if it runs elsewhere.',
                          ),
                      ],
                    ),
                  ),
                  if (status.state == BuoySyncState.retrying && status.lastError != null)
                    Text(
                      'Last error: ${status.lastError}',
                      style: _bodyText.copyWith(color: NightColor.warning),
                    ),
                ]),
            ],
          ),
        );
      },
    );
  }

  // ── PRO tab ───────────────────────────────────────────────────────────

  List<Widget> _proSections() {
    return [
      ValueListenableBuilder<BuoyLicenseState>(
        valueListenable: Buoy.license.state,
        builder: (context, license, _) {
          // The badge reads the VALIDATED tier — a free key must not read as
          // Pro anywhere.
          final badge = switch (license.tier) {
            BuoyTier.pro => const NightBadge('Active', tone: NightBadgeTone.accent),
            BuoyTier.free => const NightBadge('Free'),
            BuoyTier.anonymous => const NightBadge('Free'),
          };
          final footnote = license.isPro
              ? 'You have full access to all Buoy DevTools features.'
              : license.isValidating
                  ? 'Checking your license…'
                  : license.error != null
                      ? 'License check failed: ${license.error}.'
                      : 'Upgrade to Pro to unlock all features and support development.';
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Night.groupGap,
            children: [
              _section(
                'License',
                NightCard(
                  child: _settingRow(
                    children: [
                      Expanded(child: _rowInfo('License Status', null)),
                      badge,
                    ],
                  ),
                ),
                footnote: NightFootnote(footnote),
              ),
              if (!license.isPro) ...[
                _section(
                  'Pro Features',
                  NightCard(
                    child: NightRows(
                      children: [
                        for (final feature in const ['Advanced Settings', 'Priority Support'])
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: Night.rowPadH, vertical: 12),
                            child: Row(
                              spacing: 10,
                              children: [
                                const BuoyGlyph(BuoyIcons.checkCircle, size: 16, color: NightColor.accent),
                                Text(
                                  feature,
                                  style: const TextStyle(
                                    color: NightColor.text,
                                    fontSize: NightFont.row,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                // Display-only until a licence-entry modal is ported; the key
                // comes from BuoyDevTools(licenseKey:).
                NightButton(
                  label: 'Upgrade to Pro',
                  variant: NightButtonVariant.primary,
                  onTap: () {},
                ),
              ],
            ],
          );
        },
      ),
    ];
  }
}
