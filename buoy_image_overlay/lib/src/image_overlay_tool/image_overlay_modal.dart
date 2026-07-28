/// Ports packages/image-overlay/src/imageOverlay/components/ImageOverlayModal.tsx.
///
/// The image-overlay tool's control surface: a JsModal (RN persistence key
/// `buoy-image-overlay-modal`) that walks through four views — mode select
/// (idle), the discovered-target list, the Component Match controls, and the
/// Free Placement controls — driving [ImageOverlayController]. The actual
/// overlay is drawn by [ImageOverlayStandalone] outside this modal.
library;

import 'package:buoy_core/buoy_core.dart';
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../image_overlay_controller.dart';
import '../image_overlay_types.dart';
import '../image_target_registry.dart';
import 'overlay_controls.dart';
import 'target_list.dart';

enum _ModalView { idle, targets, controls, free }

class ImageOverlayModal extends StatefulWidget {
  const ImageOverlayModal({
    super.key,
    required this.storage,
    required this.onClose,
    this.onMinimize,
  });

  final BuoyStorage storage;
  final VoidCallback onClose;
  final VoidCallback? onMinimize;

  @override
  State<ImageOverlayModal> createState() => _ImageOverlayModalState();
}

class _ImageOverlayModalState extends State<ImageOverlayModal> {
  final _controller = ImageOverlayController.instance;
  final _urlController = TextEditingController();

  late _ModalView _view;
  List<DiscoveredTarget> _targets = const [];
  late bool _autoTrack;

