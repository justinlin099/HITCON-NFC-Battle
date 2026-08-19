import 'package:flutter/material.dart';

class PixelLinkIcon extends StatelessWidget {
  const PixelLinkIcon({super.key, required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _PixelLinkIconPainter(color)),
    );
  }
}

class _PixelLinkIconPainter extends CustomPainter {
  const _PixelLinkIconPainter(this.color);

  final Color color;

  static const List<String> _pattern = <String>[
    '000000011111110000000',
    '000001101010101100000',
    '000010001010100010000',
    '000101111111111101000',
    '001010010010010010100',
    '010010010010010010010',
    '011111111111111111110',
    '100100100010001001001',
    '100100100010001001001',
    '100100100010001001001',
    '111111111111111111111',
    '100100100010001001001',
    '100100100010001001001',
    '100100100010001001001',
    '011111111111111111110',
    '010010010010010010010',
    '001010010010010010100',
    '000101111111111101000',
    '000010001010100010000',
    '000001101010101100000',
    '000000011111110000000',
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final int rows = _pattern.length;
    final int cols = _pattern.first.length;
    final double cell = size.shortestSide / cols;
    final double offsetX = (size.width - cell * cols) / 2;
    final double offsetY = (size.height - cell * rows) / 2;

    for (int y = 0; y < rows; y += 1) {
      final String row = _pattern[y];
      for (int x = 0; x < cols; x += 1) {
        if (row.codeUnitAt(x) != 49) {
          continue;
        }
        canvas.drawRect(
          Rect.fromLTWH(offsetX + x * cell, offsetY + y * cell, cell, cell),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PixelLinkIconPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
