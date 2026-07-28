/// Ports packages/impersonate/src/impersonate/components/DataNukeSettings.tsx.
///
/// The Settings tab: header-key input, floating-banner toggle, and the
/// data-clearing toggles (React Query / Redux recommended; AsyncStorage / MMKV
/// dangerous), plus How-It-Works + Export-Configuration sections. Save / Discard
/// / Restore-Defaults pattern (banner applies immediately). Detection badges =
/// whether a clear callback was configured (RN's runtime auto-detect analog).
library;

import 'package:buoy_core/buoy_core.dart';
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../impersonate_types.dart';

const String _defaultHeaderKey = 'x-impersonate-user-id';
const bool _defaultShowBanner = true;
const DataNukeSettings _defaultSettings = DataNukeSettings.defaults;

/// Which clear integrations were configured. RN `DetectionStatus`.
typedef DetectionStatus = ({
  bool reactQuery,
  bool redux,
  bool asyncStorage,
  bool mmkv,
});

/// RN `DataNukeSettings` component.
class DataNukeSettingsView extends StatefulWidget {
  const DataNukeSettingsView({
    super.key,
    required this.headerKey,
    required this.settings,
    required this.showBanner,
    required this.onSave,
    required this.onShowBannerChange,
    required this.detectionStatus,
  });

  final String headerKey;
  final DataNukeSettings settings;
  final bool showBanner;
  final void Function(String headerKey, DataNukeSettings settings, bool showBanner)
  onSave;
  final ValueChanged<bool> onShowBannerChange;
  final DetectionStatus detectionStatus;

  @override
  State<DataNukeSettingsView> createState() => _DataNukeSettingsViewState();
}

class _DataNukeSettingsViewState extends State<DataNukeSettingsView> {
  late final TextEditingController _headerController =
      TextEditingController(text: widget.headerKey);
  late DataNukeSettings _local = widget.settings;
  late bool _localShowBanner = widget.showBanner;
  bool _copySuccess = false;

  @override
  void didUpdateWidget(DataNukeSettingsView old) {
    super.didUpdateWidget(old);
    // Sync local state when props change (e.g. after async load from storage).
    if (old.headerKey != widget.headerKey &&
        _headerController.text == old.headerKey) {
      _headerController.text = widget.headerKey;
    }
    if (old.settings != widget.settings) _local = widget.settings;
    if (old.showBanner != widget.showBanner) _localShowBanner = widget.showBanner;
  }

  @override
  void dispose() {
    _headerController.dispose();
    super.dispose();
  }

  bool get _hasChanges =>
      _headerController.text != widget.headerKey || _local != widget.settings;

  bool get _isDefault =>
      _headerController.text == _defaultHeaderKey &&
      _localShowBanner == _defaultShowBanner &&
      _local == _defaultSettings;

  void _save() {
    final key = _headerController.text.trim();
    widget.onSave(
      key.isEmpty ? _defaultHeaderKey : key,
      _local,
      _localShowBanner,
    );
  }

  void _discard() {
    setState(() {
      _headerController.text = widget.headerKey;
      _local = widget.settings;
      _localShowBanner = widget.showBanner;
    });
  }

  void _restoreDefaults() {
    setState(() {
      _headerController.text = _defaultHeaderKey;
      _local = _defaultSettings;
      _localShowBanner = _defaultShowBanner;
    });
    widget.onShowBannerChange(_defaultShowBanner);
  }

