import 'dart:io';

import 'package:hitcon_nfc_battle/services/nfc_battle_api_client.dart';
import 'package:hitcon_nfc_battle/services/staging_jwt_service.dart';

Future<void> main(List<String> args) async {
  final String role = args.contains('--staff') ? 'STAFF' : 'ATTENDEE';
  final String userId = args.contains('--staff')
      ? 'staging_staff_smoke'
      : 'staging_attendee_smoke';
  final String token = const StagingJwtService().createToken(
    userId: userId,
    role: role,
  );
  const NfcBattleApiClient api = NfcBattleApiClient();

  final Map<String, dynamic> me = await api.get('/users/me', token: token);
  final Map<String, dynamic> board = await api.get(
    '/scoreboard',
    token: token,
    query: <String, String>{'offset': '0', 'limit': '5'},
  );

  final Map<String, dynamic> meData = me['data'] as Map<String, dynamic>;
  final Map<String, dynamic> boardData = board['data'] as Map<String, dynamic>;
  stdout.writeln(
    'OK user=${meData['user_id']} role=${meData['role']} '
    'has_key=${meData['nfc_tag_key'] != null} '
    'rankings=${(boardData['rankings'] as List<dynamic>).length}',
  );
}
