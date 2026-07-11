import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'pixel_theme.dart';
import 'pixel_card_face.dart';
import 'pixel_link_dialog.dart';
import 'pixel_link_icon.dart';

class CardDetailPage extends StatefulWidget {
  const CardDetailPage({
    super.key,
    required this.heroTag,
    required this.title,
    required this.attributeEmoji,
    required this.attributeLabel,
    required this.link,
    required this.description,
    required this.uid,
    required this.collectedAt,
    required this.cardColor,
    required this.imageAsset,
    this.imageBase64,
    this.playRevealEffect = false,
    this.showCollectionInfo = true,
  });

  final String heroTag;
  final String title;
  final String attributeEmoji;
  final String attributeLabel;
  final String link;
  final String description;
  final String uid;
  final String collectedAt;
  final Color cardColor;
  final String imageAsset;
  final String? imageBase64;
  final bool playRevealEffect;
  final bool showCollectionInfo;

  @override
  State<CardDetailPage> createState() => _CardDetailPageState();
}

class _CardDetailPageState extends State<CardDetailPage> {
  static const Duration _textDelay = Duration(milliseconds: 450);
  static const double _dismissVelocity = 350;

  bool _showText = false;
  Uint8List? _imageBytes;

  @override
  void initState() {
    super.initState();
    _imageBytes = _decodeImageBytes(widget.imageBase64);
    Future<void>.delayed(_textDelay, () {
      if (mounted) {
        setState(() {
          _showText = true;
        });
      }
    });
  }

