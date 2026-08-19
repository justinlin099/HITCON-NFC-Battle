import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_manager/nfc_manager.dart';

import 'package:hitcon_nfc_battle/l10n/app_localizations.dart';
import 'package:hitcon_nfc_battle/services/nfc_error_messages.dart';

void main() {
  const AppLocalizations l10n = AppLocalizations(Locale('zh', 'TW'));

  test('maps NFC session endings to useful messages', () {
    expect(
      nfcSessionErrorMessage(
        l10n,
        const NfcError(type: NfcErrorType.userCanceled, message: 'ignored'),
      ),
      '已取消掃描。',
    );
    expect(
      nfcSessionErrorMessage(
        l10n,
        const NfcError(type: NfcErrorType.sessionTimeout, message: 'ignored'),
      ),
      '未感應到卡片，掃描已逾時。',
    );
    expect(
      nfcSessionErrorMessage(
        l10n,
        const NfcError(type: NfcErrorType.systemIsBusy, message: 'ignored'),
      ),
      'NFC 正被其他功能使用，請稍後再試。',
    );
    expect(
      nfcSessionErrorMessage(
        l10n,
        const NfcError(type: NfcErrorType.unknown, message: ''),
      ),
      'NFC 發生未預期錯誤，請重試。',
    );
    expect(
      nfcSessionErrorMessage(
        l10n,
        PlatformException(code: '203', message: 'System resource unavailable'),
      ),
      'NFC 正被其他功能使用，請稍後再試。',
    );
  });

  test('maps Core NFC 401 to a protected or out-of-range message', () {
    final PlatformException error = PlatformException(
      code: '401',
      message: 'Stack Error',
    );

    final String message = nfcWriteErrorMessage(l10n, error);

    expect(message, '無法寫入卡片。卡片可能已受保護，或已離開感應區。');
    expect(message, isNot(contains('PlatformException')));
    expect(message, isNot(contains('Stack Error')));
  });

  test('uses the platform message for other NFC failures', () {
    final PlatformException error = PlatformException(
      code: '500',
      message: 'Connection lost',
    );

    expect(nfcWriteErrorMessage(l10n, error), '寫入失敗：Connection lost');
    expect(nfcReadErrorMessage(l10n, error), 'NFC 讀取失敗：Connection lost');
  });
}
