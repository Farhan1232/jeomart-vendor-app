import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// An image decoded no larger than it needs to be to fill a box of a known
/// size - and never smaller.
///
/// ## Why
///
/// The image previews on the add/edit forms (product, store, dine-in, coupon,
/// story, advert, profile, verification documents) draw a photo the vendor has
/// just picked into a small box - most of them 80 x 80. Picked photos are
/// camera originals: a 12 MP photo decodes to about 48 MB of pixels, all of it
/// for an 80-point square, and the decode happens on the frame right after the
/// picker closes.
///
/// ## Why it is never blurry
///
/// The decode size is chosen from the photo's real dimensions: it is scaled
/// down, keeping its shape, only until its **smaller** side still covers the
/// box at the screen's pixel density. So whichever way the photo is fitted into
/// the box - `cover`, `fill`, `contain`, `fitWidth` - there are always at least
/// as many pixels as are drawn. A photo already smaller than that is decoded as
/// it is. Only the decoded copy is affected: the file that is uploaded is the
/// picked file, untouched.
@immutable
class BoxSizedImage extends ImageProvider<BoxSizedImageKey> {
  const BoxSizedImage(this.imageProvider, {required this.width, required this.height});

  /// The image to decode.
  final ImageProvider imageProvider;

  /// The box, in physical pixels.
  final int width;
  final int height;

  /// [provider] sized for a box of [width] x [height] logical pixels on this
  /// screen, or [provider] itself when the box has no usable size.
  static ImageProvider forBox(BuildContext context, ImageProvider provider, {required double width, required double height}) {
    if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0) return provider;
    final double ratio = MediaQuery.devicePixelRatioOf(context);
    return BoxSizedImage(provider, width: (width * ratio).ceil(), height: (height * ratio).ceil());
  }

  /// The decode size for an image of [imageWidth] x [imageHeight] drawn into a
  /// [boxWidth] x [boxHeight] box: the image's own shape, with both sides at
  /// least the box's. An empty size means "decode as it is".
  static ui.TargetImageSize targetSize(int imageWidth, int imageHeight, int boxWidth, int boxHeight) {
    if (imageWidth <= 0 || imageHeight <= 0) return const ui.TargetImageSize();
    final double scale = math.max(boxWidth / imageWidth, boxHeight / imageHeight);
    if (scale >= 1) return const ui.TargetImageSize();
    return ui.TargetImageSize(width: math.max(1, (imageWidth * scale).ceil()), height: math.max(1, (imageHeight * scale).ceil()));
  }

  @override
  Future<BoxSizedImageKey> obtainKey(ImageConfiguration configuration) {
    // Completes synchronously when the wrapped provider does (a file does), the
    // same way Flutter's ResizeImage does, so the image resolves on the same
    // frame it would have without this wrapper.
    Completer<BoxSizedImageKey>? completer;
    SynchronousFuture<BoxSizedImageKey>? result;
    imageProvider.obtainKey(configuration).then((Object key) {
      final BoxSizedImageKey sized = BoxSizedImageKey._(key, width, height);
      if (completer == null) {
        result = SynchronousFuture<BoxSizedImageKey>(sized);
      } else {
        completer.complete(sized);
      }
    });
    if (result != null) return result!;
    completer = Completer<BoxSizedImageKey>();
    return completer.future;
  }

  @override
  ImageStreamCompleter loadImage(BoxSizedImageKey key, ImageDecoderCallback decode) {
    Future<ui.Codec> decodeForBox(ui.ImmutableBuffer buffer, {ui.TargetImageSizeCallback? getTargetSize}) {
      return decode(buffer, getTargetSize: (int imageWidth, int imageHeight) => targetSize(imageWidth, imageHeight, key._width, key._height));
    }

    return imageProvider.loadImage(key._providerKey, decodeForBox);
  }
}

@immutable
class BoxSizedImageKey {
  const BoxSizedImageKey._(this._providerKey, this._width, this._height);

  final Object _providerKey;
  final int _width;
  final int _height;

  @override
  bool operator ==(Object other) {
    return other is BoxSizedImageKey && other._providerKey == _providerKey && other._width == _width && other._height == _height;
  }

  @override
  int get hashCode => Object.hash(_providerKey, _width, _height);
}
