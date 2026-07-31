import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hitcon_nfc_battle/pages/user/default_avatar_catalog.dart';
import 'package:image/image.dart' as img;

void main() {
  test('default avatar catalog contains valid square PNG assets', () {
    final Set<String> paths = <String>{};

    for (final DefaultAvatarOption option in defaultAvatarCatalog) {
      expect(paths.add(option.assetPath), isTrue);
      expect(option.labelKey, isNotEmpty);

      final File asset = File(option.assetPath);
      expect(asset.existsSync(), isTrue, reason: option.assetPath);

      final img.Image? decoded = img.decodePng(asset.readAsBytesSync());
      expect(decoded, isNotNull, reason: option.assetPath);
      expect(decoded!.width, 512, reason: option.assetPath);
      expect(decoded.height, 512, reason: option.assetPath);
    }
  });
}
