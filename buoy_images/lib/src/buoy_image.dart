/// Ports the capture layer (packages/images/src/capture/installRnImage.tsx +
/// installExpoImage.ts) to a Flutter drop-in widget.
///
/// Flutter has no app-wide `Image` decorator hook, so capture is opt-in: use
/// [BuoyImage] in place of `Image` / `CachedNetworkImage`. It:
///  - creates one [ImageRecord] per mounted instance (kDebugMode only),
///  - resolves the provider and observes the stream for decoded size, load
///    timing and failures (the render itself shares the same cache completer,
///    so there is no double decode),
///  - reads `PaintingBinding.instance.imageCache` for the memory cache verdict,
///  - measures its own rendered box post-frame for the oversize audit,
///  - owns the rendered props so reload/retry and simulation overrides work.
///
/// Release builds skip all of this and render the child untouched.
library;

import 'package:buoy_core/buoy_core.dart' show BuoyTheme;
import 'package:buoy_shared_ui/buoy_shared_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'buoy_image_provider.dart';
import 'image_record.dart';
import 'images_actions.dart';
import 'images_store.dart';

/// A capture-instrumented image. [provider] is any [ImageProvider]
/// (NetworkImage, AssetImage, FileImage, or a CachedNetworkImageProvider — the
/// disk cache is preserved because BuoyImage renders the provider directly).
class BuoyImage extends StatefulWidget {
  const BuoyImage({
    super.key,
    required this.provider,
    this.width,
    this.height,
    this.fit,
    this.placeholder,
    this.errorWidget,
    this.fadeInDuration = const Duration(milliseconds: 200),
    this.semanticLabel,
  });

  final ImageProvider provider;
  final double? width;
  final double? height;
  final BoxFit? fit;

  /// Shown while the first frame is loading (RN placeholder).
  final WidgetBuilder? placeholder;

  /// Shown when the load fails (RN errorWidget). Receives the error object.
  final Widget Function(BuildContext context, Object error)? errorWidget;

  final Duration fadeInDuration;

  /// Accessibility label — fed to the "missing alt text" insight when absent.
  final String? semanticLabel;

  @override
  State<BuoyImage> createState() => _BuoyImageState();
}

class _BuoyImageState extends State<BuoyImage> {
  ImageRecord? _record;
  ImageStream? _stream;
  ImageStreamListener? _listener;
  void Function()? _unsubscribeActions;
  int _renderVersion = 0;
  int _lastReloadNonce = 0;
  Object? _error;
  bool _loadStarted = false;
  String _lastSourceSignature = '';

