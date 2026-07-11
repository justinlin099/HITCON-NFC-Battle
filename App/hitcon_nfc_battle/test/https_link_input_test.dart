import 'package:flutter_test/flutter_test.dart';
import 'package:hitcon_nfc_battle/pages/user/https_link_input.dart';

void main() {
  test('normalizes editable link bodies to HTTPS URLs', () {
    expect(httpsLinkBody('https://hitcon.org/event'), 'hitcon.org/event');
    expect(httpsLinkBody('http://hitcon.org'), 'hitcon.org');
    expect(buildHttpsLink('hitcon.org/event'), 'https://hitcon.org/event');
    expect(buildHttpsLink(''), '');
  });

  test('accepts empty links and normal public HTTPS domains', () {
    expect(validateHttpsLink(''), isNull);
    expect(validateHttpsLink('hitcon.org'), isNull);
    expect(validateHttpsLink('https://www.hitcon.org/2026?q=nfc'), isNull);
    expect(validateHttpsLink('cards.hitcon.org:443/profile'), isNull);
  });

  test('rejects malformed or unsafe link targets', () {
    const List<String> unsafeLinks = <String>[
      'javascript:alert(1)',
      'user@example.com',
      'localhost/path',
      'service.local/path',
      '127.0.0.1/admin',
      '[::1]/admin',
      'example.com:8443/admin',
      r'example.com\@evil.test',
      'example',
      'example.com/%0AInjected-Header',
    ];

    for (final String link in unsafeLinks) {
      expect(validateHttpsLink(link), isNotNull, reason: link);
    }
  });
}
