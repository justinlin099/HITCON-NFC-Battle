import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hitcon_nfc_battle/services/nfc_tag_payload.dart';
import 'package:nfc_manager/nfc_manager.dart';

void main() {
  test('keeps the URI first and appends the Android application record', () {
    final Uri uri = Uri.parse(
      'https://game.hitcon2026.online/b?u=test_attendee_001',
    );

    final NdefMessage message = NfcTagPayload.buildUriMessage(uri);

    expect(message.records, hasLength(2));
    expect(
      message.records.first.typeNameFormat,
      NdefTypeNameFormat.nfcWellknown,
    );
    expect(message.records.first.type, <int>[0x55]);

    final NdefRecord applicationRecord = message.records.last;
    expect(applicationRecord.typeNameFormat, NdefTypeNameFormat.nfcExternal);
    expect(utf8.decode(applicationRecord.type), 'android.com:pkg');
    expect(
      utf8.decode(applicationRecord.payload),
      NfcTagPayload.androidPackageName,
    );
  });

  test('reads the user ID from the canonical tag URI', () {
    final NdefMessage message = NfcTagPayload.buildUriMessage(
      Uri.parse('https://game.hitcon2026.online/b?u=test_attendee_004'),
    );

    expect(NfcTagPayload.readUserId(message), 'test_attendee_004');
  });

  test('does not trust a user ID from another host', () {
    final NdefMessage message = NfcTagPayload.buildUriMessage(
      Uri.parse('https://example.com/b?u=forged_user'),
    );

    expect(NfcTagPayload.readUserId(message), isNull);
  });
}