  @override
  void initState() {
    super.initState();
    final s = _controller.state;
    if (s.mode == OverlayMode.free) {
      _view = _ModalView.free;
    } else if (s.targetRect != null) {
      _view = _ModalView.controls;
    } else {
      _view = _ModalView.idle;
    }
    _autoTrack = _controller.isAutoTracking;
    _urlController.text = _controller.persistedImageUrl;
    _urlController.addListener(_onUrlChanged);
    _controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _urlController.removeListener(_onUrlChanged);
    _urlController.dispose();
    _controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onUrlChanged() {
    // Mirror RN's module-level persistedImageUrl so the field survives remount.
    _controller.persistedImageUrl = _urlController.text;
    // Rebuild so the Load button's enabled state tracks the field.
    if (mounted) setState(() {});
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  ImageOverlayState get _state => _controller.state;
  Size get _screen => MediaQuery.of(context).size;

  void _handleScan() {
    setState(() {
      _targets = scanForImageTargets();
      _view = _ModalView.targets;
    });
  }

  Future<void> _handleSelectTarget(DiscoveredTarget target) async {
    await _controller.setTarget(target);
    final url = _urlController.text.trim();
    if (url.isNotEmpty) {
      await _controller.setImageUri(url);
      _controller.setEnabled(true);
    }
    if (mounted) setState(() => _view = _ModalView.controls);
  }

  Future<void> _handleLoadImage() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    if (_view == _ModalView.free) {
      await _controller.startFreeMode(url, _screen);
    } else {
      await _controller.setImageUri(url);
      _controller.setEnabled(true);
    }
  }

  Future<void> _handlePasteImage() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text != null &&
        (text.startsWith('http') || text.startsWith('data:'))) {
      _urlController.text = text; // fires the listener → persistedImageUrl
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text('No image URL on the clipboard — copy an image URL.'),
      ),
    );
  }

  void _handleReset() {
    _controller.reset();
    _urlController.clear();
    setState(() {
      _targets = const [];
      _view = _ModalView.idle;
    });
  }

  void _handleBack() {
    if (_view == _ModalView.controls) {
      setState(() {
        _targets = scanForImageTargets();
        _view = _ModalView.targets;
      });
    } else if (_view == _ModalView.targets || _view == _ModalView.free) {
      _controller.reset();
      setState(() => _view = _ModalView.idle);
    } else {
      setState(() => _view = _ModalView.idle);
    }
  }

  String get _headerTitle {
    switch (_view) {
      case _ModalView.targets:
        return 'Targets (${_targets.length})';
      case _ModalView.controls:
        return _state.targetLabel ?? 'Component Match';
      case _ModalView.free:
        return 'Free Placement';
      case _ModalView.idle:
        return 'Image Overlay';
    }
  }

  @override
  Widget build(BuildContext context) {
    return JsModal(
      storage: widget.storage,
      onClose: widget.onClose,
      onMinimize: widget.onMinimize,
      persistenceKey: 'buoy-image-overlay-modal',
      wrapChildInScrollView: false,
      headerContent: _header(),
      child: SizedBox.expand(child: _body()),
    );
  }

  Widget _header() {
    final showImage = _state.imageUri != null;
    return ModalHeader(
      children: [
        ModalHeaderBack(
          onBack: _view != _ModalView.idle ? _handleBack : widget.onClose,
        ),
        ModalHeaderContent(title: _headerTitle),
        ModalHeaderActions(
          children: [
            if (_view == _ModalView.targets)
              TouchableOpacity(
                activeOpacity: 0.7,
                onTap: _handleScan,
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: MacOSColors.backgroundHover,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: MacOSColors.borderDefault),
                  ),
                  child: const Text(
                    'Scan',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: BuoyColors.primary,
                    ),
                  ),
                ),
              ),
            if ((_view == _ModalView.controls || _view == _ModalView.free) &&
                showImage)
              PowerToggleButton(
                isEnabled: _state.enabled,
                onToggle: _controller.toggle,
              ),
            if (_view != _ModalView.idle)
              HeaderActionButton(
                icon: BuoyIcons.trash2,
                color: MacOSColors.textSecondary,
                onTap: _handleReset,
              ),
          ],
        ),
      ],
    );
  }

  Widget _body() {
    switch (_view) {
      case _ModalView.idle:
        return _idleView();
      case _ModalView.targets:
        return TargetList(targets: _targets, onSelect: _handleSelectTarget);
      case _ModalView.controls:
        return _controlsView();
      case _ModalView.free:
        return _freeView();
    }
  }

  // ─── Idle: mode selection ───
  Widget _idleView() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'CHOOSE A MODE',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: MacOSColors.textMuted,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _modePanel(
                  icon: BuoyIcons.crop,
                  iconColor: MacOSColors.success,
                  title: 'Component\nMatch',
                  desc: 'Overlay on a tagged component',
                  onTap: _handleScan,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _modePanel(
                  icon: BuoyIcons.image,
                  iconColor: BuoyColors.primary,
                  title: 'Free\nPlacement',
                  desc: 'Drag and resize anywhere',
                  onTap: () => setState(() => _view = _ModalView.free),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _modePanel({
    required LucideIcon icon,
    required Color iconColor,
    required String title,
    required String desc,
    required VoidCallback onTap,
  }) {
    return TouchableOpacity(
      activeOpacity: 0.7,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
        decoration: BoxDecoration(
          color: MacOSColors.backgroundHover,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: MacOSColors.borderDefault),
        ),
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0x18 / 255),
                shape: BoxShape.circle,
              ),
              child: BuoyGlyph(icon, size: 24, color: iconColor),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                height: 17 / 13,
                fontWeight: FontWeight.w700,
                color: MacOSColors.textPrimary,
              ),
            ),
            Text(
              desc,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                height: 15 / 11,
                color: MacOSColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Component Match: controls ───
  Widget _controlsView() {
    final s = _state;
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (s.targetRect != null)
            _infoCard([
              _infoRow('Component', s.targetLabel ?? '', mono: false),
              _infoRow(
                'Size',
                '${s.targetRect!.width.round()} x ${s.targetRect!.height.round()}',
              ),
              _infoRow(
                'Position',
                '${s.targetRect!.x.round()}, ${s.targetRect!.y.round()}',
              ),
              if (s.imageWidth != null && s.imageHeight != null)
                _infoRow(
                  'Image',
                  '${s.imageWidth!.round()} x ${s.imageHeight!.round()}',
                ),
            ]),
          const SizedBox(height: 10),
          _imageInputSection(),
          const SizedBox(height: 10),
          _toggleSection([
            _toggleRow(
              'Show Outline',
              s.showOutline,
              (v) => _controller.setShowOutline(v),
            ),
            _toggleRow(
              'Auto Track',
              _autoTrack,
              (v) {
                setState(() => _autoTrack = v);
                _controller.setAutoTrack(v);
              },
              activeColor: MacOSColors.success,
            ),
            if (s.imageUri != null) ...[
              _opacityButtonsRow(),
              _flipRow(),
            ],
          ]),
          if (s.imageUri != null) ...[
            const SizedBox(height: 10),
            OverlayControls(
              opacity: s.opacity,
              scale: s.scale,
              offsetX: s.offsetX,
              offsetY: s.offsetY,
              onOpacityChange: _controller.setOpacity,
              onScaleChange: _controller.setScale,
              onOffsetChange: _controller.setOffset,
            ),
          ],
          const SizedBox(height: 4),
          _actionsRow([
            _actionButton('Reset Settings', () => _controller.resetSettings(_screen)),
            _actionButton('Remeasure', _controller.remeasure),
          ]),
        ],
      ),
    );
  }

  // ─── Free Placement: controls ───
  Widget _freeView() {
    final s = _state;
    final hasImage = s.imageUri != null && s.mode == OverlayMode.free;
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _imageInputSection(),
          if (hasImage) ...[
            const SizedBox(height: 10),
            _infoCard([
              _infoRow('Position', '${s.freeX.round()}, ${s.freeY.round()}'),
              _infoRow(
                'Size',
                '${s.freeWidth.round()} x ${s.freeHeight.round()}',
              ),
              if (s.imageWidth != null && s.imageHeight != null)
                _infoRow(
                  'Original',
                  '${s.imageWidth!.round()} x ${s.imageHeight!.round()}',
                ),
            ]),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: OverlayControls(
                opacity: s.opacity,
                scale: 1,
                offsetX: 0,
                offsetY: 0,
                onOpacityChange: _controller.setOpacity,
                onScaleChange: (_) {},
                onOffsetChange: (_, _) {},
                opacityOnly: true,
              ),
            ),
            const SizedBox(height: 10),
            _toggleSection([
              _toggleRow(
                'Lock Position',
                s.locked,
                (v) => _controller.setLocked(v),
                activeColor: const Color(0xFFF59E0B),
              ),
              _opacityButtonsRow(),
              _flipRow(),
            ]),
            const SizedBox(height: 4),
            _actionsRow([
              _actionButton(
                'Reset Position',
                () => _controller.resetSettings(_screen),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  // ─── Shared pieces ───

  Widget _imageInputSection() {
    final canLoad = _urlController.text.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'IMAGE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: MacOSColors.textMuted,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          TouchableOpacity(
            activeOpacity: 0.7,
            onTap: _handlePasteImage,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: BuoyColors.primary.withValues(alpha: 0x15 / 255),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: BuoyColors.primary.withValues(alpha: 0x40 / 255),
                ),
              ),
              child: const Text(
                'Paste from Clipboard',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: BuoyColors.primary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    controller: _urlController,
                    autocorrect: false,
                    textCapitalization: TextCapitalization.none,
                    style: const TextStyle(
                      fontSize: 13,
                      color: MacOSColors.textPrimary,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12),
                      hintText: 'or enter URL...',
                      hintStyle:
                          const TextStyle(color: MacOSColors.textMuted),
                      filled: true,
                      fillColor: MacOSColors.backgroundInput,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                            color: MacOSColors.borderDefault),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                            color: MacOSColors.borderDefault),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                            color: MacOSColors.borderDefault),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TouchableOpacity(
                activeOpacity: 0.7,
                onTap: canLoad ? _handleLoadImage : null,
                child: Opacity(
                  opacity: canLoad ? 1 : 0.4,
                  child: Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: BuoyColors.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Load',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFFFFFFF),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoCard(List<Widget> rows) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: MacOSColors.backgroundHover,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MacOSColors.borderDefault),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 4),
            rows[i],
          ],
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, {bool mono = true}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: MacOSColors.textMuted,
            letterSpacing: 0.3,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: MacOSColors.textPrimary,
            fontFamily: mono ? 'monospace' : null,
          ),
        ),
      ],
    );
  }

  Widget _toggleSection(List<Widget> rows) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 6),
            rows[i],
          ],
        ],
      ),
    );
  }

  Widget _toggleRow(
    String label,
    bool value,
    ValueChanged<bool> onChanged, {
    Color activeColor = BuoyColors.primary,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: MacOSColors.backgroundHover,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MacOSColors.borderDefault),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: MacOSColors.textSecondary,
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: activeColor,
            inactiveTrackColor: MacOSColors.backgroundHover,
          ),
        ],
      ),
    );
  }

  Widget _opacityButtonsRow() {
    return _blendRow(
      'Opacity',
      [
        for (final pct in const [0, 25, 50, 75, 100])
          _blendButton(
            '$pct%',
            (_state.opacity * 100).round() == pct,
            () => _controller.setOpacity(pct / 100),
          ),
      ],
    );
  }

  Widget _flipRow() {
    return _blendRow(
      'Flip',
      [
        _blendButton('Horizontal', _state.invertX, _controller.toggleInvertX),
        _blendButton('Vertical', _state.invertY, _controller.toggleInvertY),
      ],
    );
  }

  Widget _blendRow(String label, List<Widget> buttons) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: MacOSColors.backgroundHover,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MacOSColors.borderDefault),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: MacOSColors.textSecondary,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < buttons.length; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                buttons[i],
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _blendButton(String label, bool active, VoidCallback onTap) {
    return TouchableOpacity(
      activeOpacity: 0.7,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active
              ? BuoyColors.primary.withValues(alpha: 0x20 / 255)
              : const Color(0x00000000),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: active ? BuoyColors.primary : MacOSColors.textMuted,
          ),
        ),
      ),
    );
  }

  Widget _actionsRow(List<Widget> buttons) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          for (var i = 0; i < buttons.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: buttons[i]),
          ],
        ],
      ),
    );
  }

  Widget _actionButton(String label, VoidCallback onTap) {
    return TouchableOpacity(
      activeOpacity: 0.7,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: MacOSColors.backgroundHover,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: MacOSColors.borderDefault),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: MacOSColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
