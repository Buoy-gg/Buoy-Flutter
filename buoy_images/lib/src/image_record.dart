/// Ports packages/images/src/types.ts — the ImageRecord model + derived
/// aggregate types.
///
/// One [ImageRecord] = one load lifecycle of one mounted [BuoyImage] instance
/// for one source. If the instance switches source, the old record is
/// finalized (`mounted=false`) and a new one starts.
library;

/// Provider family that rendered the instance. Flutter has no rn/expo split
/// (RN's `ImageLib`), so this reports the underlying provider family instead —
/// shown in the row's badge in place of RN/EXPO.
enum ImageLib { network, cached, asset, file, memory, other }

/// Coarse classification of where the source points (RN `SourceKind`).
enum SourceKind { network, asset, file, data, other }

enum ImageStatus { pending, loading, loaded, error }

/// Where the decoded image came from (RN `CacheVerdict`). Flutter exposes no
/// per-load origin, so `disk`/`none`(network) is a heuristic — see README.
enum CacheVerdict { none, disk, memory }

String imageLibName(ImageLib lib) => lib.name;
String sourceKindName(SourceKind kind) => kind.name;
String imageStatusName(ImageStatus s) => s.name;

/// Physical-pixel size (decoded bitmap or needed pixels).
class ImageDimensions {
  const ImageDimensions(this.width, this.height);
  final int width;
  final int height;
  Map<String, Object?> toJson() => {'width': width, 'height': height};
}

/// A single captured image load. Mutated in place by the store and the capture
/// layer (records are owned by the store), mirroring the RN store.
class ImageRecord {
  ImageRecord({
    required this.id,
    required this.lib,
    required this.uri,
    required this.sourceKind,
    required this.createdAt,
  });

  final int id;
  final ImageLib lib;
  final String uri;
  final SourceKind sourceKind;

  ImageStatus status = ImageStatus.pending;

  /// False once the owning [BuoyImage] instance unmounted.
  bool mounted = true;

  /// ms epoch when the record was created (≈ instance mount).
  final int createdAt;

  /// ms epoch when native began working on the source (load start).
  int? startedAt;
  int? loadedAt;
  int? erroredAt;

  /// startedAt → loadedAt (falls back to createdAt → loadedAt).
  double? durationMs;

  /// Decoded bitmap size in physical pixels (from ImageInfo).
  ImageDimensions? intrinsic;

  /// Laid-out box size in logical px (measured post-frame).
  ImageDimensions? layout;

  /// Device pixel ratio captured with the layout measurement — the analog of
  /// RN's global `PixelRatio.get()`, but per-record so it stays correct across
  /// views. Feeds neededPixels (physical px the box needs to fill 1:1).
  double devicePixelRatio = 1.0;

  CacheVerdict? cacheVerdict;

  /// RN `cacheVerdictSource`: always 'queryCache' on Flutter (imageCache read).
  String? cacheVerdictSource;

  /// True if a real network fetch happened (Flutter: cache-miss network load).
  bool progressSeen = false;

  int? bytesLoaded;
  int? bytesTotal;

  String? error;

  /// From NetworkImageLoadException.statusCode when present.
  int? errorCode;
  Map<String, String>? errorHeaders;

  /// How many load cycles this record has seen (retries/reloads).
  int loadCount = 0;

  /// Set while a simulation override is active (e.g. "Forced error").
  String? overrideLabel;

  /// Whether the instance had a semanticLabel at last render.
  bool? hasAltText;

  /// Times the laid-out size changed AFTER the image loaded (CLS signal).
  int layoutShifts = 0;
}

/// Cross-record findings (RN `ImageInsights`).
class ImageInsights {
  const ImageInsights({
    required this.duplicates,
    required this.retryStorms,
    required this.queueSaturated,
    required this.missingAlt,
    required this.layoutShifters,
  });

  final List<({String uri, int count})> duplicates;
  final List<({int id, String uri, int loadCount})> retryStorms;
  final bool queueSaturated;
  final int missingAlt;
  final List<({int id, String uri, int shifts})> layoutShifters;

  Map<String, Object?> toJson() => {
    'duplicates': [
      for (final d in duplicates) {'uri': d.uri, 'count': d.count},
    ],
    'retryStorms': [
      for (final r in retryStorms)
        {'id': r.id, 'uri': r.uri, 'loadCount': r.loadCount},
    ],
    'queueSaturated': queueSaturated,
    'missingAlt': missingAlt,
    'layoutShifters': [
      for (final l in layoutShifters)
        {'id': l.id, 'uri': l.uri, 'shifts': l.shifts},
    ],
  };
}

/// Aggregate stats derived from the buffer (RN `ImageStats`).
class ImageStats {
  const ImageStats({
    required this.total,
    required this.loading,
    required this.loaded,
    required this.errors,
    required this.networkLoads,
    required this.estDecodedBytes,
    required this.estWastedBytes,
  });

  final int total;
  final int loading;
  final int loaded;
  final int errors;
  final int networkLoads;
  final int estDecodedBytes;
  final int estWastedBytes;

  Map<String, Object?> toJson() => {
    'total': total,
    'loading': loading,
    'loaded': loaded,
    'errors': errors,
    'networkLoads': networkLoads,
    'estDecodedBytes': estDecodedBytes,
    'estWastedBytes': estWastedBytes,
  };
}

/// Capture capability report (RN `CaptureStatus`). Flutter has no app-wide
/// decorator, so the rn/expo flags are always false — only `installed`
/// (BuoyImage in use) is meaningful.
class CaptureStatus {
  const CaptureStatus({required this.installed});
  final bool installed;

  Map<String, Object?> toJson() => {
    'installed': installed,
    'rnDecoratorActive': false,
    'rnDecoratorTooLate': false,
    'expoPatched': false,
    'expoAvailable': false,
  };
}
