import 'package:flutter/material.dart';

import '../../config/app_config.dart';

class PanasonicBrandingBuilder extends StatelessWidget {
  const PanasonicBrandingBuilder({
    super.key,
    required this.builder,
    this.forPrint = false,
  });

  final Widget Function(BuildContext context, bool showPanasonicLogo) builder;
  final bool forPrint;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: forPrint
          ? AppConfig.showPanasonicLogoOnPrintListenable
          : AppConfig.showPanasonicLogoListenable,
      builder: (BuildContext context, bool showPanasonicLogo, Widget? child) {
        return builder(context, showPanasonicLogo);
      },
    );
  }
}

class ExpandedCardPanasonicMark extends StatelessWidget {
  const ExpandedCardPanasonicMark({
    super.key,
    required this.cardWidth,
    required this.scale,
    required this.color,
  });

  final double cardWidth;
  final double scale;
  final Color color;

  static const double widthFactor = 0.38;
  static const double padding = 8;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: Offset(padding * scale, -padding * scale),
      child: PanasonicSupportMark(width: cardWidth * widthFactor, color: color),
    );
  }
}

class PanasonicSupportMark extends StatelessWidget {
  const PanasonicSupportMark({
    super.key,
    required this.width,
    required this.color,
  });

  final double width;
  final Color color;

  static const String logoAsset = 'assets/images/panasonic_logo_white.png';
  static const double logoAspectRatio = 11811 / 1841;

  @override
  Widget build(BuildContext context) {
    final double captionSize = (width * 0.078).clamp(8.0, 12.0);

    return Semantics(
      image: true,
      label: 'Supported by Panasonic',
      child: ExcludeSemantics(
        child: SizedBox(
          width: width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Supported by',
                style: TextStyle(
                  color: color,
                  fontFamily: 'Unifont',
                  fontSize: captionSize,
                  fontWeight: FontWeight.w600,
                  height: 1,
                ),
              ),
              SizedBox(height: (width * 0.018).clamp(2.0, 4.0)),
              AspectRatio(
                aspectRatio: logoAspectRatio,
                child: Image.asset(
                  logoAsset,
                  key: const ValueKey<String>('panasonic-official-logo'),
                  alignment: Alignment.centerLeft,
                  fit: BoxFit.contain,
                  cacheWidth: 1024,
                  color: color,
                  colorBlendMode: BlendMode.srcIn,
                  filterQuality: FilterQuality.high,
                  gaplessPlayback: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
