import 'package:flutter_test/flutter_test.dart';
import 'package:hitcon_nfc_battle/pages/user/emoji_catalog.dart';

void main() {
  test('bear, honey, and soft ice cream are selectable card attributes', () {
    const List<String> requestedEmoji = <String>['🐻', '🍯', '🍦'];
    final Map<String, String> catalog = <String, String>{
      for (final EmojiOption option in emojiOptionsCatalog)
        option.emoji: option.label,
    };

    expect(catalog['🐻'], 'Bear');
    expect(catalog['🍯'], 'Honey');
    expect(catalog['🍦'], 'Icecream');
    expect(
      selectedEmojiValuesFromCatalog(requestedEmoji.join()),
      requestedEmoji,
    );
    expect(
      emojiNameLabelForValue(requestedEmoji.join()),
      'Bear / Honey / Icecream',
    );
  });
}