  final GlobalKey _boxKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (!kDebugMode) return;
    final record = ImagesStore.instance.createRecord(
      lib: _libFor(widget.provider),
      uri: _uriFor(widget.provider),
      sourceKind: _sourceKindFor(widget.provider),
    );
    record.hasAltText = widget.semanticLabel != null;
    _record = record;
    _unsubscribeActions = ImagesActions.instance.subscribeActions(
      _onActionVersionChanged,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureLayout());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Start the observing load BEFORE the child Image builds this frame, so we
    // see the true pre-load cache state (a post-frame resolve races the child's
    // own decode and would always read the bitmap as already-live → "memory").
    if (_record != null && !_loadStarted) {
      _loadStarted = true;
      _startLoad(bust: false);
    }
  }

  @override
  void didUpdateWidget(BuoyImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_record == null) return;
    // Source switch → finalize the old record, start a new one (RN behaviour).
    if (_uriFor(oldWidget.provider) != _uriFor(widget.provider)) {
      _record!.mounted = false;
      ImagesActions.instance.dropActionState(_record!.id);
      ImagesStore.instance.touch();
      final record = ImagesStore.instance.createRecord(
        lib: _libFor(widget.provider),
        uri: _uriFor(widget.provider),
        sourceKind: _sourceKindFor(widget.provider),
      );
      record.hasAltText = widget.semanticLabel != null;
      _record = record;
      _error = null;
      // Resolve now (before this frame's rebuild) for an accurate cache verdict.
      _startLoad(bust: false);
      WidgetsBinding.instance.addPostFrameCallback((_) => _measureLayout());
    }
  }

  void _onActionVersionChanged() {
    final record = _record;
    if (record == null || !mounted) return;
    final version = ImagesActions.instance.getRenderVersion(record.id);
    final nonce = ImagesActions.instance.getReloadNonce(record.id);
    if (version == _renderVersion && nonce == _lastReloadNonce) return;
    final reload = nonce != _lastReloadNonce;
    // Re-observe when the effective source changed (override set/cleared, or a
    // global network-mode change) so the record's status/timing follow the
    // simulated source — RN's wrapper re-renders and re-fires onLoad/onError.
    final signature = _sourceSignature();
    final sourceChanged = signature != _lastSourceSignature;
    setState(() {
      _renderVersion = version;
      _lastReloadNonce = nonce;
    });
    if (reload || sourceChanged) {
      final bust = reload && ImagesActions.instance.getReloadBust(record.id);
      _error = null;
      if (!_isBlanked) _startLoad(bust: bust);
      if (reload) ImagesActions.instance.settleReloadRequest(record.id);
    }
  }

  /// Identity of the currently-rendered source (original vs override vs mode).
  String _sourceSignature() {
    final record = _record;
    if (record == null) return '';
    final override = ImagesActions.instance.getOverride(record.id);
    final mode = ImagesActions.instance.networkMode.name;
    return '${override?.source.kind.name}:${override?.source.uri}:$mode';
  }

  /// The provider actually rendered/observed, after overrides + global modes.
  ImageProvider get _effectiveProvider {
    final record = _record;
    if (record == null) return widget.provider;
    final actions = ImagesActions.instance;
    final override = actions.getOverride(record.id);
    if (override != null) {
      switch (override.source.kind) {
        case OverrideKind.error:
          return const ForcedErrorImageProvider();
        case OverrideKind.hang:
          return const HangImageProvider();
        case OverrideKind.url:
          return NetworkImage(override.source.uri ?? widget.provider.toString());
        case OverrideKind.blank:
          return widget.provider; // blank handled in build (no image drawn)
      }
    }
    if (actions.networkMode == NetworkMode.offline &&
        record.sourceKind == SourceKind.network) {
      return const ForcedErrorImageProvider();
    }
    return widget.provider;
  }

  bool get _isBlanked {
    final record = _record;
    if (record == null) return false;
    if (ImagesActions.instance.blankImages) return true;
    final override = ImagesActions.instance.getOverride(record.id);
    return override?.source.kind == OverrideKind.blank;
  }

  void _measureLayout() {
    final record = _record;
    if (record == null || !mounted) return;
    final box = _boxKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final size = box.size;
    final dims = ImageDimensions(size.width.round(), size.height.round());
    final prev = record.layout;
    record.layout = dims;
    record.devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    // A box resize AFTER the image loaded is a layout-shift signal (RN CLS).
    if (prev != null &&
        record.status == ImageStatus.loaded &&
        (prev.width != dims.width || prev.height != dims.height)) {
      record.layoutShifts++;
    }
    ImagesStore.instance.touch();
  }

  void _startLoad({required bool bust}) {
    final record = _record;
    if (record == null || !mounted) return;
    _detachStream();
    _lastSourceSignature = _sourceSignature();

    final provider = _effectiveProvider;
    if (bust) provider.evict();
    if (ImagesActions.instance.networkMode == NetworkMode.cold) {
      provider.evict();
    }

    record.loadCount++;
    record.startedAt = DateTime.now().millisecondsSinceEpoch;
    record.status = ImageStatus.loading;
    record.error = null;
    record.errorCode = null;

    final config = createLocalImageConfiguration(context);
    // Memory verdict: was the decoded bitmap already resident?
    provider.obtainKey(config).then((key) {
      if (!mounted) return;
      final status = PaintingBinding.instance.imageCache.statusForKey(key);
      record.cacheVerdict = (status.keepAlive || status.live)
          ? CacheVerdict.memory
          : null; // finalized on first frame
    });

    final stream = provider.resolve(config);
    final listener = ImageStreamListener(
      _onImage,
      onError: _onImageError,
    );
    _stream = stream;
    _listener = listener;
    stream.addListener(listener);
    ImagesStore.instance.touch();
  }

  void _onImage(ImageInfo info, bool synchronousCall) {
    final record = _record;
    if (record == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    record.status = ImageStatus.loaded;
    record.loadedAt = now;
    record.durationMs = (now - (record.startedAt ?? record.createdAt)).toDouble();
    record.intrinsic = ImageDimensions(info.image.width, info.image.height);
    // A synchronous callback means the decoded bitmap was already resident.
    if (synchronousCall) record.cacheVerdict = CacheVerdict.memory;
    _finalizeCacheVerdict(record);
    if (_error != null && mounted) setState(() => _error = null);
    ImagesActions.instance.settleReloadRequest(record.id);
    ImagesStore.instance.touch();
  }

  void _onImageError(Object exception, StackTrace? stackTrace) {
    final record = _record;
    if (record == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    record.status = ImageStatus.error;
    record.erroredAt = now;
    record.durationMs = (now - (record.startedAt ?? record.createdAt)).toDouble();
    record.error = _errorMessage(exception);
    record.errorCode = _errorStatusCode(exception);
    ImagesActions.instance.settleReloadRequest(record.id);
    ImagesStore.instance.touch();
    if (mounted) setState(() => _error = exception);
  }

  /// memory (already handled) / disk / network heuristic (Flutter exposes no
  /// per-load origin) — see README.
  void _finalizeCacheVerdict(ImageRecord record) {
    if (record.cacheVerdict == CacheVerdict.memory) return;
    final diskBacked = _isDiskBacked(widget.provider);
    // Another mounted, already-loaded record for the same URI means this URI
    // has been fetched this session → a non-memory reload came from disk.
    final servedBefore = ImagesStore.instance.getSnapshot().any(
      (r) =>
          r.id != record.id &&
          r.uri == record.uri &&
          r.status == ImageStatus.loaded,
    );
    if (diskBacked && servedBefore) {
      record.cacheVerdict = CacheVerdict.disk;
      record.cacheVerdictSource = 'queryCache';
    } else {
      record.cacheVerdict = CacheVerdict.none; // network
      record.cacheVerdictSource = 'queryCache';
      record.progressSeen = true;
    }
  }

  void _detachStream() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    _stream = null;
    _listener = null;
  }

  @override
  void dispose() {
    _detachStream();
    _unsubscribeActions?.call();
    final record = _record;
    if (record != null) {
      record.mounted = false;
      ImagesActions.instance.dropActionState(record.id);
      ImagesStore.instance.touch();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return Image(
        image: widget.provider,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        semanticLabel: widget.semanticLabel,
      );
    }

    // Re-measure the box on every build (dims can change with layout).
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureLayout());

    final flashing =
        _record != null && ImagesActions.instance.isFlashing(_record!.id);

    Widget content;
    if (_isBlanked) {
      content = widget.placeholder?.call(context) ??
          SizedBox(width: widget.width, height: widget.height);
    } else {
      content = Image(
        // Key by reload nonce so a retry forces a fresh element + load cycle.
        key: ValueKey('buoy-img-${_record?.id}-$_lastReloadNonce'),
        image: _effectiveProvider,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        semanticLabel: widget.semanticLabel,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded) return child;
          return AnimatedOpacity(
            opacity: frame == null ? 0 : 1,
            duration: widget.fadeInDuration,
            curve: Curves.easeOut,
            child: frame == null
                ? (widget.placeholder?.call(context) ??
                      SizedBox(width: widget.width, height: widget.height))
                : child,
          );
        },
        errorBuilder: (context, error, stackTrace) =>
            widget.errorWidget?.call(context, error) ??
            SizedBox(
              width: widget.width,
              height: widget.height,
              child: const Center(
                child: BuoyGlyph(BuoyIcons.imageOff, color: Colors.white38),
              ),
            ),
      );
    }

    return Container(
      key: _boxKey,
      width: widget.width,
      height: widget.height,
      foregroundDecoration: flashing
          ? BoxDecoration(border: Border.all(color: BuoyTheme.error, width: 3))
          : null,
      child: content,
    );
  }
}

