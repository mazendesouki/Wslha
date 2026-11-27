import 'dart:typed_data';
import 'package:flutter_image_compress/flutter_image_compress.dart';

/// Converts a picked photo's bytes to WebP before it's uploaded, so every
/// image this app stores takes noticeably less storage/bandwidth than the
/// JPEG/PNG the camera or gallery produced — without a visible quality
/// drop, since quality 90 and keeping the original dimensions (minWidth/
/// minHeight set high enough that nothing gets downscaled here; display-
/// time sizing is handled separately by AppNetworkImage/ResizeImage on the
/// read side) make this a format change, not a compression pass.
///
/// Returns the original bytes/extension unchanged if conversion fails for
/// any reason (an unusual source format, a platform codec issue) — a
/// failed optimization must never block the upload itself.
class ImageUploadResult {
  final Uint8List bytes;
  final String fileExt;
  const ImageUploadResult(this.bytes, this.fileExt);
}

Future<ImageUploadResult> toWebpForUpload(Uint8List bytes, String originalExt, {int quality = 90}) async {
  try {
    final converted = await FlutterImageCompress.compressWithList(
      bytes,
      quality: quality,
      format: CompressFormat.webp,
      // High enough that no real photo from a phone camera/gallery picker
      // gets downscaled here — this step is only changing the encoding,
      // not resizing.
      minWidth: 4096,
      minHeight: 4096,
    );
    if (converted.isEmpty) return ImageUploadResult(bytes, originalExt);
    return ImageUploadResult(converted, 'webp');
  } catch (_) {
    return ImageUploadResult(bytes, originalExt);
  }
}
