import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'pixel_card_face.dart';

HeroFlightShuttleBuilder pixelCardFlightShuttleBuilder({
  required String title,
  required String attributeEmoji,
  required String attributeLabel,
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
    final Size shuttleSize = isPush
        ? _largerCardSize(fromBox.size, toBox.size)
        : _smallerCardSize(fromBox.size, toBox.size);
    final ThemeData shuttleTheme = Theme.of(fromContext);
    final Animation<double> curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final Widget rawShuttle = SizedBox(
      width: shuttleSize.width,
      height: shuttleSize.height,
      child: PixelCardFace(
        title: title,
        attributeEmoji: attributeEmoji,
        attributeLabel: attributeLabel,
        cardColor: cardColor,
        showText: false,
        titleFontSize: 22,
        titleFontWeight: FontWeight.w900,
        attributeFontSize: 12,
        emojiFontSize: 16,
        titleMaxLines: 2,
        watermarkScale: 1.6,
        imageToTitleSpacing: 8,
        extraContentSpacing: 8,
        image: imageBuilder(),
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
