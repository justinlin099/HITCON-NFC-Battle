import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'pixel_theme.dart';

Future<void> confirmAndOpenLink(BuildContext context, String link) async {
  final String effectiveLink = link.trim().isEmpty
      ? 'https://hitcon.org'
      : link.trim();
  final Uri? uri = Uri.tryParse(effectiveLink);
  if (uri == null) {
    return;
  }

  final bool? shouldOpen = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.72),
    builder: (BuildContext dialogContext) {
      return _PixelLinkConfirmDialog(link: effectiveLink);
    },
  );

  if (shouldOpen == true) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _PixelLinkConfirmDialog extends StatelessWidget {
  const _PixelLinkConfirmDialog({required this.link});

  final String link;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: PixelTheme.bgMid,
          border: Border.all(color: PixelTheme.accent, width: 3),
          boxShadow: const [
            BoxShadow(color: Colors.black, blurRadius: 0, offset: Offset(6, 6)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '要前往這個網站嗎？',
              style: TextStyle(
                color: PixelTheme.accent,
                fontSize: 16,
                fontWeight: FontWeight.w900,
                fontFamily: 'Unifont',
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: PixelTheme.bgDark,
                border: Border.all(color: PixelTheme.border, width: 2),
              ),
              child: Text(
                link,
                style: TextStyle(
                  color: PixelTheme.textWhite,
                  fontSize: 12,
                  height: 1.4,
                  fontFamily: 'Unifont',
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '你即將離開 HITCON NFC Battle App，請確認這是你信任的連結。',
              style: TextStyle(
                color: PixelTheme.textGray,
                fontSize: 11,
                height: 1.45,
                fontFamily: 'Unifont',
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _PixelDialogButton(
                    label: '取消',
                    color: PixelTheme.textGray,
                    onTap: () => Navigator.of(context).pop(false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _PixelDialogButton(
                    label: '前往',
                    color: PixelTheme.accent,
                    onTap: () => Navigator.of(context).pop(true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PixelDialogButton extends StatelessWidget {
  const _PixelDialogButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: PixelTheme.bgDark,
          border: Border.all(color: color, width: 2),
          boxShadow: const [
            BoxShadow(color: Colors.black, blurRadius: 0, offset: Offset(3, 3)),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w900,
            fontFamily: 'Unifont',
          ),
        ),
      ),
    );
  }
}