// ---------------------------------------------------------------------------
// Provider classification (runtimeType-based — no cached_network_image import)
// ---------------------------------------------------------------------------

String _providerTypeName(ImageProvider provider) =>
    provider.runtimeType.toString();

bool _isDiskBacked(ImageProvider provider) =>
    _providerTypeName(provider).contains('CachedNetworkImage');

ImageLib _libFor(ImageProvider provider) {
  final name = _providerTypeName(provider);
  if (name.contains('CachedNetworkImage')) return ImageLib.cached;
  if (provider is NetworkImage) return ImageLib.network;
  if (provider is AssetImage || provider is ExactAssetImage) {
    return ImageLib.asset;
  }
  if (provider is FileImage) return ImageLib.file;
  if (provider is MemoryImage) return ImageLib.memory;
  if (name.contains('Network')) return ImageLib.network;
  return ImageLib.other;
}

SourceKind _sourceKindFor(ImageProvider provider) {
  final name = _providerTypeName(provider);
  if (provider is NetworkImage || name.contains('Network')) {
    return SourceKind.network;
  }
  if (provider is AssetImage || provider is ExactAssetImage) {
    return SourceKind.asset;
  }
  if (provider is FileImage) return SourceKind.file;
  if (provider is MemoryImage) return SourceKind.data;
  return SourceKind.other;
}

String _uriFor(ImageProvider provider) {
  if (provider is NetworkImage) return provider.url;
  if (provider is AssetImage) return provider.assetName;
  if (provider is ExactAssetImage) return provider.assetName;
  if (provider is FileImage) return provider.file.path;
  // CachedNetworkImageProvider and others expose `url` dynamically.
  try {
    final url = (provider as dynamic).url;
    if (url is String) return url;
  } catch (_) {}
  try {
    final key = (provider as dynamic).cacheKey;
    if (key is String) return key;
  } catch (_) {}
  return provider.toString();
}

String _errorMessage(Object exception) {
  final text = exception.toString();
  return text.length > 300 ? '${text.substring(0, 300)}…' : text;
}

/// Extract an HTTP status from NetworkImageLoadException when present.
int? _errorStatusCode(Object exception) {
  if (exception is NetworkImageLoadException) return exception.statusCode;
  try {
    final code = (exception as dynamic).statusCode;
    if (code is int) return code;
  } catch (_) {}
  return null;
}
