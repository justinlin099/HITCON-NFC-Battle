import 'dart:convert';
import 'dart:typed_data';

import 'package:nfc_manager/nfc_manager.dart';

abstract final class NfcTagPayload {
  static const String androidPackageName = 'org.hitcon.nfcbattle';
  static const List<String> _uriPrefixes = <String>[
    '',
    'http://www.',
    'https://www.',
    'http://',
    'https://',
    'tel:',
    'mailto:',
    'ftp://anonymous:anonymous@',
    'ftp://ftp.',
    'ftps://',
    'sftp://',
    'smb://',
    'nfs://',
    'ftp://',
    'dav://',
    'news:',
    'telnet://',
    'imap:',
    'rtsp://',
    'urn:',
    'pop:',
    'sip:',
    'sips:',
    'tftp:',
    'btspp://',
    'btl2cap://',
    'btgoep://',
    'tcpobex://',
    'irdaobex://',
    'file://',
    'urn:epc:id:',
    'urn:epc:tag:',
    'urn:epc:pat:',
    'urn:epc:raw:',
    'urn:epc:',
    'urn:nfc:',
  ];

  static NdefRecord buildUriRecord(Uri uri) => NdefRecord.createUri(uri);

  static NdefRecord buildAndroidApplicationRecord() {
    return NdefRecord.createExternal(
      'android.com',
      'pkg',
      Uint8List.fromList(utf8.encode(androidPackageName)),
    );
  }

  static NdefMessage buildUriMessage(
    Uri uri, {
    Iterable<NdefRecord> additionalRecords = const <NdefRecord>[],
  }) {
    return NdefMessage(<NdefRecord>[
      buildUriRecord(uri),
      ...additionalRecords,
      buildAndroidApplicationRecord(),
    ]);
  }

  static Uri? readUriRecord(NdefRecord record) {
    if (record.typeNameFormat != NdefTypeNameFormat.nfcWellknown ||
        record.type.length != 1 ||
        record.type.first != 0x55 ||
        record.payload.isEmpty) {
      return null;
    }
    final int prefixIndex = record.payload.first;
    if (prefixIndex >= _uriPrefixes.length) {
      return null;
    }
    final String suffix = utf8.decode(
      record.payload.sublist(1),
      allowMalformed: true,
    );
    return Uri.tryParse('${_uriPrefixes[prefixIndex]}$suffix');
  }

  static String? readUserId(NdefMessage? message) {
    if (message == null) {
      return null;
    }
    for (final NdefRecord record in message.records) {
      final Uri? uri = readUriRecord(record);
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host != 'game.hitcon2026.online' ||
          uri.path != '/b') {
        continue;
      }
      final String userId = (uri.queryParameters['u'] ?? '').trim();
      if (userId.isNotEmpty) {
        return userId;
      }
    }
    return null;
  }
}
