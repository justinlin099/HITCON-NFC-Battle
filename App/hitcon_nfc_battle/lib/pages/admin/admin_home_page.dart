import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';

import '../../services/auth_service.dart';
import '../../services/ntag_security_service.dart';
import '../user/pixel_theme.dart';

class AdminHomePage extends StatefulWidget {
  const AdminHomePage({super.key});

  @override
  State<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends State<AdminHomePage> {
  @override
  void initState() {
    super.initState();
    PixelTheme.active = PixelTheme.getPalette(PixelTheme.defaultScheme);
    NfcManager.instance.stopSession();
  }

  @override
  Widget build(BuildContext context) {
    PixelTheme.active = PixelTheme.getPalette(PixelTheme.defaultScheme);

    return DefaultTextStyle.merge(
      style: const TextStyle(fontFamily: 'Unifont'),
      child: DefaultTabController(
        length: 3,
        child: Scaffold(
          backgroundColor: PixelTheme.bgDark,
          appBar: AppBar(
            backgroundColor: PixelTheme.bgMid,
            foregroundColor: PixelTheme.accent,
            title: const Text('管理者工具'),
            bottom: TabBar(
              indicatorColor: PixelTheme.accent,
              labelColor: PixelTheme.accent,
              unselectedLabelColor: PixelTheme.textGray,
              tabs: const [
                Tab(text: '寫入 Tag'),
                Tab(text: '確認領獎'),
              ],
            ),
          ),
          body: const TabBarView(
            children: [
              AdminTagWriterPage(),
              AdminPrizeClaimPage(),
              AdminTagUnlockPage(),
            ],
          ),
        ),
      ),
    );
  }
}

class AdminTagWriterPage extends StatefulWidget {
  const AdminTagWriterPage({super.key});

  @override
  State<AdminTagWriterPage> createState() => _AdminTagWriterPageState();
}

class _AdminTagWriterPageState extends State<AdminTagWriterPage> {
  static const String _blankAppUri = 'https://game.hitcon2026.online/b';

  final TextEditingController _tagIdController = TextEditingController(
    text: 'CARD-001',
  );
  final TextEditingController _titleController = TextEditingController(
    text: 'HITCON Card',
  );
  final TextEditingController _emojiController = TextEditingController(
    text: '🌐',
  );
  final TextEditingController _labelController = TextEditingController(
    text: 'WEB',
  );
  final TextEditingController _linkController = TextEditingController(
    text: 'https://hitcon.org',
  );

  String _status = '請填寫資料後按下寫入';
  String _lastUid = '-';
  bool _isWriting = false;

  @override
  void dispose() {
    _tagIdController.dispose();
    _titleController.dispose();
    _emojiController.dispose();
    _labelController.dispose();
    _linkController.dispose();
    NfcManager.instance.stopSession();
    super.dispose();
  }

  Future<void> _writeTag() async {
    if (_isWriting) {
      return;
    }

    final bool isAvailable = await NfcManager.instance.isAvailable();
    if (!isAvailable) {
      setState(() {
        _status = '此裝置不支援 NFC 或 NFC 未開啟';
      });
      return;
    }

    setState(() {
      _isWriting = true;
      _status = '請將要寫入的 Tag 靠近手機';
      _lastUid = '-';
    });

    await NfcManager.instance.stopSession();
    await NfcManager.instance.startSession(
      onDiscovered: (NfcTag tag) async {
        final String uid = _readTagId(tag);
        final Ndef? ndef = Ndef.from(tag);
        if (ndef == null || !ndef.isWritable) {
          await NfcManager.instance.stopSession();
          if (!mounted) {
            return;
          }
          setState(() {
            _isWriting = false;
            _lastUid = uid.isEmpty ? '-' : uid;
            _status = '這張 Tag 不支援 NDEF 寫入';
          });
          return;
        }

        try {
          await ndef.write(_buildTagMessage());
          await NfcManager.instance.stopSession();
          if (!mounted) {
            return;
          }
          setState(() {
            _isWriting = false;
            _lastUid = uid.isEmpty ? '-' : uid;
            _status = '寫入完成';
          });
        } catch (error) {
          await NfcManager.instance.stopSession();
          if (!mounted) {
            return;
          }
          setState(() {
            _isWriting = false;
            _lastUid = uid.isEmpty ? '-' : uid;
            _status = '寫入失敗: $error';
          });
        }
      },
      onError: (dynamic error) async {
        await NfcManager.instance.stopSession();
        if (!mounted) {
          return;
        }
        setState(() {
          _isWriting = false;
          _status = 'NFC 錯誤: $error';
        });
      },
    );
  }