  Future<void> _copyConfig() async {
    final s = _local;
    final config =
        "defaults: {\n"
        "  headerKey: '${_headerController.text}',\n"
        "  showBanner: $_localShowBanner,\n"
        "  dataNukeSettings: {\n"
        "    reactQuery: ${s.reactQuery},\n"
        "    redux: ${s.redux},\n"
        "    asyncStorage: ${s.asyncStorage},\n"
        "    mmkv: ${s.mmkv},\n"
        "  },\n"
        "},";
    await Clipboard.setData(ClipboardData(text: config));
    if (!mounted) return;
    setState(() => _copySuccess = true);
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copySuccess = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final det = widget.detectionStatus;
    final configData = {
      'defaults': {
        'headerKey': _headerController.text,
        'showBanner': _localShowBanner,
        'dataNukeSettings': _local.toJson(),
      },
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        if (_hasChanges) _actionBar(),
        if (_hasChanges) const SizedBox(height: 12),

        // Header Configuration
        CollapsibleSection(
          title: 'Header Configuration',
          icon: BuoyIcons.settings,
          defaultOpen: true,
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Header Key',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: BuoyColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                _headerInput(),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Expanded(
                      child: Text(
                        'The HTTP header key used for impersonation. Value will '
                        'be the user ID.',
                        style: TextStyle(
                          fontSize: 12,
                          color: BuoyColors.textMuted,
                          height: 1.3,
                        ),
                      ),
                    ),
                    if (_headerController.text != _defaultHeaderKey)
                      TouchableOpacityText(
                        label: 'Reset to default',
                        onTap: () => setState(
                          () => _headerController.text = _defaultHeaderKey,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Display
        CollapsibleSection(
          title: 'Display',
          icon: BuoyIcons.eye,
          defaultOpen: true,
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _togglesCard([
              _ToggleRow(
                label: 'Floating Banner',
                description:
                    'Show a floating banner when impersonation is active',
                value: _localShowBanner,
                onChanged: (v) {
                  setState(() => _localShowBanner = v);
                  widget.onShowBannerChange(v);
                },
                recommended: true,
              ),
            ]),
          ),
        ),
        const SizedBox(height: 12),

        // Data Clearing
        CollapsibleSection(
          title: 'Data Clearing',
          icon: BuoyIcons.alertTriangle,
          defaultOpen: true,
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Choose what data to clear when impersonation starts or stops. '
                  'This ensures you see fresh data for the impersonated user.',
                  style: TextStyle(
                    fontSize: 13,
                    color: BuoyColors.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),
                _togglesCard([
                  _ToggleRow(
                    label: 'React Query',
                    description: 'Clear query cache and cancel pending queries',
                    value: _local.reactQuery,
                    onChanged: (v) =>
                        setState(() => _local = _local.copyWith(reactQuery: v)),
                    recommended: true,
                    detected: det.reactQuery,
                  ),
                  const _Divider(),
                  _ToggleRow(
                    label: 'Redux',
                    description: 'Reset Redux store to initial state',
                    value: _local.redux,
                    onChanged: (v) =>
                        setState(() => _local = _local.copyWith(redux: v)),
                    recommended: true,
                    detected: det.redux,
                  ),
                ]),
                const SizedBox(height: 16),
                const Text(
                  'STORAGE OPTIONS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: BuoyColors.textMuted,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                _togglesCard(
                  dangerous: true,
                  [
                    _ToggleRow(
                      label: 'AsyncStorage',
                      description: 'Clear app data (preserves @buoy/* keys)',
                      value: _local.asyncStorage,
                      onChanged: (v) => setState(
                        () => _local = _local.copyWith(asyncStorage: v),
                      ),
                      dangerous: true,
                      detected: det.asyncStorage,
                    ),
                    const _Divider(),
                    _ToggleRow(
                      label: 'MMKV',
                      description: 'Clear MMKV storage (preserves @buoy/* keys)',
                      value: _local.mmkv,
                      onChanged: (v) =>
                          setState(() => _local = _local.copyWith(mmkv: v)),
                      dangerous: true,
                      detected: det.mmkv,
                    ),
                  ],
                ),
                if (_local.asyncStorage || _local.mmkv) ...[
                  const SizedBox(height: 14),
                  _storageWarning(),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        if (!_isDefault) ...[_restoreButton(), const SizedBox(height: 12)],

        // How It Works
        CollapsibleSection(
          title: 'How It Works',
          icon: BuoyIcons.info,
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'When impersonation is enabled, the configured header is '
                  'automatically added to all outgoing requests.',
                  style: TextStyle(
                    fontSize: 13,
                    color: BuoyColors.textSecondary,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Your backend should check for this header and return data for '
                  'the specified user ID instead of the authenticated user.',
                  style: TextStyle(
                    fontSize: 13,
                    color: BuoyColors.textSecondary,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 14),
                _codeBlock(),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Export Configuration
        CollapsibleSection(
          title: 'Export Configuration',
          icon: BuoyIcons.copy,
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Copy current settings to use in registerBuoyImpersonate().',
                  style: TextStyle(
                    fontSize: 13,
                    color: BuoyColors.textSecondary,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: BuoyColors.border),
                  ),
                  child: DataViewer(data: configData, initialExpanded: true),
                ),
                const SizedBox(height: 14),
                _copyButton(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _headerInput() {
    return Container(
      height: 42,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: BuoyColors.hover,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: BuoyColors.border),
      ),
      child: TextField(
        controller: _headerController,
        autocorrect: false,
        onChanged: (_) => setState(() {}),
        style: const TextStyle(
          fontSize: 14,
          color: BuoyColors.text,
          fontFamily: 'monospace',
        ),
        cursorColor: BuoyColors.primary,
        decoration: const InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
          hintText: 'x-impersonate-user-id',
          hintStyle: TextStyle(
            fontSize: 14,
            color: BuoyColors.textMuted,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }

  Widget _actionBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: BuoyColors.primary.hexAlpha(0x15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: BuoyColors.primary.hexAlpha(0x30)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Unsaved changes',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: BuoyColors.primary,
            ),
          ),
          Row(
            children: [
              TouchableOpacity(
                activeOpacity: 0.7,
                onTap: _discard,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: BuoyColors.hover,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: BuoyColors.border),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      BuoyGlyph(BuoyIcons.x, size: 14, color: BuoyColors.textSecondary),
                      SizedBox(width: 6),
                      Text(
                        'Discard',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: BuoyColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TouchableOpacity(
                activeOpacity: 0.7,
                onTap: _save,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: BuoyColors.primary,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      BuoyGlyph(BuoyIcons.check, size: 14, color: Color(0xFFFFFFFF)),
                      SizedBox(width: 6),
                      Text(
                        'Save',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFFFFFFF),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _togglesCard(List<Widget> children, {bool dangerous = false}) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: BuoyColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: dangerous ? BuoyColors.warning.hexAlpha(0x30) : BuoyColors.border,
        ),
      ),
      child: Column(children: children),
    );
  }

  Widget _storageWarning() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: BuoyColors.warning.hexAlpha(0x10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: BuoyColors.warning.hexAlpha(0x25)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BuoyGlyph(BuoyIcons.alertTriangle, size: 16, color: BuoyColors.warning),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Storage Clearing Enabled',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: BuoyColors.warning,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'This will remove app data like settings and cached content. '
                  'Auth tokens managed by @buoy/* are preserved.',
                  style: TextStyle(
                    fontSize: 12,
                    color: BuoyColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _restoreButton() {
    return TouchableOpacity(
      activeOpacity: 0.7,
      onTap: _restoreDefaults,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: BuoyColors.border),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            BuoyGlyph(BuoyIcons.refreshCw, size: 14, color: BuoyColors.textSecondary),
            SizedBox(width: 8),
            Text(
              'Restore Defaults',
              style: TextStyle(fontSize: 13, color: BuoyColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _codeBlock() {
    final key = _headerController.text.isEmpty
        ? _defaultHeaderKey
        : _headerController.text;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: BuoyColors.base,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '// Example request header',
            style: TextStyle(
              fontSize: 12,
              color: BuoyColors.textMuted,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(
              style: const TextStyle(
                fontSize: 13,
                color: BuoyColors.text,
                fontFamily: 'monospace',
              ),
              children: [
                TextSpan(text: '$key: '),
                const TextSpan(
                  text: 'user_123',
                  style: TextStyle(color: BuoyColors.primary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _copyButton() {
    return TouchableOpacity(
      activeOpacity: 0.7,
      onTap: _copyConfig,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: BuoyColors.primary.hexAlpha(0x15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: BuoyColors.primary.hexAlpha(0x30)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            BuoyGlyph(
              _copySuccess ? BuoyIcons.check : BuoyIcons.copy,
              size: 14,
              color: _copySuccess ? BuoyColors.success : BuoyColors.primary,
            ),
            const SizedBox(width: 8),
            Text(
              _copySuccess ? 'Copied!' : 'Copy Config',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _copySuccess ? BuoyColors.success : BuoyColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) => Container(
    height: 1,
    margin: const EdgeInsets.symmetric(horizontal: 12),
    color: BuoyColors.border,
  );
}

/// RN `ToggleRow`.
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
    this.recommended = false,
    this.dangerous = false,
    this.detected,
  });

  final String label;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool recommended;
  final bool dangerous;
  final bool? detected;

  @override
  Widget build(BuildContext context) {
    final accent = dangerous ? BuoyColors.warning : BuoyColors.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: dangerous ? BuoyColors.warning : BuoyColors.text,
                        ),
                      ),
                    ),
                    if (detected != null) ...[
                      const SizedBox(width: 8),
                      _DetectedBadge(detected: detected!),
                    ],
                    if (recommended && detected != false) ...[
                      const SizedBox(width: 8),
                      const _RecommendedBadge(),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 12,
                    color: BuoyColors.textMuted,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: accent,
            activeTrackColor: accent.hexAlpha(0x50),
            inactiveThumbColor: BuoyColors.textMuted,
            inactiveTrackColor: BuoyColors.border,
          ),
        ],
      ),
    );
  }
}

class _DetectedBadge extends StatelessWidget {
  const _DetectedBadge({required this.detected});
  final bool detected;

  @override
  Widget build(BuildContext context) {
    final color = detected ? BuoyColors.success : BuoyColors.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.hexAlpha(0x15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          BuoyGlyph(detected ? BuoyIcons.check : BuoyIcons.x, size: 10, color: color),
          const SizedBox(width: 4),
          Text(
            detected ? 'Detected' : 'Not Detected',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecommendedBadge extends StatelessWidget {
  const _RecommendedBadge();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: BuoyColors.primary.hexAlpha(0x15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          BuoyGlyph(BuoyIcons.zap, size: 10, color: BuoyColors.primary),
          SizedBox(width: 4),
          Text(
            'Recommended',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: BuoyColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

/// A minimal inline text link (RN `resetLink`).
class TouchableOpacityText extends StatelessWidget {
  const TouchableOpacityText({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          color: BuoyColors.primary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
