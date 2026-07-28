/// Ports packages/image-overlay/src/imageOverlay/utils/ImageOverlayController.ts.
///
/// Singleton state manager bridging the control modal and the standalone
/// overlay layer. In RN it's a module-level `let state` + a `Set<Listener>`;
/// here it's a [ChangeNotifier] singleton (survives modal remount/minimize and
/// route navigation, resets on app restart — RN keeps state in module scope the
/// same way, with no storage persistence).
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'image_overlay_types.dart';
import 'image_target_registry.dart';

/// RN `getImageSize` result.
typedef ImageSize = ({double width, double height});

/// Pure helper: RN's `autoScale = targetRect.width / size.width` (defaults to
/// 1.0 when the image width is unknown/zero). Extracted for unit testing.
double computeAutoScale(double? targetWidth, double? imageWidth) {
  if (targetWidth != null &&
      imageWidth != null &&
      imageWidth > 0) {
    return targetWidth / imageWidth;
  }
  return 1.0;
}

/// Pure helper mirroring the sizing block in RN `startFreeMode`: center the
/// image, scaling it down to fit within 80% width / 60% height of the screen.
/// Extracted so the math is unit-testable without a screen.
({double x, double y, double width, double height}) computeFreePlacement(
  double? imageWidth,
  double? imageHeight,
  Size screen,
) {
  final w = imageWidth ?? 200;
  final h = imageHeight ?? 200;
  var displayW = w;
  var displayH = h;
  final maxW = screen.width * 0.8;
  final maxH = screen.height * 0.6;
  if (displayW > maxW || displayH > maxH) {
    final ratio = (maxW / displayW) < (maxH / displayH)
        ? (maxW / displayW)
        : (maxH / displayH);
    displayW = (displayW * ratio).roundToDouble();
    displayH = (displayH * ratio).roundToDouble();
  }
  return (
    x: ((screen.width - displayW) / 2).roundToDouble(),
    y: ((screen.height - displayH) / 2).roundToDouble(),
    width: displayW.roundToDouble(),
    height: displayH.roundToDouble(),
  );
}

/// Build an [ImageProvider] from a URL / `data:` URI, or `null` if unsupported.
ImageProvider? providerForUri(String uri) {
  final trimmed = uri.trim();
  if (trimmed.isEmpty) return null;
  if (trimmed.startsWith('data:')) {
    final comma = trimmed.indexOf(',');
    if (comma < 0) return null;
    final meta = trimmed.substring(5, comma);
    final payload = trimmed.substring(comma + 1);
    if (!meta.contains('base64')) return null;
    try {
      return MemoryImage(base64Decode(payload));
    } catch (_) {
      return null;
    }
  }
  if (trimmed.startsWith('http')) return NetworkImage(trimmed);
  return null;
}

double _clamp(double v, double min, double max) =>
    v < min ? min : (v > max ? max : v);

class ImageOverlayController extends ChangeNotifier {
  ImageOverlayController._();

  /// Process-wide singleton (RN's module state).
  static final ImageOverlayController instance = ImageOverlayController._();

  ImageOverlayState _state = const ImageOverlayState();
  ImageOverlayState get state => _state;

  /// The resolved provider for [ImageOverlayState.imageUri]. Kept off the state
  /// object (not serializable / not part of parity JSON) — the standalone reads
  /// it directly.
  ImageProvider? _imageProvider;
  ImageProvider? get imageProvider => _imageProvider;

  /// Mirrors RN's module-level `persistedImageUrl` — the URL text field value,
  /// preserved across modal remounts within a session.
  String persistedImageUrl = '';

  // Component-match target being tracked (RN's `targetInstance`/`targetLabel`).
  GlobalKey? _targetKey;
  String? _targetLabel;

  // Auto-track (RN uses React DevTools traceUpdates; Flutter re-measures on a
  // post-frame loop while enabled).
  bool _autoTrack = false;
  bool _autoTrackScheduled = false;
  bool get isAutoTracking => _autoTrack;

