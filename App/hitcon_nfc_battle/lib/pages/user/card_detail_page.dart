import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'pixel_theme.dart';
import 'pixel_card_face.dart';

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
  });

  final String heroTag;
  final String title;
  final String attributeEmoji;
  final String attributeLabel;
  final String link;
  final String uid;
  final String collectedAt;
  final Color cardColor;

  @override
  State<CardDetailPage> createState() => _CardDetailPageState();
}

class _CardDetailPageState extends State<CardDetailPage> {
  static const Duration _textDelay = Duration(milliseconds: 450);
  static const Duration _textFade = Duration(milliseconds: 220);

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
                  const double ratio = 0.72; // match preview card ratio
                  final double maxWidth = constraints.maxWidth - 24;
                  final double maxHeight = constraints.maxHeight - 24;
                  double cardWidth = maxWidth;
                  double cardHeight = cardWidth / ratio;

                  if (cardHeight > maxHeight) {
                    cardHeight = maxHeight;
                    cardWidth = cardHeight * ratio;
                  }

                  final double contentPad = (cardWidth * 0.06).clamp(6.0, 16.0);

                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Hero(
                          tag: widget.heroTag,
                          child: Material(
                            color: Colors.transparent,
                            child: SizedBox(
                              width: cardWidth,
                              height: cardHeight,
                              child: PixelCardFace(
                                title: widget.title,
                                attributeEmoji: widget.attributeEmoji,
                                attributeLabel: widget.attributeLabel,
                                cardColor: widget.cardColor,
                                showText: _showText,
                                titleFontSize: 22,
                                titleFontWeight: FontWeight.w900,
                                attributeFontSize: 12,
                                emojiFontSize: 16,
                                titleMaxLines: 2,
                                imageToTitleSpacing: 6,
                                extraContentSpacing: 4,
                                image: Image.asset(
                                  'assets/images/mock_card_48.png',
                                  fit: BoxFit.cover,
                                  filterQuality: FilterQuality.none,
                                ),
                                extraContent: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 6),
                                    _LinkRow(
                                      link: widget.link,
                                      onTap: () => _openLink(widget.link),
                                    ),
                                    const SizedBox(height: 4),
                                    Container(
                                      height: 1,
                                      width: double.infinity,
                                      color: PixelTheme.textWhite,
                                    ),
                                    const SizedBox(height: 4),
                                    const _CardDescription(),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: cardWidth,
                          child: _InfoCard(
                            uid: widget.uid,
                            collectedAt: _formatDate(widget.collectedAt),
                            padding: EdgeInsets.all(contentPad),
                          ),
                        ),
                      ],
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

  Future<void> _openLink(String link) async {
    final String effectiveLink = link.trim().isEmpty ? 'https://hitcon.org' : link;
    final Uri? uri = Uri.tryParse(effectiveLink);
    if (uri == null) {
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.fontSize = 12});

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
            style: TextStyle(
              color: PixelTheme.textWhite,
              fontSize: fontSize,
            ),
          ),
        ),
      ],
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.link, this.onTap});

  final String link;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final String displayLink = link.trim().isEmpty ? 'https://hitcon.org' : link;
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
                fontSize: 9,
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
                fontSize: 9,
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
  const _CardDescription();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 29.3,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(right: 4),
        child: Text(
          '我是來自像素維度的漫遊者，喜歡收集閃閃發亮的故事與徽章，遇到新朋友會立刻打招呼。',
          style: TextStyle(
            color: PixelTheme.textWhite,
            fontSize: 13,
            height: 1.25,
            fontFamily: 'Unifont',
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.uid, required this.collectedAt, required this.padding});

  final String uid;
  final String collectedAt;
  final EdgeInsets padding;

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
          _InfoRow(label: 'UID', value: uid, fontSize: 12),
          const SizedBox(height: 4),
          _InfoRow(label: '收藏時間', value: collectedAt, fontSize: 12),
        ],
      ),
    );
  }
}
