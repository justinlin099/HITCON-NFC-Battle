import 'package:flutter/material.dart';

import 'pixel_theme.dart';
import 'pixel_card_face.dart';
import 'pixel_link_dialog.dart';

class CardDetailPage extends StatefulWidget {
  const CardDetailPage({
    super.key,
    required this.heroTag,
    required this.title,
    required this.attributeEmoji,
    required this.attributeLabel,
    required this.link,
    required this.uid,
    required this.collectedAt,
    required this.cardColor,
    required this.imageAsset,
  });

  final String heroTag;
  final String title;
  final String attributeEmoji;
  final String attributeLabel;
  final String link;
  final String uid;
  final String collectedAt;
  final Color cardColor;
  final String imageAsset;

  @override
  State<CardDetailPage> createState() => _CardDetailPageState();
}

class _CardDetailPageState extends State<CardDetailPage> {
  static const Duration _textDelay = Duration(milliseconds: 450);
  static const double _dismissVelocity = 350;

  bool _showText = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(_textDelay, () {
      if (mounted) {
        setState(() {
          _showText = true;
        });
      }
    });
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
                                  image: Image.asset(
                                    widget.imageAsset,
                                    fit: BoxFit.cover,
                                    filterQuality: FilterQuality.none,
                                  ),
                                  fixedContent: _LinkRow(
                                    link: widget.link,
                                    fontSize: s(10),
                                    onTap: () => confirmAndOpenLink(
                                      context,
                                      widget.link,
                                    ),
                                  ),
                                  extraContent: _CardDescription(
                                    fontSize: s(13),
                                  ),
                                ),
                              ),
                            ),
                          ),
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
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(String raw) {
    if (raw.isEmpty) {
      return '未知';
    }
    return raw.length >= 10 ? raw.substring(0, 10) : raw;
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
        ? 'https://hitcon.org'
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
            child: Text(
              '🔗',
              style: TextStyle(
                color: PixelTheme.textWhite,
                fontSize: fontSize,
                fontWeight: FontWeight.w900,
                fontFamily: 'Unifont',
              ),
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
  const _CardDescription({required this.fontSize});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Text(
      '我是來自像素維度的漫遊者，喜歡收集閃閃發亮的故事與徽章，遇到新朋友會立刻打招呼。',
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
          _InfoRow(label: 'UID', value: uid, fontSize: fontSize),
          const SizedBox(height: 4),
          _InfoRow(label: '收藏時間', value: collectedAt, fontSize: fontSize),
        ],
      ),
    );
  }
}