  @override
  void didUpdateWidget(covariant CardDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageBase64 != widget.imageBase64) {
      _imageBytes = _decodeImageBytes(widget.imageBase64);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData base = Theme.of(context);
    final ThemeData pixelTheme = base.copyWith(
      textTheme: base.textTheme.apply(fontFamily: 'Unifont'),
      primaryTextTheme: base.primaryTextTheme.apply(fontFamily: 'Unifont'),
    );

    return Theme(
      data: pixelTheme,
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.of(context).maybePop(),
                child: Container(
                  color: PixelTheme.bgDark.withValues(alpha: 0.75),
                ),
              ),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const double ratio =
                      53.98 / 85.60; // portrait credit-card ratio
                  final double maxWidth = constraints.maxWidth - 24;
                  final double maxHeight = constraints.maxHeight - 24;
                  double cardWidth = maxWidth;
                  double cardHeight = cardWidth / ratio;

                  if (cardHeight > maxHeight) {
                    cardHeight = maxHeight;
                    cardWidth = cardHeight * ratio;
                  }

                  final double contentPad = (cardWidth * 0.06).clamp(6.0, 16.0);
                  final double scale = (cardWidth / 320).clamp(0.85, 1.1);
                  double s(double value) => value * scale;

                  return Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Hero(
                            tag: widget.heroTag,
                            child: Material(
                              color: Colors.transparent,
                              child: _TiltableDetailCard(
                                width: cardWidth,
                                height: cardHeight,
                                dismissVelocity: _dismissVelocity,
                                onDismiss: () =>
                                    Navigator.of(context).maybePop(),
                                child: PixelCardFace(
                                  title: widget.title,
                                  attributeEmoji: widget.attributeEmoji,
                                  attributeLabel: widget.attributeLabel,
                                  cardColor: widget.cardColor,
                                  showText: _showText,
                                  titleFontSize: s(22),
                                  titleFontWeight: FontWeight.w900,
                                  attributeFontSize: s(12),
                                  emojiFontSize: s(16),
                                  titleMaxLines: 2,
                                  watermarkScale: 1.6,
                                  imageToTitleSpacing: s(8),
                                  extraContentSpacing: s(8),
                                  image: _cardImage(),
                                  fixedContent: _LinkRow(
                                    link: widget.link,
                                    fontSize: s(10),
                                    onTap: widget.link.trim().isEmpty
                                        ? null
                                        : () => confirmAndOpenLink(
                                            context,
                                            widget.link,
                                          ),
                                  ),
                                  extraContent: _CardDescription(
                                    description: widget.description,
                                    fontSize: s(13),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (widget.showCollectionInfo) ...<Widget>[
                            SizedBox(height: s(10)),
                            SizedBox(
                              width: cardWidth,
                              child: _InfoCard(
                                uid: widget.uid,
                                collectedAt: _formatDate(widget.collectedAt),
                                padding: EdgeInsets.all(contentPad),
                                fontSize: s(12),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            if (widget.playRevealEffect)
              Positioned.fill(
                child: IgnorePointer(
                  child: _CardRevealEffect(cardColor: widget.cardColor),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatDate(String raw) {
    if (raw.isEmpty) {
      return context.l10n.tr('unknown');
    }
    return raw.length >= 10 ? raw.substring(0, 10) : raw;
  }

  Widget _cardImage() {
    final Uint8List? bytes = _imageBytes;
    if (bytes != null) {
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.none,
        gaplessPlayback: true,
      );
    }
    return Container(
      color: PixelTheme.bgDark,
      alignment: Alignment.center,
      child: Icon(Icons.person_rounded, color: PixelTheme.accent, size: 48),
    );
  }

  Uint8List? _decodeImageBytes(String? raw) {
    final String value = raw?.trim() ?? '';
    if (value.isEmpty) {
      return null;
    }
    final String payload = value.contains(',') ? value.split(',').last : value;
    try {
      return base64Decode(payload);
    } catch (_) {
      return null;
    }
  }
}

class _CardRevealEffect extends StatefulWidget {
  const _CardRevealEffect({required this.cardColor});

  final Color cardColor;

  @override
  State<_CardRevealEffect> createState() => _CardRevealEffectState();
}

class _CardRevealEffectState extends State<_CardRevealEffect>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..forward();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        return CustomPaint(
          painter: _SparkleBurstPainter(
            progress: _controller.value,
            cardColor: widget.cardColor,
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class _SparkleBurstPainter extends CustomPainter {
  const _SparkleBurstPainter({required this.progress, required this.cardColor});

  final double progress;
  final Color cardColor;

  static const List<double> _distanceFactors = <double>[
    0.82,
    1.14,
    0.96,
    1.28,
    0.74,
    1.08,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final double travel = Curves.easeOutCubic.transform(
      (progress / 0.82).clamp(0.0, 1.0),
    );
    final double opacity = (1 - Curves.easeIn.transform(progress)).clamp(
      0.0,
      1.0,
    );
    final Offset center = Offset(size.width / 2, size.height * 0.44);

    final double flashOpacity = (1 - progress * 5).clamp(0.0, 1.0) * 0.24;
    if (flashOpacity > 0) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = Colors.white.withValues(alpha: flashOpacity),
      );
    }

    final List<Color> colors = <Color>[
      Colors.white,
      const Color(0xFFFFE45C),
      const Color(0xFF54F5FF),
      cardColor,
    ];
    final double maxTravel = math.min(size.width, size.height) * 0.43;
    for (int index = 0; index < 24; index += 1) {
      final double angle =
          (math.pi * 2 * index / 24) + (index.isOdd ? 0.09 : -0.05);
      final double factor = _distanceFactors[index % _distanceFactors.length];
      final double radius = 24 + maxTravel * travel * factor;
      final Offset position =
          center +
          Offset(math.cos(angle) * radius, math.sin(angle) * radius * 1.12);
      final double twinkle = math.sin(
        math.pi * ((progress * 2.15 + index * 0.17) % 1),
      );
      final double sparkleSize =
          (4 + (index % 4) * 1.8) * twinkle.clamp(0.25, 1.0) * opacity;
      if (sparkleSize < 0.8) {
        continue;
      }
      _drawPixelSparkle(
        canvas,
        position,
        sparkleSize,
        colors[index % colors.length].withValues(alpha: opacity),
      );
    }
  }

  void _drawPixelSparkle(
    Canvas canvas,
    Offset center,
    double size,
    Color color,
  ) {
    final double pixel = math.max(2, (size * 0.28).roundToDouble());
    final Paint paint = Paint()..color = color;
    canvas.drawRect(
      Rect.fromCenter(center: center, width: pixel, height: size * 2.3),
      paint,
    );
    canvas.drawRect(
      Rect.fromCenter(center: center, width: size * 2.3, height: pixel),
      paint,
    );
    canvas.drawRect(
      Rect.fromCenter(center: center, width: pixel * 1.7, height: pixel * 1.7),
      Paint()..color = Colors.white.withValues(alpha: color.a),
    );
  }

  @override
  bool shouldRepaint(_SparkleBurstPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.cardColor != cardColor;
  }
}

class _TiltableDetailCard extends StatefulWidget {
  const _TiltableDetailCard({
    required this.width,
    required this.height,
    required this.dismissVelocity,
    required this.onDismiss,
    required this.child,
  });

  final double width;
  final double height;
  final double dismissVelocity;
  final VoidCallback onDismiss;
  final Widget child;

  @override
  State<_TiltableDetailCard> createState() => _TiltableDetailCardState();
}

class _TiltableDetailCardState extends State<_TiltableDetailCard>
    with SingleTickerProviderStateMixin {
  double _tiltX = 0;
  double _tiltY = 0;
  Offset? _dragStart;
  double _startTiltX = 0;
  double _startTiltY = 0;
  late final AnimationController _returnController;
  late Animation<double> _returnX;
  late Animation<double> _returnY;

  @override
  void initState() {
    super.initState();
    _returnController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 420),
        )..addListener(() {
          setState(() {
            _tiltX = _returnX.value;
            _tiltY = _returnY.value;
          });
        });
    _returnX = const AlwaysStoppedAnimation<double>(0);
    _returnY = const AlwaysStoppedAnimation<double>(0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanDown: (DragDownDetails details) =>
          _startTilt(details.globalPosition),
      onPanUpdate: (DragUpdateDetails details) =>
          _updateTilt(details.globalPosition),
      onPanEnd: _handlePanEnd,
      onPanCancel: _resetTilt,
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.0018)
          ..rotateX(_tiltX)
          ..rotateY(_tiltY),
        child: SizedBox(
          width: widget.width,
          height: widget.height,
          child: widget.child,
        ),
      ),
    );
  }

  void _startTilt(Offset globalPosition) {
    _returnController.stop();
    setState(() {
      _dragStart = globalPosition;
      _startTiltX = _tiltX;
      _startTiltY = _tiltY;
    });
  }

  void _updateTilt(Offset globalPosition) {
    final Offset start = _dragStart ?? globalPosition;
    final Offset delta = globalPosition - start;
    final double dx = (delta.dx / widget.width).clamp(-1.0, 1.0);
    final double dy = (delta.dy / widget.height).clamp(-1.0, 1.0);

    setState(() {
      _tiltY = (_startTiltY - dx * 0.62).clamp(-0.44, 0.44);
      _tiltX = (_startTiltX + dy * 0.62).clamp(-0.44, 0.44);
    });
  }

  void _resetTilt() {
    setState(() {
      _dragStart = null;
    });
    _returnX = Tween<double>(begin: _tiltX, end: 0).animate(
      CurvedAnimation(parent: _returnController, curve: Curves.easeOutCubic),
    );
    _returnY = Tween<double>(begin: _tiltY, end: 0).animate(
      CurvedAnimation(parent: _returnController, curve: Curves.easeOutCubic),
    );
    _returnController.forward(from: 0);
  }

  void _handlePanEnd(DragEndDetails details) {
    final double velocity = details.velocity.pixelsPerSecond.dx;
    if (velocity.abs() >= widget.dismissVelocity) {
      widget.onDismiss();
      return;
    }
    _resetTilt();
  }

  @override
  void dispose() {
    _returnController.dispose();
    super.dispose();
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.fontSize = 12,
  });

  final String label;
  final String value;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: PixelTheme.textWhite,
            fontWeight: FontWeight.w900,
            fontSize: fontSize,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: TextStyle(color: PixelTheme.textWhite, fontSize: fontSize),
          ),
        ),
      ],
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.link, required this.fontSize, this.onTap});

