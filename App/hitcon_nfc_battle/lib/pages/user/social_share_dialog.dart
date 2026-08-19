import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import '../../l10n/app_localizations.dart';
import 'panasonic_support_mark.dart';
import 'pixel_theme.dart';

class SocialSharePayload {
  const SocialSharePayload({
    required this.poster,
    required this.text,
    required this.fileName,
    required this.accentColor,
  });

  final Widget poster;
  final String text;
  final String fileName;
  final Color accentColor;
}

Future<void> showSocialSharePreview({
  required BuildContext context,
  required SocialSharePayload payload,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.82),
    builder: (BuildContext context) => _SocialShareDialog(payload: payload),
  );
}

class SocialSharePoster extends StatelessWidget {
  const SocialSharePoster({
    super.key,
    required this.eyebrow,
    required this.headline,
    required this.visual,
    required this.accentColor,
    this.detail,
  });

  static const double width = 360;
  static const double height = 360;

  final String eyebrow;
  final String headline;
  final String? detail;
  final Widget visual;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final Color background =
        Color.lerp(PixelTheme.bgDark, accentColor, 0.12) ?? PixelTheme.bgDark;
    return MediaQuery.withNoTextScaling(
      child: SizedBox(
        key: const Key('social-share-poster'),
        width: width,
        height: height,
        child: Material(
          color: background,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              CustomPaint(
                painter: _SocialShareBackdropPainter(
                  accentColor: accentColor,
                  backgroundColor: background,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 14),
                child: Column(
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        ClipRRect(
                          key: const Key('social-share-app-icon-clip'),
                          borderRadius: BorderRadius.circular(5),
                          child: Image.asset(
                            'assets/app_icon/app_icon_master.png',
                            key: const Key('social-share-app-icon'),
                            width: 24,
                            height: 24,
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.none,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'HITCON NFC BATTLE',
                            maxLines: 1,
                            style: TextStyle(
                              color: PixelTheme.textWhite,
                              fontFamily: 'Unifont',
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.4,
                            ),
                          ),
                        ),
                        Text(
                          '2026',
                          style: TextStyle(
                            color: accentColor,
                            fontFamily: 'Unifont',
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Center(
                        child: FittedBox(
                          key: const Key('social-share-visual-fitted'),
                          fit: BoxFit.contain,
                          child: visual,
                        ),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      eyebrow.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: accentColor,
                        fontFamily: 'Unifont',
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      headline,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: PixelTheme.textWhite,
                        fontFamily: 'Unifont',
                        fontSize: 22,
                        height: 1.08,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (detail?.trim().isNotEmpty == true) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        detail!.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: PixelTheme.textGray,
                          fontFamily: 'Unifont',
                          fontSize: 11,
                          height: 1.15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            '#HITCON  #HITCON2026  #NFCBATTLE',
                            maxLines: 1,
                            style: TextStyle(
                              color: accentColor,
                              fontFamily: 'Unifont',
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        PanasonicBrandingBuilder(
                          builder:
                              (BuildContext context, bool showPanasonicLogo) =>
                                  showPanasonicLogo
                                  ? PanasonicSupportMark(
                                      width: 96,
                                      color: PixelTheme.textWhite.withValues(
                                        alpha: 0.62,
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SocialShareDialog extends StatefulWidget {
  const _SocialShareDialog({required this.payload});

  final SocialSharePayload payload;

  @override
  State<_SocialShareDialog> createState() => _SocialShareDialogState();
}

class _SocialShareDialogState extends State<_SocialShareDialog> {
  final GlobalKey _posterKey = GlobalKey();
  bool _isSharing = false;
  bool _shareFailed = false;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      key: const Key('social-share-dialog'),
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: PixelTheme.bgMid,
          border: Border.all(color: widget.payload.accentColor, width: 3),
          boxShadow: const <BoxShadow>[
            BoxShadow(color: Colors.black, blurRadius: 0, offset: Offset(6, 6)),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                context.l10n.tr('socialSharePreviewTitle'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: widget.payload.accentColor,
                  fontFamily: 'Unifont',
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 290),
                  child: AspectRatio(
                    aspectRatio:
                        SocialSharePoster.width / SocialSharePoster.height,
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: RepaintBoundary(
                        key: _posterKey,
                        child: widget.payload.poster,
                      ),
                    ),
                  ),
                ),
              ),
              if (_shareFailed) ...<Widget>[
                const SizedBox(height: 9),
                Text(
                  context.l10n.tr('socialShareFailed'),
                  key: const Key('social-share-error'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: PixelTheme.warning,
                    fontFamily: 'Unifont',
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _SocialShareDialogButton(
                      key: const Key('social-share-cancel'),
                      label: context.l10n.tr('cancel'),
                      color: PixelTheme.textGray,
                      onPressed: _isSharing
                          ? null
                          : () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Builder(
                      builder: (BuildContext shareButtonContext) {
                        return _SocialShareDialogButton(
                          key: const Key('social-share-submit'),
                          label: context.l10n.tr(
                            _isSharing ? 'socialShareGenerating' : 'share',
                          ),
                          color: widget.payload.accentColor,
                          icon: _isSharing ? null : Icons.ios_share_rounded,
                          onPressed: _isSharing
                              ? null
                              : () => _share(shareButtonContext),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _share(BuildContext shareButtonContext) async {
    final Rect origin = _shareOrigin(shareButtonContext);
    setState(() {
      _isSharing = true;
      _shareFailed = false;
    });
    try {
      await WidgetsBinding.instance.endOfFrame;
      final RenderObject? renderObject = _posterKey.currentContext
          ?.findRenderObject();
      if (renderObject is! RenderRepaintBoundary || !renderObject.hasSize) {
        throw StateError('Share poster is not ready.');
      }
      final ui.Image image = await renderObject.toImage(pixelRatio: 3);
      final ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      image.dispose();
      if (byteData == null) {
        throw StateError('Unable to encode the share poster.');
      }
      final Uint8List bytes = byteData.buffer.asUint8List();
      await SharePlus.instance.share(
        ShareParams(
          title: 'HITCON NFC Battle',
          subject: 'HITCON NFC Battle',
          text: widget.payload.text,
          files: <XFile>[XFile.fromData(bytes, mimeType: 'image/png')],
          fileNameOverrides: <String>[widget.payload.fileName],
          sharePositionOrigin: origin,
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _shareFailed = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSharing = false;
        });
      }
    }
  }

  Rect _shareOrigin(BuildContext context) {
    final RenderObject? renderObject = context.findRenderObject();
    if (renderObject is RenderBox && renderObject.hasSize) {
      return renderObject.localToGlobal(Offset.zero) & renderObject.size;
    }
    return const Rect.fromLTWH(0, 0, 1, 1);
  }
}

class _SocialShareDialogButton extends StatelessWidget {
  const _SocialShareDialogButton({
    super.key,
    required this.label,
    required this.color,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final Color color;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final Color effectiveColor = onPressed == null
        ? color.withValues(alpha: 0.48)
        : color;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: PixelTheme.bgDark,
          border: Border.all(color: effectiveColor, width: 2),
          boxShadow: onPressed == null
              ? const <BoxShadow>[]
              : const <BoxShadow>[
                  BoxShadow(
                    color: Colors.black,
                    blurRadius: 0,
                    offset: Offset(3, 3),
                  ),
                ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: 17, color: effectiveColor),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: effectiveColor,
                  fontFamily: 'Unifont',
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SocialShareBackdropPainter extends CustomPainter {
  const _SocialShareBackdropPainter({
    required this.accentColor,
    required this.backgroundColor,
  });

  final Color accentColor;
  final Color backgroundColor;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint glowPaint = Paint()
      ..shader =
          RadialGradient(
            colors: <Color>[
              accentColor.withValues(alpha: 0.24),
              backgroundColor.withValues(alpha: 0),
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.52, size.height * 0.38),
              radius: size.width * 0.58,
            ),
          );
    canvas.drawRect(Offset.zero & size, glowPaint);

    final Paint gridPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.075)
      ..strokeWidth = 1;
    const double grid = 24;
    for (double x = 0; x <= size.width; x += grid) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y <= size.height; y += grid) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final Paint cornerPaint = Paint()..color = accentColor;
    canvas.drawRect(
      Rect.fromLTWH(size.width - 6, size.height - 38, 6, 38),
      cornerPaint,
    );
  }

  @override
  bool shouldRepaint(_SocialShareBackdropPainter oldDelegate) {
    return oldDelegate.accentColor != accentColor ||
        oldDelegate.backgroundColor != backgroundColor;
  }
}