  void _set(ImageOverlayState next) {
    _state = next;
    notifyListeners();
  }

  // ─── Component Match Mode ───────────────────────────────────────────

  /// RN `setTarget`. Measures the target and stores its rect + label.
  Future<void> setTarget(DiscoveredTarget target) async {
    _targetKey = target.key;
    _targetLabel = target.label;
    final rect = measureTarget(target.key);
    _set(_state.copyWith(
      mode: OverlayMode.component,
      targetLabel: target.label,
      targetRect: rect,
      clearTargetRect: rect == null,
    ));
  }

  /// RN `setImageUri`. Records the image and auto-scales to the target width.
  ///
  /// Deviation from RN: RN blocks on `Image.getSize` before updating state.
  /// Flutter's `ImageStream` resolve can be slow (network) or, for some
  /// providers, not surface a completion at all — blocking the whole tool. So
  /// we apply the image immediately (controls + overlay appear at once) and
  /// refine the intrinsic size + auto-scale asynchronously when it decodes.
  Future<void> setImageUri(String uri) async {
    final provider = providerForUri(uri);
    _imageProvider = provider;
    _set(_state.copyWith(
      imageUri: uri,
      clearImageSize: true,
      scale: 1.0,
      showOutline: false,
    ));
    if (provider == null) return;
    final size = await _getImageSize(provider);
    if (size == null || _imageProvider != provider) return;
    _set(_state.copyWith(
      imageWidth: size.width,
      imageHeight: size.height,
      scale: computeAutoScale(_state.targetRect?.width, size.width),
    ));
  }

  void setOpacity(double value) =>
      _set(_state.copyWith(opacity: _clamp(value, 0, 1)));

  void setScale(double value) =>
      _set(_state.copyWith(scale: _clamp(value, 0.01, 5)));

  void setOffset(double x, double y) =>
      _set(_state.copyWith(offsetX: x, offsetY: y));

  void toggleInvertX() => _set(_state.copyWith(invertX: !_state.invertX));

  void toggleInvertY() => _set(_state.copyWith(invertY: !_state.invertY));

  void setLocked(bool locked) => _set(_state.copyWith(locked: locked));

  void setShowOutline(bool show) => _set(_state.copyWith(showOutline: show));

  void setEnabled(bool enabled) => _set(_state.copyWith(enabled: enabled));

  void toggle() => _set(_state.copyWith(enabled: !_state.enabled));

  void setAutoTrack(bool enabled) {
    _autoTrack = enabled;
    if (enabled) {
      _scheduleAutoTrackTick();
    }
    // Disabling simply lets the loop stop on its next tick.
  }

