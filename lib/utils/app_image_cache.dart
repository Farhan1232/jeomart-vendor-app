import 'dart:async';

import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// The image cache every network image in the vendor app draws through.
///
/// ## The problem it solves
///
/// Firebase Storage serves every uploaded image on this project with
///
/// ```
/// cache-control: private, max-age=0
/// ```
///
/// `flutter_cache_manager` honours that header literally: it computes
/// `validTill = now + max-age`, so every photo is stale the instant it lands.
/// The file is still written to disk and still shown from disk on the next
/// visit - the picture is not slow to appear - but the manager also fetches it
/// again **every single time** it is displayed, to revalidate.
///
/// In this app that is every product photo on the Products tab, every customer
/// avatar on the order cards, every chat picture and every store photo, each
/// downloaded again on every visit. On mobile data those downloads compete with
/// the Firestore reads the same screen is waiting for. Measured on the customer
/// app in Session 23 at roughly 4 MB per screen entry.
///
/// ## What this changes
///
/// Nothing about which image is shown, its size, or its quality. Only how long a
/// downloaded copy is trusted:
///
/// * a real `max-age` from the server is still obeyed, unchanged;
/// * a **zero or missing** `max-age` - which is every image on this project - is
///   treated as [_assumedFreshness] instead of "already stale".
///
/// The `eTag` is passed through untouched, so once the period lapses the manager
/// still revalidates. A photo the vendor replaces is uploaded under a new
/// download URL, so it is a new cache entry and shows immediately.
///
/// Same class as the customer and driver apps.
class AppImageCache {
  AppImageCache._();

  /// Cache key for the manager's own store.
  static const String _cacheKey = 'jeomartVendorImageCache';

  /// How long a copy is trusted when the server declines to say.
  static const Duration _assumedFreshness = Duration(days: 7);

  /// How long an untouched file is kept before the store evicts it.
  static const Duration _stalePeriod = Duration(days: 30);

  /// The most files kept on disk at once.
  static const int _maxObjects = 800;

  static CacheManager? _instance;

  static CacheManager get manager {
    return _instance ??= CacheManager(Config(_cacheKey, stalePeriod: _stalePeriod, maxNrOfCacheObjects: _maxObjects, fileService: _FreshnessFloorFileService()));
  }

  /// Test seam. Lets a test install a manager without touching the disk.
  static set manager(CacheManager value) => _instance = value;

  /// The freshness a response should be given, given what the server said.
  ///
  /// Returns [serverValidTill] when the server asked for a future time, and
  /// `now + `[_assumedFreshness] when it asked for now or the past.
  static DateTime freshnessFor(DateTime serverValidTill, {DateTime? now}) {
    final at = now ?? DateTime.now();
    if (serverValidTill.isAfter(at)) return serverValidTill;
    return at.add(_assumedFreshness);
  }

  /// The width, in physical pixels, an image may be *decoded* at without ever
  /// being drawn larger than it was decoded - or `null` when no such bound is
  /// safe and the image must be decoded at full size, exactly as before.
  ///
  /// Photos on this project are full-size camera output (Session 23 measured
  /// 512x768 to 1152x768, one 1.8 MB file). Flutter decodes them to raw ARGB, so
  /// a 1152x768 photo holds about 3.5 MB of memory however small it is drawn,
  /// and a list of them overruns Flutter's 100 MB image cache - the cache then
  /// evicts, and the next scroll decodes the same pictures again. That is the
  /// stutter on long lists.
  ///
  /// A bound is only returned for fits where the drawn width can never exceed
  /// the widget's width, whatever the photo's shape:
  ///
  /// * `fitWidth` draws exactly the widget width (and it is the widget default);
  /// * `contain` and `scaleDown` draw at most the widget width.
  ///
  /// `cover`, `fill`, `fitHeight` and `none` can draw a photo wider than the
  /// widget (a wide photo in a square `cover` box, for one), so decoding to the
  /// widget width would blur them. Those get `null`.
  ///
  /// Aspect ratio is always preserved - only a width is ever given - and
  /// `ResizeImage` never enlarges, so a photo already smaller than the bound is
  /// decoded untouched.
  static int? decodeWidthFor({required double? width, required BoxFit? fit, required double devicePixelRatio}) {
    final BoxFit effectiveFit = fit ?? BoxFit.fitWidth;
    if (effectiveFit != BoxFit.fitWidth && effectiveFit != BoxFit.contain && effectiveFit != BoxFit.scaleDown) return null;
    if (width == null || !width.isFinite || width <= 0) return null;
    final double ratio = devicePixelRatio.isFinite && devicePixelRatio > 0 ? devicePixelRatio : 1.0;
    return (width * ratio).ceil();
  }
}

/// Wraps [HttpFileService] and raises a zero freshness to a usable one.
class _FreshnessFloorFileService extends FileService {
  _FreshnessFloorFileService() : _inner = HttpFileService();

  final HttpFileService _inner;

  @override
  Future<FileServiceResponse> get(String url, {Map<String, String>? headers}) async {
    final response = await _inner.get(url, headers: headers);
    return _FreshnessFloorResponse(response);
  }
}

/// Delegates everything to the real response except [validTill].
class _FreshnessFloorResponse implements FileServiceResponse {
  _FreshnessFloorResponse(this._inner);

  final FileServiceResponse _inner;

  @override
  Stream<List<int>> get content => _inner.content;

  @override
  int? get contentLength => _inner.contentLength;

  @override
  int get statusCode => _inner.statusCode;

  @override
  String? get eTag => _inner.eTag;

  @override
  String get fileExtension => _inner.fileExtension;

  @override
  DateTime get validTill => AppImageCache.freshnessFor(_inner.validTill);
}
