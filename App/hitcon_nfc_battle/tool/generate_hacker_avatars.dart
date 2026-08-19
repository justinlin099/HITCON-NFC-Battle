import 'dart:io';

import 'package:image/image.dart' as img;

const int _size = 48;

void main() {
  final Directory output = Directory('assets/images/default_avatars');
  _write(output, 'hacker_dragon.png', _dragon());
  _write(output, 'hacker_rabbit.png', _rabbit());
}

void _write(Directory output, String name, img.Image source) {
  final img.Image scaled = img.copyResize(
    source,
    width: 512,
    height: 512,
    interpolation: img.Interpolation.nearest,
  );
  File('${output.path}/$name').writeAsBytesSync(img.encodePng(scaled));
}

img.Image _dragon() {
  final img.Image image = _loadAvatarGrid(
    'assets/images/default_avatars/hacker_cat_orange_tabby.png',
  );

  // Keep the original cat shading, hoodie, outlines, and continuous visor.
  // Only warm head pixels are shifted into a red dragon palette.
  for (int y = 3; y <= 38; y += 1) {
    for (int x = 8; x <= 40; x += 1) {
      final img.Pixel pixel = image.getPixel(x, y);
      final int red = pixel.r.toInt();
      final int green = pixel.g.toInt();
      final int blue = pixel.b.toInt();
      final bool warmFur =
          red > 145 && green >= 45 && green < 195 && blue < 110;
      if (!warmFur) {
        continue;
      }
      final int replacement = green > 145
          ? 0xFFFF7766
          : green > 95
          ? 0xFFE84444
          : 0xFF9E1D31;
      _pixel(image, x, y, replacement);
    }
  }

  // Dragon-specific silhouette and face details are layered over the cat base.
  _rect(image, 12, 3, 14, 7, 0xFFD89132);
  _rect(image, 13, 2, 16, 4, 0xFFFFC857);
  _rect(image, 14, 2, 16, 2, 0xFFFFE29A);
  _rect(image, 33, 3, 35, 7, 0xFFD89132);
  _rect(image, 31, 2, 34, 4, 0xFFFFC857);
  _rect(image, 31, 2, 33, 2, 0xFFFFE29A);
  _rect(image, 7, 15, 10, 17, 0xFFFF6659);
  _rect(image, 5, 18, 9, 20, 0xFF9E1D31);
  _rect(image, 38, 15, 41, 17, 0xFFFF6659);
  _rect(image, 39, 18, 43, 20, 0xFF9E1D31);

  _rect(image, 16, 27, 31, 32, 0xFFFF9B7D);
  _rect(image, 19, 28, 22, 30, 0xFFFFB093);
  _rect(image, 26, 28, 29, 30, 0xFFFFB093);
  _rect(image, 20, 28, 21, 29, 0xFF5F1424);
  _rect(image, 27, 28, 28, 29, 0xFF5F1424);
  _rect(image, 21, 32, 26, 33, 0xFF5F1424);
  _rect(image, 18, 31, 20, 33, 0xFFFFFFFF);
  _rect(image, 28, 31, 30, 33, 0xFFFFFFFF);
  _rect(image, 16, 10, 18, 12, 0xFFFF7766);
  _rect(image, 29, 10, 31, 12, 0xFFFF7766);

  return image;
}

img.Image _rabbit() {
  final img.Image image = _loadAvatarGrid(
    'assets/images/default_avatars/hacker_cat.png',
  );

  // Preserve the source cat's hoodie and line work verbatim, then reshape only
  // the animal head into a white rabbit.
  _rect(image, 10, 2, 11, 18, 0xFF001933);
  _rect(image, 36, 2, 37, 18, 0xFF001933);
  _rect(image, 12, 2, 18, 20, 0xFFF7F7F7);
  _rect(image, 15, 4, 17, 16, 0xFFFFA8CB);
  _rect(image, 29, 2, 35, 20, 0xFFF7F7F7);
  _rect(image, 30, 4, 32, 16, 0xFFFFA8CB);

  _rect(image, 19, 10, 28, 18, 0xFF001933);
  _rect(image, 15, 19, 32, 21, 0xFFE1E4E8);
  _rect(image, 10, 19, 11, 27, 0xFF171B24);
  _rect(image, 36, 19, 37, 27, 0xFF171B24);
  _rect(image, 38, 19, 38, 27, 0xFF001933);
  _rect(image, 12, 21, 35, 31, 0xFFE1E4E8);
  _rect(image, 14, 20, 33, 25, 0xFFF7F7F7);
  _rect(image, 11, 25, 36, 32, 0xFFF7F7F7);
  _rect(image, 13, 31, 34, 35, 0xFFFFFFFF);
  _rect(image, 17, 35, 30, 37, 0xFFFFFFFF);

  // No nose, mouth, mouth line, or teeth. Keep only sleepy dash eyes.
  _rect(image, 14, 29, 20, 30, 0xFF171B24);
  _rect(image, 28, 29, 34, 30, 0xFF171B24);

  return image;
}

img.Image _loadAvatarGrid(String assetPath) {
  final img.Image source = img.decodePng(File(assetPath).readAsBytesSync())!;
  return img.copyResize(
    source,
    width: _size,
    height: _size,
    interpolation: img.Interpolation.nearest,
  );
}

void _pixel(img.Image image, int x, int y, int argb) {
  final int alpha = (argb >> 24) & 0xFF;
  final int red = (argb >> 16) & 0xFF;
  final int green = (argb >> 8) & 0xFF;
  final int blue = argb & 0xFF;
  image.setPixelRgba(x, y, red, green, blue, alpha);
}

void _rect(
  img.Image image,
  int left,
  int top,
  int right,
  int bottom,
  int argb,
) {
  for (int y = top; y <= bottom; y += 1) {
    for (int x = left; x <= right; x += 1) {
      _pixel(image, x, y, argb);
    }
  }
}
