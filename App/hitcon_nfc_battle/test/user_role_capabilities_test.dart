import 'package:flutter_test/flutter_test.dart';
import 'package:hitcon_nfc_battle/services/auth_service.dart';

void main() {
  group('card collection role capability', () {
    test('attendees and staff can collect cards', () {
      expect(UserRole.user.canCollectCards, isTrue);
      expect(UserRole.eventStaff.canCollectCards, isTrue);
    });

    test('admin and unknown roles cannot collect cards', () {
      expect(UserRole.admin.canCollectCards, isFalse);
      expect(UserRole.unknown.canCollectCards, isFalse);
    });
  });
}
