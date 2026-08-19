import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'pixel_theme.dart';

enum NfcScanTransitionPhase { detected, verifying, syncing, ready }

class NfcScanTransition extends StatefulWidget {
  const NfcScanTransition({
    super.key,
    required this.phase,
    required this.label,
  });

  final NfcScanTransitionPhase phase;
  final String label;

  @override
  State<NfcScanTransition> createState() => _NfcScanTransitionState();
}

class _NfcScanTransitionState extends State<NfcScanTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Offset _pointer = const Offset(0.5, 0.5);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ColoredBox(
        color: PixelTheme.bgDark.withValues(alpha: 0.97),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanDown: (DragDownDetails details) =>
                    _updatePointer(details.localPosition, constraints.biggest),
                onPanUpdate: (DragUpdateDetails details) =>
                    _updatePointer(details.localPosition, constraints.biggest),
                onTapDown: (TapDownDetails details) =>
                    _updatePointer(details.localPosition, constraints.biggest),
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (BuildContext context, Widget? child) {
                    return _buildFrame(constraints.biggest, _controller.value);
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildFrame(Size size, double progress) {
    const double cardRatio = 53.98 / 85.60;
    double cardWidth = math.min(size.width * 0.5, 230);
    double cardHeight = cardWidth / cardRatio;
    final double maxCardHeight = size.height * 0.52;
    if (cardHeight > maxCardHeight) {
      cardHeight = maxCardHeight;
      cardWidth = cardHeight * cardRatio;
    }

    final double tiltY = (_pointer.dx - 0.5) * 0.34;
    final double tiltX = -(_pointer.dy - 0.5) * 0.24;
    final double scanPosition = Curves.easeInOut.transform(progress);
    final int activeSignal = switch (widget.phase) {
      NfcScanTransitionPhase.detected => 1,
      NfcScanTransitionPhase.verifying => 2,
      NfcScanTransitionPhase.syncing => 3,
      NfcScanTransitionPhase.ready => 4,
    };

    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: CustomPaint(
            painter: _ScannerFieldPainter(
              progress: progress,
              pointer: _pointer,
              phase: widget.phase,
              color: PixelTheme.accent,
            ),
          ),
        ),
        Align(
          alignment: const Alignment(0, -0.83),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'NFC',
                style: TextStyle(
                  color: PixelTheme.accent,
                  fontFamily: 'Unifont',
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 10),
              for (int index = 0; index < 4; index += 1) ...<Widget>[
                Container(
                  width: 13,
                  height: 8 + index * 3,
                  alignment: Alignment.bottomCenter,
                  color: index < activeSignal
                      ? PixelTheme.accent
                      : PixelTheme.textGray.withValues(alpha: 0.35),
                ),
                if (index != 3) const SizedBox(width: 4),
              ],
            ],
          ),
        ),
        Center(
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0018)
              ..rotateX(tiltX)
              ..rotateY(tiltY),
            child: Container(
              width: cardWidth,
              height: cardHeight,
              decoration: BoxDecoration(
                color: PixelTheme.bgMid,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: PixelTheme.accent, width: 3),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: PixelTheme.accent.withValues(alpha: 0.22),
                    blurRadius: 0,
                    offset: const Offset(7, 7),
                  ),
                ],
              ),
              clipBehavior: Clip.hardEdge,
              child: CustomPaint(
                painter: _CardScannerPainter(
                  progress: progress,
                  scanPosition: scanPosition,
                  color: PixelTheme.accent,
                  ready: widget.phase == NfcScanTransitionPhase.ready,
                ),
              ),
            ),
          ),
        ),
        Align(
          alignment: const Alignment(0, 0.84),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (Widget child, Animation<double> animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.25),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: Text(
                widget.label,
                key: ValueKey<NfcScanTransitionPhase>(widget.phase),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: widget.phase == NfcScanTransitionPhase.ready
                      ? PixelTheme.textWhite
                      : PixelTheme.accent,
                  fontFamily: 'Unifont',
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _updatePointer(Offset position, Size size) {
    if (size.width <= 0 || size.height <= 0) {
      return;
    }
    setState(() {
      _pointer = Offset(
        (position.dx / size.width).clamp(0.0, 1.0),
        (position.dy / size.height).clamp(0.0, 1.0),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class _ScannerFieldPainter extends CustomPainter {
  const _ScannerFieldPainter({
    required this.progress,
    required this.pointer,
    required this.phase,
    required this.color,
  });

  final double progress;
  final Offset pointer;
  final NfcScanTransitionPhase phase;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint gridPaint = Paint()
      ..color = color.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    const double grid = 24;
    for (double x = 0; x <= size.width; x += grid) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y <= size.height; y += grid) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final Offset target = Offset(
      size.width * (0.42 + pointer.dx * 0.16),
      size.height * (0.42 + pointer.dy * 0.16),
    );
    final Paint pixelPaint = Paint()..color = color;
    for (int index = 0; index < 26; index += 1) {
      final double seedX = ((index * 47) % 101) / 100;
      final double seedY = ((index * 73) % 97) / 96;
      final double staggered = (progress + index * 0.071) % 1;
      final double travel = Curves.easeIn.transform(staggered);
      final Offset start = Offset(seedX * size.width, seedY * size.height);
      final Offset point = Offset.lerp(start, target, travel)!;
      final double pixel = index.isEven ? 3 : 5;
      pixelPaint.color = color.withValues(alpha: (1 - travel) * 0.58);
      canvas.drawRect(
        Rect.fromLTWH(
          (point.dx / pixel).round() * pixel,
          (point.dy / pixel).round() * pixel,
          pixel,
          pixel,
        ),
        pixelPaint,
      );
    }

    final double pulse = (progress * 3) % 1;
    final double inset = 18 + pulse * math.min(size.width, size.height) * 0.13;
    final Paint bracketPaint = Paint()
      ..color = color.withValues(alpha: (1 - pulse) * 0.38)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final Rect pulseRect = Rect.fromLTRB(
      inset,
      inset,
      size.width - inset,
      size.height - inset,
    );
    _drawCorners(canvas, pulseRect, 18, bracketPaint);
  }

  void _drawCorners(Canvas canvas, Rect rect, double length, Paint paint) {
    canvas.drawLine(rect.topLeft, rect.topLeft + Offset(length, 0), paint);
    canvas.drawLine(rect.topLeft, rect.topLeft + Offset(0, length), paint);
    canvas.drawLine(rect.topRight, rect.topRight + Offset(-length, 0), paint);
    canvas.drawLine(rect.topRight, rect.topRight + Offset(0, length), paint);
    canvas.drawLine(
      rect.bottomLeft,
      rect.bottomLeft + Offset(length, 0),
      paint,
    );
    canvas.drawLine(
      rect.bottomLeft,
      rect.bottomLeft + Offset(0, -length),
      paint,
    );
    canvas.drawLine(
      rect.bottomRight,
      rect.bottomRight + Offset(-length, 0),
      paint,
    );
    canvas.drawLine(
      rect.bottomRight,
      rect.bottomRight + Offset(0, -length),
      paint,
    );
  }

  @override
  bool shouldRepaint(_ScannerFieldPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.pointer != pointer ||
        oldDelegate.phase != phase ||
        oldDelegate.color != color;
  }
}

class _CardScannerPainter extends CustomPainter {
  const _CardScannerPainter({
    required this.progress,
    required this.scanPosition,
    required this.color,
    required this.ready,
  });

  final double progress;
  final double scanPosition;
  final Color color;
  final bool ready;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint dimPaint = Paint()
      ..color = PixelTheme.bgDark.withValues(alpha: 0.78);
    canvas.drawRect(Offset.zero & size, dimPaint);

    final Paint patternPaint = Paint();
    const int columns = 12;
    const int rows = 18;
    final double cellWidth = size.width / columns;
    final double cellHeight = size.height / rows;
    for (int row = 1; row < rows - 1; row += 1) {
      for (int column = 1; column < columns - 1; column += 1) {
        final bool active = ((row * 11 + column * 7) % 9) < 3;
        if (!active) {
          continue;
        }
        final double wave =
            (math.sin(progress * math.pi * 2 + row * 0.42 + column) + 1) / 2;
        patternPaint.color = color.withValues(alpha: 0.08 + wave * 0.2);
        canvas.drawRect(
          Rect.fromLTWH(
            column * cellWidth + cellWidth * 0.28,
            row * cellHeight + cellHeight * 0.3,
            math.max(2, cellWidth * 0.36),
            math.max(2, cellHeight * 0.34),
          ),
          patternPaint,
        );
      }
    }

    final double lineY = size.height * (0.08 + scanPosition * 0.84);
    canvas.drawRect(
      Rect.fromLTWH(0, lineY - 10, size.width, 20),
      Paint()..color = color.withValues(alpha: 0.08),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, lineY - 2, size.width, 4),
      Paint()..color = ready ? Colors.white : color,
    );

    final Paint cornerPaint = Paint()
      ..color = ready ? Colors.white : color
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;
    const double inset = 14;
    final Rect frame = Rect.fromLTRB(
      inset,
      inset,
      size.width - inset,
      size.height - inset,
    );
    const double corner = 24;
    canvas.drawLine(
      frame.topLeft,
      frame.topLeft + const Offset(corner, 0),
      cornerPaint,
    );
    canvas.drawLine(
      frame.topLeft,
      frame.topLeft + const Offset(0, corner),
      cornerPaint,
    );
    canvas.drawLine(
      frame.topRight,
      frame.topRight + const Offset(-corner, 0),
      cornerPaint,
    );
    canvas.drawLine(
      frame.topRight,
      frame.topRight + const Offset(0, corner),
      cornerPaint,
    );
    canvas.drawLine(
      frame.bottomLeft,
      frame.bottomLeft + const Offset(corner, 0),
      cornerPaint,
    );
    canvas.drawLine(
      frame.bottomLeft,
      frame.bottomLeft + const Offset(0, -corner),
      cornerPaint,
    );
    canvas.drawLine(
      frame.bottomRight,
      frame.bottomRight + const Offset(-corner, 0),
      cornerPaint,
    );
    canvas.drawLine(
      frame.bottomRight,
      frame.bottomRight + const Offset(0, -corner),
      cornerPaint,
    );

    if (ready) {
      final Offset center = size.center(Offset.zero);
      final Paint readyPaint = Paint()
        ..color = Colors.white
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.square
        ..style = PaintingStyle.stroke;
      final Path check = Path()
        ..moveTo(center.dx - 32, center.dy)
        ..lineTo(center.dx - 8, center.dy + 24)
        ..lineTo(center.dx + 38, center.dy - 28);
      canvas.drawPath(check, readyPaint);
    }
  }

  @override
  bool shouldRepaint(_CardScannerPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.scanPosition != scanPosition ||
        oldDelegate.color != color ||
        oldDelegate.ready != ready;
  }
}
