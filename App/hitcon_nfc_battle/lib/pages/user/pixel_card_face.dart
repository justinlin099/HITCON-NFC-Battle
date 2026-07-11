import 'package:flutter/material.dart';

import 'pixel_theme.dart';

class PixelCardFace extends StatelessWidget {
  const PixelCardFace({
    super.key,
    required this.title,
    required this.attributeEmoji,
    required this.attributeLabel,
    required this.cardColor,
    required this.showText,
    required this.image,
    this.fixedContent,
    this.extraContent,
    this.titleFontSize = 9,
    this.titleFontWeight = FontWeight.w700,
    this.attributeFontSize = 8,
    this.emojiFontSize = 10,
    this.titleMaxLines = 1,
    this.attributeMaxLines = 1,
    this.stackAttributePairs = false,
    this.watermarkScale = 1,
    this.imageBorderWidth = 2,
    this.showOuterFrame = true,
    this.showDropShadow = true,
    this.imageToTitleSpacing,
    this.extraContentSpacing,
    this.onTapTitle,
    this.onTapAttribute,
    this.titleSuffix,
    this.attributeSuffix,
  });

  final String title;
  final String attributeEmoji;
  final String attributeLabel;
  final Color cardColor;
  final bool showText;
  final Widget image;
  final Widget? fixedContent;
  final Widget? extraContent;
  final double titleFontSize;
  final FontWeight titleFontWeight;
  final double attributeFontSize;
  final double emojiFontSize;
  final int titleMaxLines;
  final int attributeMaxLines;
  final bool stackAttributePairs;
  final double watermarkScale;
  final double imageBorderWidth;
  final bool showOuterFrame;
  final bool showDropShadow;
  final double? imageToTitleSpacing;
  final double? extraContentSpacing;
  final VoidCallback? onTapTitle;
  final VoidCallback? onTapAttribute;
  final Widget? titleSuffix;
  final Widget? attributeSuffix;

