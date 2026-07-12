import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

img.Image? _decodeImage(Uint8List bytes) => img.decodeImage(bytes);

void main() {
  test('decoded image can return from a background isolate', () async {
    final img.Image source = img.Image(width: 2, height: 2);
    final Uint8List bytes = Uint8List.fromList(img.encodePng(source));
    final img.Image? decoded = await compute(_decodeImage, bytes);

    expect(decoded, isNotNull);
    expect(decoded!.width, 2);
    expect(decoded.height, 2);
  });
}
