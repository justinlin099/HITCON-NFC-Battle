import 'package:flutter_test/flutter_test.dart';

import 'package:hitcon_nfc_battle/l10n/strings_en.dart';
import 'package:hitcon_nfc_battle/l10n/strings_ja.dart';
import 'package:hitcon_nfc_battle/l10n/strings_ko.dart';
import 'package:hitcon_nfc_battle/l10n/strings_zh_tw.dart';

void main() {
  test('every localized social share message includes HITCON 2026 hashtag', () {
    const List<String> shareTextKeys = <String>[
      'socialShareAchievementText',
      'socialShareRankText',
      'socialShareCardText',
      'socialShareCollectionText',
    ];

    for (final Map<String, String> strings in <Map<String, String>>[
      appStringsEn,
      appStringsZhTw,
      appStringsJa,
      appStringsKo,
    ]) {
      for (final String key in shareTextKeys) {
        expect(strings[key], contains('#HITCON2026'), reason: key);
      }
    }
  });

  test('social share preview describes the square image ratio', () {
    for (final Map<String, String> strings in <Map<String, String>>[
      appStringsEn,
      appStringsZhTw,
      appStringsJa,
      appStringsKo,
    ]) {
      expect(strings['socialSharePreviewHint'], contains('1:1'));
      expect(strings['socialSharePreviewHint'], isNot(contains('4:5')));
    }
  });
}
