import 'package:flutter_test/flutter_test.dart';
import 'package:hitcon_nfc_battle/services/user_profile_fields.dart';

void main() {
  group('readPhishingCount', () {
    test('reads a non-negative integer count', () {
      expect(readPhishingCount(<String, dynamic>{'phishing_count': 2}), 2);
    });

    test('returns null when the backend omits the field', () {
      expect(readPhishingCount(<String, dynamic>{}), isNull);
      expect(readPhishingCount(null), isNull);
    });

    test('ignores invalid values without throwing', () {
      expect(
        readPhishingCount(<String, dynamic>{'phishing_count': null}),
        isNull,
      );
      expect(
        readPhishingCount(<String, dynamic>{'phishing_count': '2'}),
        isNull,
      );
      expect(
        readPhishingCount(<String, dynamic>{'phishing_count': -1}),
        isNull,
      );
      expect(
        readPhishingCount(<String, dynamic>{'phishing_count': 1.5}),
        isNull,
      );
    });
  });
}
