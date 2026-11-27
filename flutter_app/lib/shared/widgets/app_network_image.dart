import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'full_screen_image_viewer.dart';

/// A network image sized and decoded for where it's actually shown, not at
/// its original resolution — every `Image.network(url, width: 56, height:
/// 56, ...)` call site in this app was decoding the full source image into
/// memory just to display it at a thumbnail size. `cacheWidth`/`cacheHeight`
/// tell Flutter's image codec to downsample at decode time instead, which is
/// both faster to render and much lighter on memory for a list/grid of
/// photos.
///
/// Tapping the image (when [onTapOpenFullScreen] is true, the default for
/// anything shown above thumbnail size) opens [FullScreenImageViewer], which
/// loads the same URL again without a cache size cap — so a thumbnail is
/// cheap, and the full-quality image is only ever decoded once the user
/// actually asks to see it bigger.
class AppNetworkImage extends StatelessWidget {
  final String url;
  final double width;
  final double height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final bool onTapOpenFullScreen;
  final Widget Function(BuildContext context)? errorBuilder;
  final String? heroTag;

  const AppNetworkImage({
    super.key,
    required this.url,
    required this.width,
    required this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.onTapOpenFullScreen = true,
    this.errorBuilder,
    this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    // Capped well above any realistic on-screen size so a tap-to-zoom still
    // looks sharp, without decoding at the source's full (often much
    // larger) resolution for a tile that's only ever shown small.
    final cacheWidth = math.min((width * dpr).round(), 1600);
    final cacheHeight = math.min((height * dpr).round(), 1600);

    Widget image = Image.network(
      url,
      width: width,
      height: height,
      fit: fit,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
      errorBuilder: (ctx, _, _) =>
          errorBuilder?.call(ctx) ??
          Container(
            width: width,
            height: height,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Icon(Icons.broken_image_outlined, size: 20, color: Colors.grey),
          ),
      loadingBuilder: (ctx, child, progress) {
        if (progress == null) return child;
        return SizedBox(
          width: width,
          height: height,
          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        );
      },
    );

    if (heroTag != null) image = Hero(tag: heroTag!, child: image);
    if (borderRadius != null) image = ClipRRect(borderRadius: borderRadius!, child: image);

    if (!onTapOpenFullScreen) return image;

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => FullScreenImageViewer(url: url, heroTag: heroTag),
          fullscreenDialog: true,
        ),
      ),
      child: image,
    );
  }
}
