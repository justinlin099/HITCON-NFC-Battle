import 'package:flutter/services.dart';
import 'package:nfc_manager/nfc_manager.dart';

import '../l10n/app_localizations.dart';

String nfcSessionErrorMessage(AppLocalizations l10n, Object error) {
  if (error is NfcError) {
    return switch (error.type) {
      NfcErrorType.userCanceled => l10n.tr('nfcScanCanceled'),
      NfcErrorType.sessionTimeout => l10n.tr('nfcScanTimedOut'),
      NfcErrorType.systemIsBusy => l10n.tr('nfcSystemBusy'),
      NfcErrorType.unknown => l10n.tr('nfcUnknownError'),
    };
  }
  if (error is PlatformException) {
    return switch (error.code) {
      '200' => l10n.tr('nfcScanCanceled'),
      '201' => l10n.tr('nfcScanTimedOut'),
      '203' => l10n.tr('nfcSystemBusy'),
      _ => l10n.tr('nfcError', <String, Object?>{
        'error': nfcErrorDetail(l10n, error),
      }),
    };
  }

  return l10n.tr('nfcError', <String, Object?>{
    'error': nfcErrorDetail(l10n, error),
  });
}

String nfcReadErrorMessage(AppLocalizations l10n, Object error) {
  return l10n.tr('nfcReadFailed', <String, Object?>{
    'error': nfcErrorDetail(l10n, error),
  });
}

String nfcWriteErrorMessage(AppLocalizations l10n, Object error) {
  if (error is PlatformException && error.code == '401') {
    return l10n.tr('nfcTagUpdateFailed');
  }

  return l10n.tr('writeFailed', <String, Object?>{
    'error': nfcErrorDetail(l10n, error),
  });
}

String nfcErrorDetail(AppLocalizations l10n, Object error) {
  if (error is PlatformException) {
    final String message = error.message?.trim() ?? '';
    final String code = error.code.trim();
    return message.isNotEmpty
        ? message
        : code.isNotEmpty
        ? code
        : l10n.tr('unknown');
  }
  if (error is NfcError) {
    final String message = error.message.trim();
    return message.isNotEmpty ? message : l10n.tr('unknown');
  }

  final String detail = error.toString().trim();
  return detail.isEmpty ? l10n.tr('unknown') : detail;
}
