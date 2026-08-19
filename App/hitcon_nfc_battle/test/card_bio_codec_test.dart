import 'package:flutter_test/flutter_test.dart';
import 'package:hitcon_nfc_battle/services/card_bio_codec.dart';

void main() {
  const CardBioCodec codec = CardBioCodec();

  test('encodes and decodes card metadata without exposing it in bio', () {
    final String encoded = codec.encode(
      bio: 'Hello HITCON',
      link: 'https://hitcon.org',
      cardColor: 0xFFFFD700,
    );

    final CardBioData decoded = codec.decode(encoded);

    expect(decoded.bio, 'Hello HITCON');
    expect(decoded.link, 'https://hitcon.org');
    expect(decoded.cardColor, 0xFFFFD700);
  });

  test('keeps legacy plain bio unchanged', () {
    final CardBioData decoded = codec.decode('Legacy profile');

    expect(decoded.bio, 'Legacy profile');
    expect(decoded.link, isEmpty);
    expect(decoded.cardColor, isNull);
  });

  test('re-encoding replaces existing metadata', () {
    final String first = codec.encode(
      bio: 'Profile',
      link: 'https://old.example',
      cardColor: 1,
    );
    final String second = codec.encode(
      bio: first,
      link: 'https://new.example',
      cardColor: 2,
    );

    final CardBioData decoded = codec.decode(second);
    expect(decoded.bio, 'Profile');
    expect(decoded.link, 'https://new.example');
    expect(decoded.cardColor, 2);
  });

  test('does not hide malformed metadata', () {
    const String malformed = 'Profile\n\n[[HITCON_CARD:v1:not-base64]]';

    expect(codec.decode(malformed).bio, malformed);
  });
}