  @override
  Widget build(BuildContext context) {
    final Color textColor = PixelTheme.textWhite;
    final Color attributeTextColor = _readableAttributeColor(cardColor);
    final double borderSize = 3;

    return MediaQuery.withNoTextScaling(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double pad = (constraints.maxWidth * 0.06).clamp(6.0, 16.0);
          final double contentGap = extraContentSpacing ?? pad * 0.6;
          final double watermarkSize =
              (constraints.maxWidth * 0.07 * watermarkScale).clamp(10.0, 36.0);
          final double watermarkDrop = watermarkSize * 0.12;
          final Color gradientBase = PixelTheme.bgDark;
          final Color gradientStart =
              Color.lerp(gradientBase, cardColor, 0.18) ?? gradientBase;
          final Color gradientEnd =
              Color.lerp(gradientBase, cardColor, 0.48) ?? gradientBase;

          return Container(
            decoration: BoxDecoration(
              color: gradientBase,
              gradient: LinearGradient(
                colors: [gradientStart, gradientEnd],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: showOuterFrame
                  ? Border.all(color: cardColor, width: borderSize)
                  : null,
              boxShadow: showDropShadow
                  ? const [
                      BoxShadow(
                        color: Colors.black,
                        blurRadius: 0,
                        offset: Offset(4, 4),
                      ),
                    ]
                  : const [],
            ),
            child: Stack(
              children: [
                Padding(
                  padding: EdgeInsets.all(pad),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AspectRatio(
                        aspectRatio: 1,
                        child: Container(
                          decoration: BoxDecoration(
                            color: PixelTheme.bgDark,
                            border: Border.all(
                              color: cardColor,
                              width: imageBorderWidth,
                            ),
                          ),
                          child: image,
                        ),
                      ),
                      SizedBox(height: imageToTitleSpacing ?? pad),
                      Expanded(
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 140),
                          opacity: showText ? 1 : 0,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              GestureDetector(
                                onTap: onTapTitle,
                                behavior: HitTestBehavior.opaque,
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        title,
                                        maxLines: titleMaxLines,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: textColor,
                                          fontSize: titleFontSize,
                                          fontWeight: titleFontWeight,
                                          fontFamily: 'Unifont',
                                        ),
                                      ),
                                    ),
                                    if (titleSuffix != null) ...[
                                      const SizedBox(width: 6),
                                      titleSuffix!,
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(height: 1),
                              GestureDetector(
                                onTap: onTapAttribute,
                                behavior: HitTestBehavior.opaque,
                                child: Row(
                                  children: [
                                    if (_showSeparateAttributeEmoji) ...[
                                      Text(
                                        attributeEmoji,
                                        style: TextStyle(
                                          color: attributeTextColor,
                                          fontSize: emojiFontSize,
                                          fontFamily: 'Roboto',
                                          fontFamilyFallback: const <String>[
                                            'Segoe UI Emoji',
                                            'Apple Color Emoji',
                                            'Noto Color Emoji',
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                    ],
                                    Expanded(
                                      child: RichText(
                                        maxLines: attributeMaxLines,
                                        overflow: TextOverflow.ellipsis,
                                        text: TextSpan(
                                          children: _attributeLabelSpans(
                                            attributeTextColor,
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (attributeSuffix != null) ...[
                                      const SizedBox(width: 6),
                                      attributeSuffix!,
                                    ],
                                  ],
                                ),
                              ),
                              if (fixedContent != null ||
                                  extraContent != null) ...[
                                SizedBox(height: contentGap),
                                ?fixedContent,
                                if (fixedContent != null &&
                                    extraContent != null)
                                  SizedBox(height: contentGap),
                                Container(
                                  height: 1,
                                  width: double.infinity,
                                  color: PixelTheme.textWhite,
                                ),
                                if (extraContent != null) ...[
                                  SizedBox(height: contentGap),
                                  Expanded(
                                    child: SingleChildScrollView(
                                      padding: const EdgeInsets.only(right: 4),
                                      child: extraContent!,
                                    ),
                                  ),
                                ],
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: Transform.translate(
                      offset: Offset(0, watermarkDrop),
                      child: Text(
                        'HITCON 2026',
                        style: TextStyle(
                          color: PixelTheme.textWhite.withValues(alpha: 0.18),
                          fontFamily: 'Unifont',
                          fontSize: watermarkSize,
                          fontWeight: FontWeight.w900,
                          height: 1,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  List<InlineSpan> _attributeLabelSpans(Color attributeTextColor) {
    final String displayLabel = _displayAttributeLabel();
    final TextStyle labelStyle = TextStyle(
      color: attributeTextColor,
      fontSize: attributeFontSize,
      fontWeight: FontWeight.w900,
      fontFamily: 'Unifont',
      letterSpacing: 0.6,
    );
    final TextStyle emojiStyle = TextStyle(
      color: attributeTextColor,
      fontSize: emojiFontSize,
      fontFamily: 'Roboto',
      fontFamilyFallback: const <String>[
        'Segoe UI Emoji',
        'Apple Color Emoji',
        'Noto Color Emoji',
      ],
    );

    return displayLabel.characters
        .map(
          (String cluster) => TextSpan(
            text: cluster,
            style: _containsEmoji(cluster) ? emojiStyle : labelStyle,
          ),
        )
        .toList(growable: false);
  }

  Color _readableAttributeColor(Color accentColor) {
    if (accentColor.computeLuminance() < 0.38) {
      return PixelTheme.textWhite;
    }
    return accentColor;
  }

  bool get _showSeparateAttributeEmoji {
    return attributeEmoji.isNotEmpty &&
        _displayAttributeLabel() == attributeLabel;
  }

  String _displayAttributeLabel() {
    final List<String> emojis = _attributeEmojiClusters();
    final List<String> labels = attributeLabel
        .split('/')
        .map((String label) => label.trim())
        .where((String label) => label.isNotEmpty)
        .take(3)
        .toList(growable: false);

    if (emojis.length < 2 || labels.isEmpty) {
      return attributeLabel;
    }

    final int pairCount = emojis.length < labels.length
        ? emojis.length
        : labels.length;
    final List<String> pairs = <String>[];
    for (int i = 0; i < pairCount; i++) {
      pairs.add('${emojis[i]} ${labels[i]}');
    }

    return pairs.join(stackAttributePairs ? '\n' : '  ');
  }

  List<String> _attributeEmojiClusters() {
    return attributeEmoji.characters
        .where(_containsEmoji)
        .take(3)
        .toList(growable: false);
  }

  bool _containsEmoji(String value) {
    for (final int rune in value.runes) {
      if ((rune >= 0x1F000 && rune <= 0x1FAFF) ||
          (rune >= 0x2600 && rune <= 0x27BF)) {
        return true;
      }
    }
    return false;
  }
}
