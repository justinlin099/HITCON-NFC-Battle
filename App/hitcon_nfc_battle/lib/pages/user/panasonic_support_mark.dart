import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class PanasonicSupportMark extends StatelessWidget {
  const PanasonicSupportMark({
    super.key,
    required this.width,
    required this.color,
  });

  final double width;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final double captionSize = (width * 0.078).clamp(8.0, 12.0);
    final double logoHeight = (width * 0.19).clamp(20.0, 30.0);
    final String fontFamily = switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.macOS => 'Helvetica Neue',
      TargetPlatform.windows => 'Arial',
      TargetPlatform.android ||
      TargetPlatform.fuchsia ||
      TargetPlatform.linux => 'Roboto',
    };

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
                  fontFamily: fontFamily,
                  fontSize: captionSize,
                  fontWeight: FontWeight.w600,
                  height: 1,
                ),
              ),
              SizedBox(height: (width * 0.018).clamp(2.0, 4.0)),
              SizedBox(
                width: width,
                height: logoHeight,
                child: FittedBox(
                  alignment: Alignment.centerLeft,
                  fit: BoxFit.contain,
                  child: Text(
                    'Panasonic',
                    style: TextStyle(
                      color: color,
                      fontFamily: fontFamily,
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      height: 1,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