  NdefMessage _buildTagMessage() {
    final String tagId = _tagIdController.text.trim();
    final String title = _titleController.text.trim();
    final String emoji = _emojiController.text.trim();
    final String label = _labelController.text.trim();
    final String link = _normalizedLink;

    return NdefMessage(<NdefRecord>[
      _buildUriRecord(_blankAppUri),
      _buildTextRecord('tag_id', tagId),
      _buildTextRecord('card_title', title),
      _buildTextRecord('attribute_emoji', emoji),
      _buildTextRecord('attribute_label', label),
      _buildTextRecord('link', link),
    ]);
  }

  String get _normalizedLink {
    final String raw = _linkController.text.trim();
    if (raw.isEmpty) {
      return 'https://hitcon.org';
    }
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return raw;
    }
    return 'https://$raw';
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PixelPanel(
            title: 'Tag 資料',
            children: [
              _PixelInput(label: 'Tag ID', controller: _tagIdController),
              _PixelInput(label: '卡片名稱', controller: _titleController),
              _PixelInput(label: 'Emoji', controller: _emojiController),
              _PixelInput(label: '屬性名稱', controller: _labelController),
              _PixelInput(label: '連結', controller: _linkController),
            ],
          ),
          const SizedBox(height: 12),
          _PixelPanel(
            title: '寫入狀態',
            children: [
              _StatusLine(label: '狀態', value: _status),
              _StatusLine(label: 'UID', value: _lastUid),
              _StatusLine(label: 'Landing URL', value: _previewLandingUrl),
            ],
          ),
          const SizedBox(height: 14),
          _PixelButton(
            label: _isWriting ? '等待 Tag...' : '寫入 Tag',
            color: PixelTheme.accent,
            onTap: _writeTag,
          ),
        ],
      ),
    );
  }

  String get _previewLandingUrl {
    return _blankAppUri;
  }
}

class AdminPrizeClaimPage extends StatefulWidget {
  const AdminPrizeClaimPage({super.key});

  @override
  State<AdminPrizeClaimPage> createState() => _AdminPrizeClaimPageState();
}

class _AdminPrizeClaimPageState extends State<AdminPrizeClaimPage> {
  final AuthService _authService = AuthService();
  String _status = '按下開始掃描，刷會眾 Tag 確認領獎';
  String _lastUid = '-';
  String _lastUserId = '-';
  String _claimCode = '-';
  bool _isScanning = false;

  @override
  void dispose() {
    NfcManager.instance.stopSession();
    super.dispose();
  }

  Future<void> _startScan() async {
    if (_isScanning) {
      return;
    }

    final bool isAvailable = await NfcManager.instance.isAvailable();
    if (!isAvailable) {
      setState(() {
        _status = '此裝置不支援 NFC 或 NFC 未開啟';
      });
      return;
    }

    setState(() {
      _isScanning = true;
      _status = '請刷會眾 Tag';
      _lastUid = '-';
      _lastUserId = '-';
      _claimCode = '-';
    });

    await NfcManager.instance.stopSession();
    await NfcManager.instance.startSession(
      onDiscovered: (NfcTag tag) async {
        final String uid = _readTagId(tag);
        final Map<String, String> records = await _readTextRecords(tag);
        final String userId = records['user_id'] ?? records['owner'] ?? '';
        final Map<String, dynamic>? result = await _authService
            .confirmPrizeClaim(tagUid: uid, userId: userId);

        await NfcManager.instance.stopSession();
        if (!mounted) {
          return;
        }

        setState(() {
          _isScanning = false;
          _lastUid = uid.isEmpty ? '-' : uid;
          _lastUserId = userId.isEmpty ? '(Tag 未寫入 user_id)' : userId;
          if (result == null) {
            _status = '確認失敗，請稍後再試';
            _claimCode = '-';
            return;
          }
          final bool alreadyClaimed = result['already_claimed'] == true;
          _status = alreadyClaimed ? '此會眾已領過獎' : '領獎確認完成';
          _claimCode = result['claim_code'] as String? ?? '-';
        });
      },
      onError: (dynamic error) async {
        await NfcManager.instance.stopSession();
        if (!mounted) {
          return;
        }
        setState(() {
          _isScanning = false;
          _status = 'NFC 錯誤: $error';
        });
      },
    );
  }

