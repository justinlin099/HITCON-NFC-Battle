import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:hitcon_nfc_battle/services/nfc_battle_api_client.dart';

void main() {
  test(
    'recognizes connection failures without treating API errors as offline',
    () {
      expect(
        isNetworkConnectionError(const SocketException('offline')),
        isTrue,
      );
      expect(isNetworkConnectionError(TimeoutException('slow')), isTrue);
      expect(
        isNetworkConnectionError(const ApiException(503, 'Unavailable')),
        isFalse,
      );
    },
  );
}
