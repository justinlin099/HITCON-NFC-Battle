import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hitcon_nfc_battle/services/local_scoreboard_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('stores the latest scoreboard per user', () async {
    final LocalScoreboardStore store = LocalScoreboardStore();

    await store.save('alice', <String, dynamic>{
      'rank_threshold': 10,
      'frozen': false,
      'rankings': <Map<String, dynamic>>[
        <String, dynamic>{'user_id': 'alice', 'rank': 1, 'score': 42},
      ],
    });

    final Map<String, dynamic>? cached = await store.load('alice');
    expect(cached?['rank_threshold'], 10);
    expect(cached?['rankings'], hasLength(1));
    expect(cached?['cached_at'], isA<String>());
    expect(await store.load('bob'), isNull);
  });

  test('ignores malformed cached scoreboards', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'local_scoreboard_v1:alice': 'not-json',
    });

    expect(await LocalScoreboardStore().load('alice'), isNull);
  });

  test(
    'stores scoreboard pages and the current user rank separately',
    () async {
      final LocalScoreboardStore store = LocalScoreboardStore();

      await store.savePage(
        'alice',
        <String, dynamic>{
          'offset': 20,
          'limit': 20,
          'rankings': <Map<String, dynamic>>[
            <String, dynamic>{'user_id': 'page-two', 'rank': 21},
          ],
        },
        offset: 20,
        limit: 20,
      );
      await store.saveMyRank('alice', <String, dynamic>{
        'user_id': 'alice',
        'rank': 87,
        'score': 123,
      });

      final Map<String, dynamic>? page = await store.loadPage(
        'alice',
        offset: 20,
        limit: 20,
      );
      final Map<String, dynamic>? me = await store.loadMyRank('alice');

      expect(page?['rankings'], hasLength(1));
      expect(me?['rank'], 87);
      expect(await store.loadPage('alice', offset: 40, limit: 20), isNull);
    },
  );
}
