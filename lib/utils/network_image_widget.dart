import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:vendor/constant/constant.dart';
import 'package:vendor/themes/responsive.dart';
import 'package:vendor/utils/app_image_cache.dart';

class NetworkImageWidget extends StatelessWidget {
  final String imageUrl;
  final double? height;
  final double? width;
  final Widget? errorWidget;
  final BoxFit? fit;
  final double? borderRadius;
  final Color? color;

  final bool showShimmer;

  const NetworkImageWidget({super.key, this.height, this.width, this.fit, required this.imageUrl, this.borderRadius, this.errorWidget, this.color, this.showShimmer = true});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final w = width ?? Responsive.width(15, context);
    final h = height ?? Responsive.height(8, context);
    final double devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    // Through the app's own cache (see AppImageCache: Storage's max-age=0 made
    // every photo download again on every display), and decoded no larger than
    // it is drawn where that is provably safe.
    return CachedNetworkImage(
      imageUrl: imageUrl,
      cacheManager: AppImageCache.manager,
      memCacheWidth: AppImageCache.decodeWidthFor(width: w, fit: fit ?? BoxFit.fitWidth, devicePixelRatio: devicePixelRatio),
      fit: fit ?? BoxFit.fitWidth,
      height: h,
      width: w,
      color: color,
      placeholder: (context, url) => showShimmer
          ? Shimmer.fromColors(
              baseColor: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE0E0E0),
              highlightColor: isDark ? const Color(0xFF3A3A3A) : const Color(0xFFF5F5F5),
              child: Container(height: h, width: w, color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE0E0E0)),
            )
          : SizedBox(height: h, width: w),
      errorWidget: (context, url, error) =>
          errorWidget ??
          CachedNetworkImage(
            imageUrl: Constant.placeholderImage,
            cacheManager: AppImageCache.manager,
            memCacheWidth: AppImageCache.decodeWidthFor(width: w, fit: fit ?? BoxFit.cover, devicePixelRatio: devicePixelRatio),
            fit: fit ?? BoxFit.cover,
            height: h,
            width: w,
          ),
    );
  }
}
