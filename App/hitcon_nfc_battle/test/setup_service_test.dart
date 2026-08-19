import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hitcon_nfc_battle/services/setup_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('completing setup queues the one-time manual prompt', () async {
    final SetupService service = SetupService();

    await service.markComplete('user-1');

    expect(await service.isComplete('user-1'), isTrue);
    expect(await service.shouldPromptManual('user-1'), isTrue);

    await service.markManualPromptHandled('user-1');

    expect(await service.isComplete('user-1'), isTrue);
    expect(await service.shouldPromptManual('user-1'), isFalse);
  });

  test('reset clears setup completion and the pending manual prompt', () async {
    final SetupService service = SetupService();
    await service.markComplete('user-1');

    await service.reset('user-1');

    expect(await service.isComplete('user-1'), isFalse);
    expect(await service.shouldPromptManual('user-1'), isFalse);
  });
}
