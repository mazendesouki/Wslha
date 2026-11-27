import 'package:flutter/material.dart';

/// Opened by [AppNetworkImage] on tap — the "see it at real size and
/// quality" counterpart to the downsized thumbnails used everywhere else.
/// No cacheWidth/cacheHeight cap here: this is the one place the source
/// image is actually decoded at full resolution, and [InteractiveViewer]
/// lets the user pinch-zoom further if they want to check detail (a
/// product's condition, a document's fine print, a driver's face).
class FullScreenImageViewer extends StatelessWidget {
  final String url;
  final String? heroTag;

  const FullScreenImageViewer({super.key, required this.url, this.heroTag});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: Hero(
            tag: heroTag ?? url,
            child: Image.network(
              url,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const Padding(
                padding: EdgeInsets.all(24),
                child: Icon(Icons.broken_image_outlined, size: 48, color: Colors.white54),
              ),
              loadingBuilder: (_, child, progress) {
                if (progress == null) return child;
                return const Padding(
                  padding: EdgeInsets.all(48),
                  child: CircularProgressIndicator(color: Colors.white),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
