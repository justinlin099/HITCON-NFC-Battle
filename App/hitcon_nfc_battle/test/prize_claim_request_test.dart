import 'package:flutter_test/flutter_test.dart';
import 'package:hitcon_nfc_battle/services/auth_service.dart';

void main() {
  test('staff prize claims include the selected API prize type', () {
    expect(
      prizeClaimRequestBody(
        userId: 'attendee-1',
        uid: '04:A1:B2:C3',
        type: PrizeClaimType.stamp,
      ),
      <String, dynamic>{
        'user_id': 'attendee-1',
        'uid': '04:A1:B2:C3',
        'type': 'STAMP',
      },
    );
    expect(
      prizeClaimRequestBody(
        userId: 'attendee-1',
        uid: '04:A1:B2:C3',
        type: PrizeClaimType.external,
      )['type'],
      'EXTERNAL',
    );
    expect(
      prizeClaimRequestBody(
        userId: 'attendee-1',
        uid: '04:A1:B2:C3',
        type: PrizeClaimType.ranking,
      )['type'],
      'RANKING',
    );
  });
}
