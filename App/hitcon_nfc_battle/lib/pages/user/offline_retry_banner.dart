import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'pixel_theme.dart';

class OfflineRetryBanner extends StatelessWidget {
  const OfflineRetryBanner({
    super.key,
    required this.onRetry,
    this.isRetrying = false,
  });

  final VoidCallback onRetry;
  final bool isRetrying;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: context.l10n.tr('offlineTapToRefresh'),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isRetrying ? null : onRetry,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: PixelTheme.warning.withValues(alpha: 0.16),
              border: Border.all(color: PixelTheme.warning, width: 2),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Colors.black,
                  blurRadius: 0,
                  offset: Offset(3, 3),
                ),
              ],
            ),
            child: Row(
              children: <Widget>[
                if (isRetrying)
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: PixelTheme.warning,
                    ),
                  )
                else
                  Icon(
                    Icons.wifi_off_rounded,
                    size: 20,
                    color: PixelTheme.warning,
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    context.l10n.tr(
                      isRetrying ? 'reconnecting' : 'offlineTapToRefresh',
                    ),
                    style: TextStyle(
                      color: PixelTheme.textWhite,
                      fontFamily: 'Unifont',
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (!isRetrying)
                  Icon(
                    Icons.refresh_rounded,
                    size: 20,
                    color: PixelTheme.warning,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
