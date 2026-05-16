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
    this.extraContent,
    this.titleFontSize = 9,
    this.titleFontWeight = FontWeight.w700,
    this.attributeFontSize = 8,
    this.emojiFontSize = 10,
    this.titleMaxLines = 1,
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
  final Widget? extraContent;
  final double titleFontSize;
  final FontWeight titleFontWeight;
  final double attributeFontSize;
  final double emojiFontSize;
  final int titleMaxLines;
  final double? imageToTitleSpacing;
  final double? extraContentSpacing;
  final VoidCallback? onTapTitle;
  final VoidCallback? onTapAttribute;
  final Widget? titleSuffix;
  final Widget? attributeSuffix;

  @override
  Widget build(BuildContext context) {
    final Color textColor = PixelTheme.textWhite;
    final double borderSize = 3;

    return LayoutBuilder(
      builder: (context, constraints) {
        final double pad = (constraints.maxWidth * 0.06).clamp(6.0, 16.0);

        return Container(
          decoration: BoxDecoration(
            color: PixelTheme.bgMid,
            gradient: LinearGradient(
              colors: [PixelTheme.bgMid, cardColor.withValues(alpha: 0.08)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: cardColor, width: borderSize),
            boxShadow: const [
              BoxShadow(color: Colors.black, blurRadius: 0, offset: Offset(4, 4)),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.all(pad),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: Container(
                    decoration: BoxDecoration(
                      color: PixelTheme.bgDark,
                      border: Border.all(color: cardColor, width: 2),
                    ),
                    child: image,
                  ),
                ),
                SizedBox(height: imageToTitleSpacing ?? pad),
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 140),
                  opacity: showText ? 1 : 0,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
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
                      const SizedBox(height: 2),
                      GestureDetector(
                        onTap: onTapAttribute,
                        behavior: HitTestBehavior.opaque,
                        child: Row(
                          children: [
                            Text(
                              attributeEmoji,
                              style: TextStyle(
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
                            Expanded(
                              child: Text(
                                attributeLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: cardColor,
                                  fontSize: attributeFontSize,
                                  fontWeight: FontWeight.w900,
                                  fontFamily: 'Unifont',
                                  letterSpacing: 0.6,
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
                      if (extraContent != null) ...[
                        SizedBox(height: extraContentSpacing ?? pad * 0.6),
                        extraContent!,
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
