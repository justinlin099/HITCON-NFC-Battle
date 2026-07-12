import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hitcon_nfc_battle/services/local_collection_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('imports a supported collection backup', () async {
    final LocalCollectionStore store = LocalCollectionStore();

    await store.importJson(
      'current-user',
      '{"schema":1,"user_id":"other-user","cards_by_uid":{}}',
    );

    final Map<String, dynamic> restored = await store.load('current-user');
    expect(restored['user_id'], 'current-user');
    expect(restored['schema'], 1);
  });

  test('rejects an unsupported backup schema', () async {
    final LocalCollectionStore store = LocalCollectionStore();

    expect(
      () => store.importJson('current-user', '{"schema":2,"cards_by_uid":{}}'),
      throwsFormatException,
    );
  });

  test('rejects a backup without a cards map', () async {
    final LocalCollectionStore store = LocalCollectionStore();

    expect(
      () => store.importJson('current-user', '{"schema":1}'),
      throwsFormatException,
    );
  });

  test('rejects a backup larger than the size limit', () async {
    final LocalCollectionStore store = LocalCollectionStore();
    final String oversized =
        '{"schema":1,"cards_by_uid":{},"padding":"${'a' * LocalCollectionStore.maxBackupBytes}"}';

    expect(
      () => store.importJson('current-user', oversized),
      throwsFormatException,
    );
  });
}
