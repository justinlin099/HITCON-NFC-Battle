import 'dart:io';

import 'package:image/image.dart' as img;

void main() {
  const int size = 48;
  final img.Image image = img.Image(width: size, height: size);

  final int sky = img.ColorUint8.rgb(0x35, 0x5C, 0x7D);
  final int skyAccent = img.ColorUint8.rgb(0x6C, 0x8E, 0xBF);
  final int sun = img.ColorUint8.rgb(0xFF, 0xD5, 0x4F);
  final int backMountain = img.ColorUint8.rgb(0x3E, 0x4C, 0x59);
  final int frontMountain = img.ColorUint8.rgb(0x2D, 0x6A, 0x4F);
  final int ground = img.ColorUint8.rgb(0x1B, 0x43, 0x32);
  final int highlight = img.ColorUint8.rgb(0xFF, 0xAA, 0x00);

  for (int y = 0; y < 28; y++) {
    for (int x = 0; x < size; x++) {
      final bool accent = (x + y) % 6 == 0;
      image.setPixel(x, y, accent ? skyAccent : sky);
    }
  }

  const int sunX = 36;
  const int sunY = 9;
  const int sunR = 5;
  for (int y = -sunR; y <= sunR; y++) {
    for (int x = -sunR; x <= sunR; x++) {
      if (x * x + y * y <= sunR * sunR) {
        final int px = sunX + x;
        final int py = sunY + y;
        if (px >= 0 && px < size && py >= 0 && py < size) {
          image.setPixel(px, py, sun);
        }
      }
    }
  }

  for (int x = 4; x <= 28; x++) {
    final int peak = 18;
    final int height = (x <= 16) ? x - 4 : 28 - x;
    for (int y = 0; y <= height; y++) {
      image.setPixel(x, peak + y, backMountain);
    }
  }

  for (int x = 12; x <= 44; x++) {
    final int peak = 22;
    final int height = (x <= 28) ? x - 12 : 44 - x;
    for (int y = 0; y <= height; y++) {
      image.setPixel(x, peak + y, frontMountain);
    }
  }

  for (int y = 30; y < size; y++) {
    for (int x = 0; x < size; x++) {
      final bool accent = (x + y) % 5 == 0;
      image.setPixel(x, y, accent ? highlight : ground);
    }
  }

  final File output = File('assets/images/mock_card_48.png');
  output.createSync(recursive: true);
  output.writeAsBytesSync(img.encodePng(image));
}