  final String link;
  final double fontSize;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final String displayLink = link.trim().isEmpty
        ? context.l10n.tr('noLink')
        : link;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: PixelTheme.bgDark,
              border: Border.all(color: PixelTheme.textWhite, width: 2),
            ),
            child: PixelLinkIcon(
              size: fontSize + 8,
              color: PixelTheme.textWhite,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              displayLink,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: PixelTheme.textWhite,
                fontSize: fontSize,
                fontFamily: 'Unifont',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CardDescription extends StatelessWidget {
  const _CardDescription({required this.description, required this.fontSize});

  final String description;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Text(
      description.trim().isEmpty
          ? context.l10n.tr('noDescription')
          : description.trim(),
      style: TextStyle(
        color: PixelTheme.textWhite,
        fontSize: fontSize,
        height: 1.25,
        fontFamily: 'Unifont',
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.uid,
    required this.collectedAt,
    required this.padding,
    required this.fontSize,
  });

  final String uid;
  final String collectedAt;
  final EdgeInsets padding;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: PixelTheme.bgDark.withValues(alpha: 0.35),
        border: Border.all(color: PixelTheme.textWhite, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InfoRow(
            label: context.l10n.tr('uidLabel'),
            value: uid,
            fontSize: fontSize,
          ),
          const SizedBox(height: 4),
          _InfoRow(
            label: context.l10n.tr('collectedDate'),
            value: collectedAt,
            fontSize: fontSize,
          ),
        ],
      ),
    );
  }
}
