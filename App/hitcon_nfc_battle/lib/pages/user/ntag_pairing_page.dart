import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';

import '../../services/auth_service.dart';
import '../../services/ntag_security_service.dart';
import 'pixel_theme.dart';

Future<String?> openNtagPairingScanPage(BuildContext context) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute<String>(builder: (_) => const NtagPairingPage()),
  );
}

class NtagPairingPage extends StatefulWidget {
  const NtagPairingPage({super.key});

  @override
  State<NtagPairingPage> createState() => _NtagPairingPageState();
}

class _NtagPairingPageState extends State<NtagPairingPage> {
  static const String _targetUri = 'https://game.hitcon2026.online/b';
  static const NtagSecurityService _security = NtagSecurityService();

  String _status = '準備掃描 NTAG...';
  String _tagId = '-';
  String _userId = '';
  bool _isReading = false;

  @override
  void initState() {
    super.initState();
    _userId = AuthService().currentUserId ?? '';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startSession();
    });
  }

  Future<void> _startSession() async {
    if (_isReading) {
      return;
    }

    final bool isAvailable = await NfcManager.instance.isAvailable();
    if (!isAvailable) {
      setState(() {
        _status = 'NFC is unavailable or disabled';
      });
      return;
    }

    if (_userId.trim().isEmpty) {
      setState(() {
        _status = '請先登入取得 user_id';
      });
      return;
    }

    setState(() {
      _isReading = true;
      _status = '正在等待 NFC Tag...';
    });

    await NfcManager.instance.startSession(
      onDiscovered: (NfcTag tag) async {
        final String parsedTagId = _security.readTagId(tag);
        final bool ndefWritten = await _writeUserIdToTag(tag, _userId);
        final NtagLockSecret? lockSecret = ndefWritten
            ? await AuthService().requestNtagLockSecret(
                uid: parsedTagId,
                purpose: 'lock',
              )
            : null;
        final NtagSecurityResult lockResult = ndefWritten
            ? lockSecret == null
                  ? const NtagSecurityResult(
                      success: false,
                      message: '無法從 Server 取得 NTAG 鎖定密碼',
                    )
                  : await _security.protectForRewrite(tag, lockSecret)
            : const NtagSecurityResult(
                success: false,
                message: '寫入失敗：此 Tag 不支援 NDEF 寫入',
              );

        bool pairSuccess = false;
        if (ndefWritten && lockResult.success && parsedTagId.isNotEmpty) {
          pairSuccess = await AuthService().pairNfcTag(parsedTagId);
        }

        if (!mounted) {
          return;
        }

        setState(() {
          _tagId = parsedTagId.isEmpty ? '(讀不到 Tag ID)' : parsedTagId;
          if (!ndefWritten || !lockResult.success) {
            _status = lockResult.message;
          } else if (!pairSuccess) {
            _status = '${lockResult.message}\nAPI 配對失敗，請重試';
          } else {
            _status = '已寫入 user_id 並完成 NTAG 密碼鎖定';
          }
        });

        final NavigatorState navigator = Navigator.of(context);
        await NfcManager.instance.stopSession();
        if (pairSuccess) {
          navigator.pop(_tagId);
        } else {
          setState(() {
            _isReading = false;
          });
        }
      },
      onError: (dynamic error) async {
        if (!mounted) {
          return;
        }
        setState(() {
          _status = 'NFC 讀取失敗：$error';
          _isReading = false;
        });
        await NfcManager.instance.stopSession();
      },
    );
  }

  Future<bool> _writeUserIdToTag(NfcTag tag, String userId) async {
    final Ndef? ndef = Ndef.from(tag);
    if (ndef == null || !ndef.isWritable) {
      return false;
    }

    await ndef.write(
      NdefMessage(<NdefRecord>[
        _buildUriRecord(_targetUri),
        _buildTextRecord('user_id', userId),
      ]),
    );
    return true;
  }

  NdefRecord _buildUriRecord(String uri) {
    const List<String> prefixes = <String>[
      '',
      'http://www.',
      'https://www.',
      'http://',
      'https://',
    ];

    int prefixIndex = 0;
    String body = uri;
    for (int i = prefixes.length - 1; i >= 0; i -= 1) {
      if (prefixes[i].isNotEmpty && uri.startsWith(prefixes[i])) {
        prefixIndex = i;
        body = uri.substring(prefixes[i].length);
        break;
      }
    }

    final List<int> payload = <int>[prefixIndex, ...utf8.encode(body)];
    return NdefRecord(
      typeNameFormat: NdefTypeNameFormat.nfcWellknown,
      type: Uint8List.fromList(<int>[0x55]),
      identifier: Uint8List(0),
      payload: Uint8List.fromList(payload),
    );
  }

  NdefRecord _buildTextRecord(String identifier, String text) {
    final List<int> encodedText = utf8.encode(text);
    final List<int> languageCode = utf8.encode('en');
    return NdefRecord(
      typeNameFormat: NdefTypeNameFormat.nfcWellknown,
      type: Uint8List.fromList(<int>[0x54]),
      identifier: Uint8List.fromList(utf8.encode(identifier)),
      payload: Uint8List.fromList(<int>[0x65, ...languageCode, ...encodedText]),
    );
  }

  @override
  void dispose() {
    NfcManager.instance.stopSession();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        textTheme: Theme.of(context).textTheme.apply(fontFamily: 'Unifont'),
        primaryTextTheme: Theme.of(
          context,
        ).primaryTextTheme.apply(fontFamily: 'Unifont'),
      ),
      child: Scaffold(
        backgroundColor: PixelTheme.bgDark,
        appBar: AppBar(
          backgroundColor: PixelTheme.bgMid,
          foregroundColor: PixelTheme.accent,
          title: const Text('NTAG Badge 配對'),
        ),
        body: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: PixelTheme.bgMid,
              border: Border.all(color: PixelTheme.textWhite, width: 2),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black,
                  blurRadius: 0,
                  offset: Offset(4, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.nfc_rounded, size: 48, color: PixelTheme.accent),
                const SizedBox(height: 12),
                Text(
                  '請把自己的 Badge 靠近手機',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: PixelTheme.textWhite,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _status,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: PixelTheme.textGray, fontSize: 12),
                ),
                const SizedBox(height: 10),
                Text(
                  'UID: $_tagId',
                  style: TextStyle(
                    color: PixelTheme.textWhite,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'user_id: ${_userId.isEmpty ? '-' : _userId}',
                  style: TextStyle(color: PixelTheme.textWhite, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
