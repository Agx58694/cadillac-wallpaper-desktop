import 'dart:io';

import 'package:image/image.dart' as img;

class ImageProbe {
  const ImageProbe({
    required this.path,
    required this.width,
    required this.height,
    required this.hasAlpha,
    required this.alphaMin,
    required this.alphaMax,
  });

  final String path;
  final int width;
  final int height;
  final bool hasAlpha;
  final int alphaMin;
  final int alphaMax;

  bool get isRequiredPreviewSize => width == 2198 && height == 367;
}

class ImageProbeService {
  Future<ImageProbe> inspect(String path) async {
    final bytes = await File(path).readAsBytes();
    final image = img.decodeImage(bytes);
    if (image == null) {
      throw FormatException('不是可读取的图片: $path');
    }

    var alphaMin = 255;
    var alphaMax = 255;
    if (image.hasAlpha) {
      alphaMin = 255;
      alphaMax = 0;
      for (final pixel in image) {
        final alpha = pixel.a.round();
        if (alpha < alphaMin) {
          alphaMin = alpha;
        }
        if (alpha > alphaMax) {
          alphaMax = alpha;
        }
      }
    }

    return ImageProbe(
      path: path,
      width: image.width,
      height: image.height,
      hasAlpha: image.hasAlpha,
      alphaMin: alphaMin,
      alphaMax: alphaMax,
    );
  }
}