  Future<void> _stopScan() async {
    await NfcManager.instance.stopSession();
    if (!mounted) {
      return;
    }
    setState(() {
      _isScanning = false;
      _status = '已停止掃描';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PixelPanel(
            title: '領獎確認',
            children: [
              _StatusLine(label: '狀態', value: _status),
              _StatusLine(label: 'UID', value: _lastUid),
              _StatusLine(label: 'User ID', value: _lastUserId),
              _StatusLine(label: '收件編號', value: _claimCode),
            ],
          ),
          const SizedBox(height: 14),
          _PixelButton(
            label: _isScanning ? '停止掃描' : '開始掃描',
            color: _isScanning ? PixelTheme.warning : PixelTheme.accent,
            onTap: _isScanning ? _stopScan : _startScan,
          ),
        ],
      ),
    );
  }
}

class AdminTagUnlockPage extends StatefulWidget {
  const AdminTagUnlockPage({super.key});

  @override
  State<AdminTagUnlockPage> createState() => _AdminTagUnlockPageState();
}

class _AdminTagUnlockPageState extends State<AdminTagUnlockPage> {
  static const NtagSecurityService _security = NtagSecurityService();

  String _status = '請掃描需要解鎖重寫的 NTAG';
  String _lastUid = '-';
  bool _isUnlocking = false;

  @override
  void dispose() {
    NfcManager.instance.stopSession();
    super.dispose();
  }

  Future<void> _unlockTag() async {
    if (_isUnlocking) {
      return;
    }

    final bool isAvailable = await NfcManager.instance.isAvailable();
    if (!isAvailable) {
      setState(() {
        _status = '此裝置不支援 NFC 或 NFC 未開啟';
      });
      return;
    }

    setState(() {
      _isUnlocking = true;
      _status = '請靠近要解鎖的 NTAG';
      _lastUid = '-';
    });

    await NfcManager.instance.stopSession();
    await NfcManager.instance.startSession(
      onDiscovered: (NfcTag tag) async {
        final String uid = _security.readTagId(tag);
        final NtagLockSecret? secret = await AuthService()
            .requestNtagLockSecret(uid: uid, purpose: 'unlock');
        final NtagSecurityResult result = secret == null
            ? const NtagSecurityResult(
                success: false,
                message: '無法從 Server 取得 NTAG 解鎖密碼',
              )
            : await _security.unlockForRewrite(tag, secret);

        await NfcManager.instance.stopSession();
        if (!mounted) {
          return;
        }

        setState(() {
          _isUnlocking = false;
          _lastUid = uid.isEmpty ? '-' : uid;
          _status = result.message;
        });
      },
      onError: (dynamic error) async {
        await NfcManager.instance.stopSession();
        if (!mounted) {
          return;
        }
        setState(() {
          _isUnlocking = false;
          _status = 'NFC 錯誤: $error';
        });
      },
    );
  }

