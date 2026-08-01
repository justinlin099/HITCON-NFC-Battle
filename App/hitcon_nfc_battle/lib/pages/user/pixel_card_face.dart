import 'package:flutter/material.dart';

import '../../widgets/system_emoji_text_style.dart';
import 'pixel_theme.dart';

class ExpandedPixelCardStyle {
  ExpandedPixelCardStyle._();

  static const double referenceCardWidth = 320;
  static const double watermarkFooterHeight = 58;
  static const double myCardWatermarkFooterHeight = 32;
  static const double printWatermarkFooterHeight = 24;
  static const double descriptionFontSize = 13;
  static const double descriptionLineHeight = 1.25;
  static const double verticalHitconWidthFactor = 0.11;
  static const double verticalHitconEdgeBleedFactor = 0.075;
  static const double hitconWordGapFactor = 0.18;
  static const double thumbnailHitconScale = 0.86;
  static const double thumbnailHitconRightInsetFactor = 0.025;
  static const double thumbnailHitconBottomInsetFactor = 0.02;
  static const double dividerExtraLength = 4;
}

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
    this.bottomLeftWatermark,
    this.watermarkFooterHeight = 0,
    this.verticalHitconWatermark = false,
    this.verticalHitconScale = 1,
    this.verticalHitconRightInsetFactor = 0,
    this.verticalHitconBottomInsetFactor = 0,
    this.fadeExtraContentAtBottom = false,
    this.extraContentScrollable = true,
    this.extraContentBottomPadding,
    this.contentAboveWatermarks = false,
    this.textFadeDuration = const Duration(milliseconds: 140),
    this.hiddenTextOpacity = 0,
    this.textOpacity,
    this.textOpacityKey,
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
  final Widget? bottomLeftWatermark;
  final double watermarkFooterHeight;
  final bool verticalHitconWatermark;
  final double verticalHitconScale;
  final double verticalHitconRightInsetFactor;
  final double verticalHitconBottomInsetFactor;
  final bool fadeExtraContentAtBottom;
  final bool extraContentScrollable;
  final double? extraContentBottomPadding;
  final bool contentAboveWatermarks;
  final Duration textFadeDuration;
  final double hiddenTextOpacity;
  final double? textOpacity;
  final Key? textOpacityKey;

  @override
  Widget build(BuildContext context) {
    final Color textColor = PixelTheme.textWhite;
    final Color attributeTextColor = _readableAttributeColor(cardColor);
    final double borderSize = 3;
    final double outerFrameInset = showOuterFrame ? borderSize : 0;

    return MediaQuery.withNoTextScaling(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double pad = (constraints.maxWidth * 0.06).clamp(6.0, 16.0);
          final double contentGap = extraContentSpacing ?? pad * 0.6;
          final double watermarkSize =
              (constraints.maxWidth * 0.07 * watermarkScale).clamp(10.0, 36.0);
          final double cardScale =
              constraints.maxWidth / ExpandedPixelCardStyle.referenceCardWidth;
          final double effectiveWatermarkSize = verticalHitconWatermark
              ? constraints.maxWidth *
                    ExpandedPixelCardStyle.verticalHitconWidthFactor *
                    verticalHitconScale
              : watermarkSize;
          final double dividerExtension = verticalHitconWatermark
              ? effectiveWatermarkSize * 0.25 +
                    ExpandedPixelCardStyle.dividerExtraLength * cardScale
              : 0;
          final double hitconEdgeBleed = verticalHitconWatermark
              ? effectiveWatermarkSize *
                    ExpandedPixelCardStyle.verticalHitconEdgeBleedFactor
              : 0;
          final double hitconRightInset =
              constraints.maxWidth * verticalHitconRightInsetFactor;
          final double hitconBottomInset =
              constraints.maxWidth * verticalHitconBottomInsetFactor;
          final double watermarkDrop = watermarkSize * 0.12;
          final Color gradientBase = PixelTheme.bgDark;
          final Color gradientStart =
              Color.lerp(gradientBase, cardColor, 0.18) ?? gradientBase;
          final Color gradientEnd =
              Color.lerp(gradientBase, cardColor, 0.48) ?? gradientBase;
          final List<Widget> watermarkLayers = <Widget>[
            if (bottomLeftWatermark != null)
              Positioned(
                left: 0,
                bottom: 0,
                width: constraints.maxWidth * 0.44,
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: IgnorePointer(child: bottomLeftWatermark!),
                ),
              ),
            Positioned(
              right: verticalHitconWatermark
                  ? -outerFrameInset - hitconEdgeBleed + hitconRightInset
                  : 0,
              bottom: verticalHitconWatermark
                  ? -outerFrameInset + hitconBottomInset
                  : 0,
              child: IgnorePointer(
                child: verticalHitconWatermark
                    ? RotatedBox(
                        quarterTurns: 3,
                        child: _HitconWatermark(
                          fontSize: effectiveWatermarkSize,
                          drop: 0,
                        ),
                      )
                    : bottomLeftWatermark == null
                    ? _HitconWatermark(
                        fontSize: watermarkSize,
                        drop: watermarkDrop,
                      )
                    : SizedBox(
                        width: constraints.maxWidth * 0.56,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.bottomRight,
                          child: _HitconWatermark(
                            fontSize: watermarkSize,
                            drop: 0,
                          ),
                        ),
                      ),
              ),
            ),
          ];

          return Container(
            clipBehavior: Clip.hardEdge,
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
              clipBehavior: Clip.none,
              children: [
                if (contentAboveWatermarks) ...watermarkLayers,
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
                        child: Padding(
                          padding: EdgeInsets.only(
                            right: verticalHitconWatermark
                                ? effectiveWatermarkSize * 1.05
                                : 0,
                          ),
                          child: _CardTextOpacity(
                            opacity: textOpacity,
                            opacityKey: textOpacityKey,
                            showText: showText,
                            hiddenOpacity: hiddenTextOpacity,
                            duration: textFadeDuration,
                            child: RepaintBoundary(
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
                                            style: systemEmojiTextStyle(
                                              color: attributeTextColor,
                                              fontSize: emojiFontSize,
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
                                    _CardContentDivider(
                                      extension: dividerExtension,
                                    ),
                                    if (extraContent != null) ...[
                                      SizedBox(height: contentGap),
                                      Expanded(
                                        child: _ExtraContentScrollView(
                                          contentGap: contentGap,
                                          fadeAtBottom:
                                              fadeExtraContentAtBottom,
                                          scrollable: extraContentScrollable,
                                          bottomPadding:
                                              extraContentBottomPadding,
                                          child: extraContent!,
                                        ),
                                      ),
                                    ],
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (watermarkFooterHeight > 0)
                        SizedBox(height: watermarkFooterHeight),
                    ],
                  ),
                ),
                if (!contentAboveWatermarks) ...watermarkLayers,
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
    final TextStyle emojiStyle = systemEmojiTextStyle(
      color: attributeTextColor,
      fontSize: emojiFontSize,
    );

    return displayLabel.characters
        .map(
          (String cluster) => TextSpan(
            text: cluster,
            style: isEmojiGrapheme(cluster) ? emojiStyle : labelStyle,
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
        .where(isEmojiGrapheme)
        .take(3)
        .toList(growable: false);
  }
}

class _HitconWatermark extends StatelessWidget {
  const _HitconWatermark({required this.fontSize, required this.drop});

  final double fontSize;
  final double drop;

  @override
  Widget build(BuildContext context) {
    final TextStyle style = TextStyle(
      color: PixelTheme.textWhite.withValues(alpha: 0.18),
      fontFamily: 'Unifont',
      fontSize: fontSize,
      fontWeight: FontWeight.w900,
      height: 1,
      letterSpacing: 1.0,
    );

    return Transform.translate(
      offset: Offset(0, drop),
      child: Text.rich(
        TextSpan(
          children: <InlineSpan>[
            const TextSpan(text: 'HITCON'),
            WidgetSpan(
              child: SizedBox(
                width: fontSize * ExpandedPixelCardStyle.hitconWordGapFactor,
              ),
            ),
            const TextSpan(text: '2026'),
          ],
        ),
        key: const ValueKey<String>('hitcon-watermark'),
        semanticsLabel: 'HITCON 2026',
        maxLines: 1,
        softWrap: false,
        style: style,
      ),
    );
  }
}

class _CardTextOpacity extends StatelessWidget {
  const _CardTextOpacity({
    required this.opacity,
    required this.opacityKey,
    required this.showText,
    required this.hiddenOpacity,
    required this.duration,
    required this.child,
  });

  final double? opacity;
  final Key? opacityKey;
  final bool showText;
  final double hiddenOpacity;
  final Duration duration;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final double? directOpacity = opacity;
    if (directOpacity != null) {
      return Opacity(
        key: opacityKey,
        opacity: directOpacity.clamp(0.0, 1.0),
        child: child,
      );
    }
    return AnimatedOpacity(
      key: opacityKey,
      duration: duration,
      curve: Curves.easeInOut,
      opacity: showText ? 1 : hiddenOpacity,
      child: child,
    );
  }
}

class _ExtraContentScrollView extends StatelessWidget {
  const _ExtraContentScrollView({
    required this.contentGap,
    required this.fadeAtBottom,
    required this.scrollable,
    required this.bottomPadding,
    required this.child,
  });

  final double contentGap;
  final bool fadeAtBottom;
  final bool scrollable;
  final double? bottomPadding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final double fadeHeight = (contentGap * 2.4).clamp(16.0, 24.0);
    final EdgeInsets padding = EdgeInsets.only(
      right: 4,
      bottom: bottomPadding ?? (fadeAtBottom ? fadeHeight : contentGap),
    );
    final Widget viewport = scrollable
        ? SingleChildScrollView(
            clipBehavior: Clip.hardEdge,
            padding: padding,
            child: child,
          )
        : ClipRect(
            child: Padding(
              key: const ValueKey<String>('card-extra-content-static'),
              padding: padding,
              child: child,
            ),
          );
    if (!fadeAtBottom) {
      return viewport;
    }

    return ShaderMask(
      key: const ValueKey<String>('my-card-description-fade'),
      blendMode: BlendMode.dstIn,
      shaderCallback: (Rect bounds) {
        final double fadeFraction = bounds.height <= 0
            ? 0.25
            : (fadeHeight / bounds.height).clamp(0.16, 0.42);
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const <Color>[Colors.white, Colors.white, Colors.transparent],
          stops: <double>[0, 1 - fadeFraction, 1],
        ).createShader(bounds);
      },
      child: viewport,
    );
  }
}

class _CardContentDivider extends StatelessWidget {
  const _CardContentDivider({required this.extension});

  final double extension;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth + extension;
        return SizedBox(
          height: 1,
          child: OverflowBox(
            alignment: Alignment.centerLeft,
            minWidth: width,
            maxWidth: width,
            minHeight: 1,
            maxHeight: 1,
            child: SizedBox(
              key: const ValueKey<String>('card-content-divider'),
              width: width,
              height: 1,
              child: ColoredBox(color: PixelTheme.textWhite),
            ),
          ),
        );
      },
    );
  }
}
