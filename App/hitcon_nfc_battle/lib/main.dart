import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NTag Reader',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      ),
      home: const NTagReaderPage(),
    );
  }
}

class NTagReaderPage extends StatefulWidget {
  const NTagReaderPage({super.key});

  @override
  State<NTagReaderPage> createState() => _NTagReaderPageState();
}

class _NTagReaderPageState extends State<NTagReaderPage> {
  static const String _targetHost = 'game.hitcon2026.online';
  static const String _targetPath = '/b';

  final TextEditingController _userIdController = TextEditingController();
  final TextEditingController _secretKeyController = TextEditingController();
  final AppLinks _appLinks = AppLinks();

  StreamSubscription<Uri>? _linkSubscription;

  String _status = '初始化中...';
  String _tagId = '-';
  List<String> _records = <String>[];
  String _lastIncomingUri = '-';
  bool _isReading = false;
  bool _autoWriteEnabled = true;
  String _lastTagId = '';
  DateTime _lastReadTime = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _initAppLinks();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startAutoRead();
    });
  }

  Future<void> _initAppLinks() async {
    try {
      final Uri? initialLink = await _appLinks.getInitialLink();
      if (initialLink != null) {
        _consumeIncomingUri(initialLink);
      }
    } catch (_) {
      // Ignore startup deep link errors and keep NFC flow running.
    }

    _linkSubscription = _appLinks.uriLinkStream.listen(
      (Uri uri) {
        _consumeIncomingUri(uri);
      },
      onError: (_) {
        setState(() {
          _status = '收到連結事件，但解析失敗';
        });
      },
    );
  }

  void _consumeIncomingUri(Uri uri) {
    final bool hostMatches = uri.host.toLowerCase() == _targetHost;
    final bool pathMatches = uri.path == _targetPath || uri.path == '$_targetPath/';
    if (!hostMatches || !pathMatches) {
      return;
    }

    final String userId = uri.queryParameters['u'] ?? '';
    final String secretKey = uri.queryParameters['k'] ?? '';

    setState(() {
      _lastIncomingUri = uri.toString();
      _status = '已收到外部掃描連結';
    });

    if (userId.isNotEmpty && secretKey.isNotEmpty) {
      _userIdController.text = userId;
      _secretKeyController.text = secretKey;
      setState(() {
        _status = '已由外部連結帶入 user_id / secret_key';
      });
    }
  }

  String _buildTargetUri() {
    final String userId = _userIdController.text.trim();

    // 只包含 user_id，secret 另外寫成獨立記錄
    if (userId.isNotEmpty) {
      final Uri uri = Uri.https(_targetHost, _targetPath, <String, String>{
        'u': userId,
      });
      return uri.toString();
    }

    return Uri.https(_targetHost, _targetPath).toString();
  }

  Future<bool> _writeUriToTag(NfcTag tag, String uri) async {
    final String secretKey = _secretKeyController.text.trim();
    
    // 建立多個 NDEF 記錄：URI + Secret（如果存在）
    final List<NdefRecord> records = <NdefRecord>[
      _buildUriRecord(uri),
    ];
    
    // 如果有 secret，額外寫入文本記錄
    if (secretKey.isNotEmpty) {
      records.add(_buildTextRecord('secret_key', secretKey));
    }
    
    final NdefMessage message = NdefMessage(records);
    final Ndef? ndef = Ndef.from(tag);

    if (ndef == null || !ndef.isWritable) {
      return false;
    }

    await ndef.write(message);
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
    for (int i = prefixes.length - 1; i >= 0; i--) {
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
    // 構建 NDEF Text record (TNF = NFC Well-known, Type = 'T')
    // Payload: [狀態碼][語言碼][文本]
    // 狀態碼：0x65 = UTF-8 編碼 + 語言碼長度 2 ("en")
    final List<int> encodedText = utf8.encode(text);
    final List<int> identifierBytes = utf8.encode(identifier);
    final List<int> languageCode = utf8.encode('en'); // 語言代碼 "en"
    
    // Payload 結構：
    // Byte 0-5: 狀態碼 (0x65 = UTF-8, 語言碼長度為 2)
    // Bytes 1-2: 語言碼 ('en')
    // Bytes 3+: 文本內容
    final List<int> payload = <int>[
      0x65, // UTF-8 編碼，語言碼長度 2
      ...languageCode,
      ...encodedText,
    ];

    return NdefRecord(
      typeNameFormat: NdefTypeNameFormat.nfcWellknown,
      type: Uint8List.fromList(<int>[0x54]), // 'T' = Text record
      identifier: Uint8List.fromList(identifierBytes),
      payload: Uint8List.fromList(payload),
    );
  }

  Future<void> _startAutoRead() async {
    final bool isAvailable = await NfcManager.instance.isAvailable();
    if (!isAvailable) {
      setState(() {
        _status = '此裝置不支援 NFC 或 NFC 未開啟';
        _isReading = false;
      });
      return;
    }

    if (_isReading) {
      return;
    }

    setState(() {
      _isReading = true;
      _status = '自動感應中... 請將 NTag 貼近手機';
      _tagId = '-';
      _records = <String>[];
    });

    await NfcManager.instance.startSession(
      onDiscovered: (NfcTag tag) async {
        final Map<String, dynamic> data = tag.data;
        final dynamic idBytes = data['nfca']?['identifier'] ??
            data['mifareclassic']?['identifier'] ??
            data['mifareultralight']?['identifier'];

        final String parsedTagId = _toHexString(idBytes);
        final DateTime now = DateTime.now();
        final bool isDuplicateRead =
            parsedTagId.isNotEmpty &&
            parsedTagId == _lastTagId &&
            now.difference(_lastReadTime).inMilliseconds < 1200;

        if (isDuplicateRead) {
          return;
        }

        _lastTagId = parsedTagId;
        _lastReadTime = now;

        final Ndef? ndef = Ndef.from(tag);
        final List<String> parsedRecords = <String>[];
        final List<String> existingSecrets = <String>[];

        if (ndef != null) {
          final NdefMessage? message = ndef.cachedMessage;
          if (message != null) {
            for (final NdefRecord record in message.records) {
              parsedRecords.add(_parseRecord(record));
              final String? secret = _extractSecretKeyFromRecord(record);
              if (secret != null) {
                existingSecrets.add(secret);
              }
            }
          }
        }

        String writeMessage = '';
        if (_autoWriteEnabled) {
          final String targetUri = _buildTargetUri();
          final String targetSecret = _secretKeyController.text.trim();
          final bool uriMatches = parsedRecords.contains(targetUri);
          final bool secretMatches = targetSecret.isEmpty
              ? existingSecrets.isEmpty
              : existingSecrets.length == 1 && existingSecrets.first == targetSecret;

          if (uriMatches && secretMatches) {
            writeMessage = targetSecret.isEmpty
                ? '（Tag 已是目標 URI，略過寫入）'
                : '（Tag 已是目標 URI + secret，略過寫入）';
          } else {
            try {
              final bool writeSuccess = await _writeUriToTag(tag, targetUri);
              writeMessage = writeSuccess ? '（已寫入 URI）' : '（無法寫入：Tag 不支援寫入）';
            } catch (e) {
              writeMessage = '（寫入失敗：$e）';
            }
          }
        }

        setState(() {
          _tagId = parsedTagId.isEmpty ? '(讀不到 Tag ID)' : parsedTagId;
          _records = parsedRecords;
          _status = parsedRecords.isEmpty
              ? '已讀取，等待下一張 NTag（無可解析 NDEF）$writeMessage'
              : '已讀取，等待下一張 NTag$writeMessage';
        });
      },
      onError: (dynamic error) async {
        setState(() {
          _status = '讀取失敗: $error';
          _isReading = false;
        });
        await NfcManager.instance.stopSession();
      },
    );
  }

  String _toHexString(dynamic bytes) {
    if (bytes is! List) {
      return '';
    }
    final Iterable<int> values = bytes.whereType<int>();
    return values.map((int b) => b.toRadixString(16).padLeft(2, '0')).join(':').toUpperCase();
  }

  String _parseRecord(NdefRecord record) {
    if (record.typeNameFormat == NdefTypeNameFormat.nfcWellknown &&
        record.type.isNotEmpty &&
        record.type.first == 0x54 &&
        record.payload.length > 1) {
      final int languageCodeLength = record.payload.first & 0x3F;
      final int textStart = 1 + languageCodeLength;
      if (record.payload.length > textStart) {
        return String.fromCharCodes(record.payload.sublist(textStart));
      }
    }

    if (record.typeNameFormat == NdefTypeNameFormat.nfcWellknown &&
        record.type.isNotEmpty &&
        record.type.first == 0x55 &&
        record.payload.isNotEmpty) {
      const List<String> uriPrefix = <String>[
        '',
        'http://www.',
        'https://www.',
        'http://',
        'https://',
      ];
      final int code = record.payload.first;
      final String prefix = code < uriPrefix.length ? uriPrefix[code] : '';
      final String uriBody = String.fromCharCodes(record.payload.sublist(1));
      return '$prefix$uriBody';
    }

    return 'TNF=${record.typeNameFormat.name}, type=${_toHexString(record.type)}, payload=${_toHexString(record.payload)}';
  }

  String? _extractSecretKeyFromRecord(NdefRecord record) {
    if (record.typeNameFormat != NdefTypeNameFormat.nfcWellknown ||
        record.type.isEmpty ||
        record.type.first != 0x54 ||
        record.payload.length <= 1) {
      return null;
    }

    final String identifier = utf8.decode(record.identifier, allowMalformed: true);
    if (identifier != 'secret_key') {
      return null;
    }

    final int languageCodeLength = record.payload.first & 0x3F;
    final int textStart = 1 + languageCodeLength;
    if (record.payload.length <= textStart) {
      return null;
    }

    return String.fromCharCodes(record.payload.sublist(textStart));
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    _userIdController.dispose();
    _secretKeyController.dispose();
    NfcManager.instance.stopSession();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('NTag Reader'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '狀態：$_status',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Text('Tag ID: $_tagId'),
            const SizedBox(height: 8),
            Text('外部掃描 URI: $_lastIncomingUri'),
            const SizedBox(height: 16),
            TextField(
              controller: _userIdController,
              decoration: const InputDecoration(
                labelText: 'user_id',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _secretKeyController,
              decoration: const InputDecoration(
                labelText: 'secret_key',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('自動寫入 URI 到 Tag'),
              value: _autoWriteEnabled,
              contentPadding: EdgeInsets.zero,
              onChanged: (bool value) {
                setState(() {
                  _autoWriteEnabled = value;
                });
              },
            ),
            Text(
              '目標 URI: ${_buildTargetUri()}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            Text('NDEF 內容', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Expanded(
              child: _records.isEmpty
                  ? const Center(child: Text('尚未讀取到 NDEF 記錄'))
                  : ListView.separated(
                      itemCount: _records.length,
                      separatorBuilder: (_, index) => const Divider(),
                      itemBuilder: (BuildContext context, int index) {
                        return ListTile(
                          leading: CircleAvatar(child: Text('${index + 1}')),
                          title: Text(_records[index]),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
