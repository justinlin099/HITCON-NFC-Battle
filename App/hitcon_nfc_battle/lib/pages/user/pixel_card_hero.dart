import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import '../../l10n/app_localizations.dart';
import 'panasonic_support_mark.dart';
import 'pixel_card_face.dart';
import 'pixel_link_icon.dart';
import 'pixel_theme.dart';

HeroFlightShuttleBuilder pixelCardFlightShuttleBuilder({
  required String title,
  required String attributeEmoji,
  required String attributeLabel,
  String link = '',
  String description = '',
  required Color cardColor,
  required Widget Function() imageBuilder,
}) {
  return (
    BuildContext context,
    Animation<double> animation,
    HeroFlightDirection direction,
    BuildContext fromContext,
    BuildContext toContext,
  ) {
    final RenderBox fromBox = fromContext.findRenderObject()! as RenderBox;
    final RenderBox toBox = toContext.findRenderObject()! as RenderBox;
    final bool isPush = direction == HeroFlightDirection.push;
    final Size thumbnailSize = _smallerCardSize(fromBox.size, toBox.size);
    final Size expandedSize = _largerCardSize(fromBox.size, toBox.size);
    final Size shuttleSize = isPush ? expandedSize : thumbnailSize;
    final ThemeData shuttleTheme = Theme.of(fromContext);
    final Animation<double> curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final Widget cardImage = imageBuilder();
    final Widget rawShuttle = SizedBox(
      width: shuttleSize.width,
      height: shuttleSize.height,
      child: AnimatedBuilder(
        animation: curved,
        child: cardImage,
        builder: (BuildContext context, Widget? image) {
          final double detailProgress = curved.value;
          final double thumbnailProgress = 1 - detailProgress;
          final double detailScale = (expandedSize.width / 320).clamp(
            0.85,
            1.1,
          );
          final double rawDetailTextScale =
              detailScale * shuttleSize.width / expandedSize.width;
          final double rawExpandedCardScale =
              shuttleSize.width / ExpandedPixelCardStyle.referenceCardWidth;
          final double detailContentOpacity = isPush
              ? 0
              : Curves.easeInOut.transform(
                  ((animation.value - 0.08) / 0.92).clamp(0.0, 1.0),
                );
          final bool showPanasonicLogo = AppConfig.showPanasonicLogo;
          return PixelCardFace(
            title: title,
            attributeEmoji: attributeEmoji,
            attributeLabel: attributeLabel,
            cardColor: cardColor,
            showText: true,
            textOpacity: detailContentOpacity,
            textOpacityKey: ValueKey<String>(
              isPush ? 'hero-push-text-opacity' : 'hero-pop-text-opacity',
            ),
            titleFontSize: 22 * rawDetailTextScale,
            titleFontWeight: FontWeight.w900,
            attributeFontSize: 12 * rawDetailTextScale,
            emojiFontSize: 16 * rawDetailTextScale,
            titleMaxLines: 2,
            watermarkScale: 1.6,
            watermarkFooterHeight: showPanasonicLogo
                ? ExpandedPixelCardStyle.watermarkFooterHeight *
                      rawExpandedCardScale *
                      detailProgress
                : 0,
            verticalHitconWatermark: true,
            verticalHitconScale:
                1 -
                (1 - ExpandedPixelCardStyle.thumbnailHitconScale) *
                    thumbnailProgress,
            verticalHitconRightInsetFactor:
                ExpandedPixelCardStyle.thumbnailHitconRightInsetFactor *
                thumbnailProgress,
            verticalHitconBottomInsetFactor:
                ExpandedPixelCardStyle.thumbnailHitconBottomInsetFactor *
                thumbnailProgress,
            imageToTitleSpacing: 8 * rawDetailTextScale,
            extraContentSpacing: 8 * rawDetailTextScale,
            bottomLeftWatermark: showPanasonicLogo
                ? Opacity(
                    key: ValueKey<String>(
                      isPush
                          ? 'hero-push-logo-opacity'
                          : 'hero-pop-logo-opacity',
                    ),
                    opacity: detailContentOpacity,
                    child: ExpandedCardPanasonicMark(
                      cardWidth: shuttleSize.width,
                      scale: rawExpandedCardScale,
                      color: PixelTheme.textWhite.withValues(alpha: 0.18),
                    ),
                  )
                : null,
            image: image!,
            fixedContent: _HeroLinkRow(
              link: link,
              fontSize: 10 * rawDetailTextScale,
            ),
            extraContent: _HeroDescription(
              description: description,
              fontSize:
                  ExpandedPixelCardStyle.descriptionFontSize *
                  rawDetailTextScale,
            ),
          );
        },
      ),
    );
    final Widget shuttle = _wrapShuttle(
      rawShuttle: rawShuttle,
      shuttleTheme: shuttleTheme,
      shuttleSize: shuttleSize,
    );
    final Widget clippedChild = ClipRect(
      child: MediaQuery.withNoTextScaling(
        child: RepaintBoundary(child: shuttle),
      ),
    );

    return AnimatedBuilder(
      animation: curved,
      child: clippedChild,
      builder: (BuildContext context, Widget? child) {
        final double rotation = (1 - curved.value) * math.pi * 2;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateY(rotation),
          child: child,
        );
      },
    );
  };
}

class _HeroLinkRow extends StatelessWidget {
  const _HeroLinkRow({required this.link, required this.fontSize});

  final String link;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final String displayLink = link.trim().isEmpty
        ? context.l10n.tr('noLink')
        : link;
    return Row(
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: PixelTheme.bgDark,
            border: Border.all(color: PixelTheme.textWhite, width: 2),
          ),
          child: PixelLinkIcon(size: fontSize + 8, color: PixelTheme.textWhite),
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
    );
  }
}

class _HeroDescription extends StatelessWidget {
  const _HeroDescription({required this.description, required this.fontSize});

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
        height: ExpandedPixelCardStyle.descriptionLineHeight,
        fontFamily: 'Unifont',
      ),
    );
  }
}

Widget _wrapShuttle({
  required Widget rawShuttle,
  required ThemeData shuttleTheme,
  required Size shuttleSize,
}) {
  return Theme(
    data: shuttleTheme.copyWith(
      textTheme: shuttleTheme.textTheme.apply(fontFamily: 'Unifont'),
      primaryTextTheme: shuttleTheme.primaryTextTheme.apply(
        fontFamily: 'Unifont',
      ),
    ),
    child: DefaultTextStyle.merge(
      style: const TextStyle(fontFamily: 'Unifont'),
      child: FittedBox(
        fit: BoxFit.fill,
        child: SizedBox(
          width: shuttleSize.width,
          height: shuttleSize.height,
          child: rawShuttle,
        ),
      ),
    ),
  );
}

Size _largerCardSize(Size a, Size b) {
  return a.width * a.height >= b.width * b.height ? a : b;
}

Size _smallerCardSize(Size a, Size b) {
  return a.width * a.height <= b.width * b.height ? a : b;
}
