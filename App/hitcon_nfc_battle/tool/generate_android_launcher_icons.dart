import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

final _background = img.ColorRgb8(15, 0, 24);

const _densities = <String, int>{
  'mdpi': 48,
  'hdpi': 72,
  'xhdpi': 96,
  'xxhdpi': 144,
  'xxxhdpi': 192,
};

void main() {
  final sourceFile = File('assets/app_icon/app_icon_master.png');
  final source = img.decodePng(sourceFile.readAsBytesSync());
  if (source == null) {
    throw StateError('Unable to decode ${sourceFile.path}');
  }

  final foreground = _removeDarkBackground(source);
  final monochrome = _createMonochrome(source);
  for (final entry in _densities.entries) {
    _writeLegacyIcon(foreground, entry.key, entry.value);
    _writeAdaptiveForeground(foreground, entry.key, entry.value * 9 ~/ 4);
    _writeAdaptiveMonochrome(monochrome, entry.key, entry.value * 9 ~/ 4);
  }
}

img.Image _removeDarkBackground(img.Image source) {
  final result = img.Image(
    width: source.width,
    height: source.height,
    numChannels: 4,
  );

  for (final sourcePixel in source) {
    final brightness = math.max(
      sourcePixel.r.toInt(),
      math.max(sourcePixel.g.toInt(), sourcePixel.b.toInt()),
    );
    final alpha = ((brightness - 20) * 5).clamp(0, 255);
    final target = result.getPixel(sourcePixel.x, sourcePixel.y);
    target
      ..r = sourcePixel.r
      ..g = sourcePixel.g
      ..b = sourcePixel.b
      ..a = alpha;
  }
  return result;
}

img.Image _createMonochrome(img.Image source) {
  final result = img.Image(
    width: source.width,
    height: source.height,
    numChannels: 4,
  );

  for (final sourcePixel in source) {
    final brightness = math.max(
      sourcePixel.r.toInt(),
      math.max(sourcePixel.g.toInt(), sourcePixel.b.toInt()),
    );
    final alpha = ((brightness - 70) * 4).clamp(0, 255);
    final target = result.getPixel(sourcePixel.x, sourcePixel.y);
    target
      ..r = 255
      ..g = 255
      ..b = 255
      ..a = alpha;
  }
  return result;
}

void _writeLegacyIcon(img.Image foreground, String density, int size) {
  final canvas = img.Image(width: size, height: size, numChannels: 3);
  img.fill(canvas, color: _background);
  _centerForeground(canvas, foreground, scale: 0.74);
  _writePng('android/app/src/main/res/mipmap-$density/ic_launcher.png', canvas);
}

void _writeAdaptiveForeground(
  img.Image foreground,
  String density,
  int size,
) {
  final canvas = img.Image(width: size, height: size, numChannels: 4);
  img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));
  _centerForeground(canvas, foreground, scale: 0.62);
  _writePng(
    'android/app/src/main/res/mipmap-$density/ic_launcher_foreground.png',
    canvas,
  );
}

void _writeAdaptiveMonochrome(
  img.Image monochrome,
  String density,
  int size,
) {
  final canvas = img.Image(width: size, height: size, numChannels: 4);
  img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));
  _centerForeground(canvas, monochrome, scale: 0.62);
  _writePng(
    'android/app/src/main/res/mipmap-$density/ic_launcher_monochrome.png',
    canvas,
  );
}

void _centerForeground(img.Image canvas, img.Image foreground, {required double scale}) {
  final contentSize = (canvas.width * scale).round();
  final resized = img.copyResize(
    foreground,
    width: contentSize,
    height: contentSize,
    interpolation: img.Interpolation.cubic,
  );
  img.compositeImage(
    canvas,
    resized,
    dstX: (canvas.width - contentSize) ~/ 2,
    dstY: (canvas.height - contentSize) ~/ 2,
  );
}

void _writePng(String path, img.Image image) {
  final file = File(path)..parent.createSync(recursive: true);
  file.writeAsBytesSync(img.encodePng(image));
  stdout.writeln('Wrote $path (${image.width}x${image.height})');
}
