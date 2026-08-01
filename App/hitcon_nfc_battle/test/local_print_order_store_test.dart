import 'package:flutter_test/flutter_test.dart';
import 'package:hitcon_nfc_battle/services/local_print_order_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('saves print orders separately for each user', () async {
    final LocalPrintOrderStore store = LocalPrintOrderStore();
    const LocalPrintOrder first = LocalPrintOrder(
      id: 'ORDER-1',
      barcodeValue: 'BARCODE-1',
      fileName: 'first.png',
      format: 'PNG',
    );
    const LocalPrintOrder second = LocalPrintOrder(
      id: 'ORDER-2',
      barcodeValue: 'BARCODE-2',
      fileName: 'second.png',
      format: 'PNG',
    );

    expect(await store.save('user-1', first), isTrue);
    expect(await store.save('user-2', second), isTrue);

    expect((await store.load('user-1'))?.id, 'ORDER-1');
    expect((await store.load('user-1'))?.barcodeValue, 'BARCODE-1');
    expect((await store.load('user-2'))?.id, 'ORDER-2');
  });

  test('ignores malformed saved print orders', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'local_print_order_v1:user-1': '{"id":"ORDER-1"}',
    });

    expect(await LocalPrintOrderStore().load('user-1'), isNull);
  });
}