  void _scheduleAutoTrackTick() {
    if (_autoTrackScheduled) return;
    _autoTrackScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _autoTrackScheduled = false;
      if (!_autoTrack) return;
      _autoTrackRemeasure();
      _scheduleAutoTrackTick();
    });
  }

  /// RN `handleTraceForAutoTrack` — remeasure, notify only if moved > 0.5px.
  void _autoTrackRemeasure() {
    final key = _targetKey;
    final prev = _state.targetRect;
    if (key == null || prev == null) return;
    final rect = measureTarget(key);
    if (rect == null) return;
    if ((rect.x - prev.x).abs() > 0.5 ||
        (rect.y - prev.y).abs() > 0.5 ||
        (rect.width - prev.width).abs() > 0.5 ||
        (rect.height - prev.height).abs() > 0.5) {
      _set(_state.copyWith(targetRect: rect));
    }
  }

  void fitWidth() {
    final img = _state.imageWidth;
    final target = _state.targetRect;
    if (img != null && target != null && img > 0) {
      _set(_state.copyWith(scale: target.width / img));
    }
  }

  void fitHeight() {
    final img = _state.imageHeight;
    final target = _state.targetRect;
    if (img != null && target != null && img > 0) {
      _set(_state.copyWith(scale: target.height / img));
    }
  }

  /// RN `resetSettings`. Free mode re-centers; component mode restores opacity +
  /// auto-scale and zeroes the offset.
  void resetSettings(Size screen) {
    if (_state.mode == OverlayMode.free) {
      final w = _state.imageWidth ?? 200;
      final h = _state.imageHeight ?? 200;
      _set(_state.copyWith(
        opacity: 0.5,
        freeX: (screen.width - w) / 2,
        freeY: (screen.height - h) / 2,
        freeWidth: w,
        freeHeight: h,
      ));
    } else {
      final autoScale =
          computeAutoScale(_state.targetRect?.width, _state.imageWidth);
      _set(_state.copyWith(
        opacity: 0.5,
        scale: autoScale,
        offsetX: 0,
        offsetY: 0,
      ));
    }
  }

  /// RN `remeasure`.
  Future<void> remeasure() async {
    final key = _targetKey;
    if (_targetLabel == null || key == null) return;
    final rect = measureTarget(key);
    if (rect != null) _set(_state.copyWith(targetRect: rect));
  }

  // ─── Free Placement Mode ───────────────────────────────────────────

  /// RN `startFreeMode`.
  ///
  /// Deviation from RN: applied non-blocking (see [setImageUri]). We center a
  /// 200×200 placeholder immediately so the overlay + controls appear at once,
  /// then re-center to the true aspect ratio once the image decodes.
  Future<void> startFreeMode(String uri, Size screen) async {
    final provider = providerForUri(uri);
    _imageProvider = provider;
    final initial = computeFreePlacement(null, null, screen);
    _set(_state.copyWith(
      mode: OverlayMode.free,
      enabled: true,
      imageUri: uri,
      clearImageSize: true,
      opacity: 0.5,
      freeX: initial.x,
      freeY: initial.y,
      freeWidth: initial.width,
      freeHeight: initial.height,
    ));
    if (provider == null) return;
    final size = await _getImageSize(provider);
    if (size == null || _imageProvider != provider) return;
    final placement = computeFreePlacement(size.width, size.height, screen);
    _set(_state.copyWith(
      imageWidth: size.width,
      imageHeight: size.height,
      freeX: placement.x,
      freeY: placement.y,
      freeWidth: placement.width,
      freeHeight: placement.height,
    ));
  }

  void setFreePosition(double x, double y) =>
      _set(_state.copyWith(freeX: x, freeY: y));

  void setFreeDimensions(double width, double height, double x, double y) =>
      _set(_state.copyWith(
        freeWidth: width,
        freeHeight: height,
        freeX: x,
        freeY: y,
      ));

  // ─── Shared ─────────────────────────────────────────────────────────

  /// RN `reset` — stop tracking and clear everything.
  void reset() {
    _autoTrack = false;
    _targetKey = null;
    _targetLabel = null;
    _imageProvider = null;
    persistedImageUrl = '';
    _set(const ImageOverlayState());
  }

  Future<ImageSize?> _getImageSize(ImageProvider provider) {
    final completer = Completer<ImageSize?>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        stream.removeListener(listener);
        if (!completer.isCompleted) {
          completer.complete((
            width: info.image.width.toDouble(),
            height: info.image.height.toDouble(),
          ));
        }
        info.image.dispose();
      },
      onError: (_, _) {
        stream.removeListener(listener);
        if (!completer.isCompleted) completer.complete(null);
      },
    );
    stream.addListener(listener);
    return completer.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () {
        stream.removeListener(listener);
        return null;
      },
    );
  }

  /// Test-only: reset the singleton between unit tests.
  @visibleForTesting
  void debugReset() {
    _autoTrack = false;
    _autoTrackScheduled = false;
    _targetKey = null;
    _targetLabel = null;
    _imageProvider = null;
    persistedImageUrl = '';
    _state = const ImageOverlayState();
  }
}
