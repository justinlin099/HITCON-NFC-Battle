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

  group('backend role mapping', () {
    test('attendee, sponsor, and community use player capabilities', () {
      expect(userRoleFromValue('ATTENDEE'), UserRole.user);
      expect(userRoleFromValue('SPONSOR'), UserRole.user);
      expect(userRoleFromValue('COMMUNITY'), UserRole.user);
      expect(userRoleFromValue(' sponsor '), UserRole.user);
    });

    test('only staff and admin use the management flow', () {
      expect(userRoleFromValue('STAFF').usesUserFlow, isFalse);
      expect(userRoleFromValue('EVENT_STAFF').usesUserFlow, isFalse);
      expect(userRoleFromValue('ADMIN').usesUserFlow, isFalse);
      expect(userRoleFromValue('ATTENDEE').usesUserFlow, isTrue);
      expect(userRoleFromValue('SPONSOR').usesUserFlow, isTrue);
      expect(userRoleFromValue('COMMUNITY').usesUserFlow, isTrue);
      expect(userRoleFromValue('UNRECOGNIZED').usesUserFlow, isTrue);
    });
  });
}