  Future<void> _stopUnlock() async {
    await NfcManager.instance.stopSession();
    if (!mounted) {
      return;
    }
    setState(() {
      _isUnlocking = false;
      _status = '已停止解鎖';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PixelPanel(
            title: 'UNLOCK TAG',
            children: [
              _StatusLine(label: '狀態', value: _status),
              _StatusLine(label: 'UID', value: _lastUid),
              _StatusLine(
                label: '說明',
                value:
                    '此功能會用 Tag UID 推導密碼，驗證後解除 AUTH0 保護並重設 PWD/PACK，讓此 NTAG 可以重新寫入。',
              ),
            ],
          ),
          const SizedBox(height: 14),
          _PixelButton(
            label: _isUnlocking ? '停止掃描' : '解鎖 Tag 以便重寫',
            color: _isUnlocking ? PixelTheme.warning : PixelTheme.accent,
            onTap: _isUnlocking ? _stopUnlock : _unlockTag,
          ),
        ],
      ),
    );
  }
}

class _PixelPanel extends StatelessWidget {
  const _PixelPanel({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: PixelTheme.bgMid,
        border: Border.all(color: PixelTheme.textWhite, width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black, blurRadius: 0, offset: Offset(4, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: PixelTheme.accent,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _PixelInput extends StatelessWidget {
  const _PixelInput({required this.label, required this.controller});

  final String label;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        style: TextStyle(color: PixelTheme.textWhite, fontFamily: 'Unifont'),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: PixelTheme.textGray),
          filled: true,
          fillColor: PixelTheme.bgDark,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide(color: PixelTheme.border, width: 2),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide(color: PixelTheme.accent, width: 2),
          ),
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: PixelTheme.textGray,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: PixelTheme.textWhite,
              fontSize: 12,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _PixelButton extends StatelessWidget {
  const _PixelButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: PixelTheme.bgMid,
          border: Border.all(color: color, width: 2),
          boxShadow: const [
            BoxShadow(color: Colors.black, blurRadius: 0, offset: Offset(4, 4)),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

String _readTagId(NfcTag tag) {
  final Map<String, dynamic> data = tag.data;
  final dynamic idBytes =
      data['nfca']?['identifier'] ??
      data['mifareclassic']?['identifier'] ??
      data['mifareultralight']?['identifier'];

  if (idBytes is! List) {
    return '';
  }
  return idBytes
      .whereType<int>()
      .map((int b) => b.toRadixString(16).padLeft(2, '0'))
      .join(':')
      .toUpperCase();
}

Future<Map<String, String>> _readTextRecords(NfcTag tag) async {
  final Ndef? ndef = Ndef.from(tag);
  final NdefMessage? message = ndef?.cachedMessage;
  final Map<String, String> records = <String, String>{};
  if (message == null) {
    return records;
  }

  for (final NdefRecord record in message.records) {
    if (record.typeNameFormat != NdefTypeNameFormat.nfcWellknown ||
        record.type.isEmpty ||
        record.type.first != 0x54 ||
        record.payload.length <= 1) {
      continue;
    }
    final String key = utf8.decode(record.identifier, allowMalformed: true);
    if (key.isEmpty) {
      continue;
    }
    final int languageCodeLength = record.payload.first & 0x3F;
    final int textStart = 1 + languageCodeLength;
    if (record.payload.length <= textStart) {
      continue;
    }
    records[key] = utf8.decode(
      record.payload.sublist(textStart),
      allowMalformed: true,
    );
  }
  return records;
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

  return NdefRecord(
    typeNameFormat: NdefTypeNameFormat.nfcWellknown,
    type: Uint8List.fromList(<int>[0x55]),
    identifier: Uint8List(0),
    payload: Uint8List.fromList(<int>[prefixIndex, ...utf8.encode(body)]),
  );
}

NdefRecord _buildTextRecord(String identifier, String text) {
  final List<int> languageCode = utf8.encode('en');
  return NdefRecord(
    typeNameFormat: NdefTypeNameFormat.nfcWellknown,
    type: Uint8List.fromList(<int>[0x54]),
    identifier: Uint8List.fromList(utf8.encode(identifier)),
    payload: Uint8List.fromList(<int>[
      languageCode.length,
      ...languageCode,
      ...utf8.encode(text),
    ]),
  );
}
