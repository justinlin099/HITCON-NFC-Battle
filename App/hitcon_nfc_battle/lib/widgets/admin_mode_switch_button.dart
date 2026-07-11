import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

enum AdminModeTarget { adminTools, gameplay }

class AdminModeSwitchButton extends StatelessWidget {
  const AdminModeSwitchButton({
    super.key,
    required this.target,
    required this.color,
  });

  final AdminModeTarget target;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final bool opensAdmin = target == AdminModeTarget.adminTools;
    return IconButton(
      tooltip: context.l10n.tr(
        opensAdmin ? 'switchToAdminTools' : 'switchToGameplay',
      ),
      onPressed: () {
        Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil(
          opensAdmin ? '/admin' : '/collection',
          (Route<dynamic> route) => false,
          arguments: opensAdmin
              ? null
              : const <String, Object>{'fromAdminMode': true},
        );
      },
      icon: CustomPaint(
        size: const Size.square(28),
        painter: _PixelSwitchIconPainter(color),
      ),
    );
  }
}

class _PixelSwitchIconPainter extends CustomPainter {
  const _PixelSwitchIconPainter(this.color);

  final Color color;

  static const List<String> _pattern = <String>[
    '000000000100',
    '000000000110',
    '011111111111',
    '011111111111',
    '000000000110',
    '000000000100',
    '000000000000',
    '001000000000',
    '011000000000',
    '111111111110',
    '111111111110',
    '011000000000',
    '001000000000',
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final int rows = _pattern.length;
    final int columns = _pattern.first.length;
    final double cell = size.shortestSide / rows;
    final double left = (size.width - columns * cell) / 2;
    final Paint paint = Paint()
      ..color = color
      ..isAntiAlias = false;

    for (int y = 0; y < rows; y += 1) {
      for (int x = 0; x < columns; x += 1) {
        if (_pattern[y][x] == '1') {
          canvas.drawRect(
            Rect.fromLTWH(left + x * cell, y * cell, cell, cell),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_PixelSwitchIconPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
