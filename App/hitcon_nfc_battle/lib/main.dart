import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'l10n/app_localizations.dart';
import 'pages/admin/admin_home_page.dart';
import 'pages/user/card_collection_page.dart';
import 'pages/user/setup_page.dart';
import 'pages/debug/test_login_page.dart';
import 'services/auth_service.dart';
import 'services/nfc_deep_link_service.dart';
import 'services/ntag_security_service.dart';
import 'services/setup_service.dart';

void main() {
  runApp(const MyApp());
}

class _SessionGate extends StatefulWidget {
  const _SessionGate();

  @override
  State<_SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<_SessionGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_restoreAndRoute());
    });
  }

  Future<void> _restoreAndRoute() async {
    final AuthService auth = AuthService();
    final bool restored = await auth.restoreSession();
    if (!mounted) {
      return;
    }

    if (!restored) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const TestLoginPage()),
      );
      return;
    }

    final String? userId = auth.currentUserId;
    final bool setupComplete =
        userId != null && await SetupService().isComplete(userId);
    if (!mounted) {
      return;
    }

    final String routeName = auth.isRegularUser
        ? (setupComplete ? '/collection' : '/setup')
        : '/admin';
    Navigator.of(context).pushReplacementNamed(routeName);
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF101820),
      body: Center(child: CircularProgressIndicator(color: Color(0xFF7CFF6B))),
    );
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late final _AutoNtagScanner _autoScanner;

  @override
  void initState() {
    super.initState();
    unawaited(NfcDeepLinkService.instance.initialize());
    _autoScanner = _AutoNtagScanner(deepLinks: NfcDeepLinkService.instance);
    NfcDeepLinkService.instance.registerInAppScanStarter(_autoScanner.start);
  }

  @override
  void dispose() {
    _autoScanner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      onGenerateTitle: (BuildContext context) => context.l10n.tr('appTitle'),
      builder: (BuildContext context, Widget? child) {
        final MediaQueryData mediaQuery = MediaQuery.of(context);
        final double systemTextScale = mediaQuery.textScaler.scale(1);
        return MediaQuery(
          data: mediaQuery.copyWith(
            textScaler: TextScaler.linear(
              (systemTextScale * 1.1).clamp(0.8, 2.0),
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      ),
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      localeListResolutionCallback: _resolveLocale,
      home: const _SessionGate(),
      routes: {
        '/home': (context) => const NTagReaderPage(),
        '/admin': (context) => const AdminHomePage(),
        '/collection': (context) => const CardCollectionPage(),
        '/setup': (context) => const SetupPage(),
      },
    );
  }

  Locale _resolveLocale(
    List<Locale>? preferredLocales,
    Iterable<Locale> supportedLocales,
  ) {
    for (final Locale locale in preferredLocales ?? const <Locale>[]) {
      final String country = locale.countryCode?.toUpperCase() ?? '';
      final String script = locale.scriptCode?.toLowerCase() ?? '';
      final bool traditionalChinese =
          locale.languageCode == 'zh' &&
          (script == 'hant' ||
              country == 'TW' ||
              country == 'HK' ||
              country == 'MO');
      if (traditionalChinese) {
        return const Locale.fromSubtags(languageCode: 'zh', countryCode: 'TW');
      }
      if (locale.languageCode == 'en') {
        return const Locale('en');
      }
    }
    return const Locale('en');
  }
}

class _AutoNtagScanner {
  _AutoNtagScanner({required this.deepLinks});

  final NfcDeepLinkService deepLinks;
  static const NtagSecurityService _ntagSecurity = NtagSecurityService();
  bool _isScanning = false;
  bool _isHandling = false;
  String _lastTagId = '';
  DateTime _lastReadTime = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> start() async {
    if (_isScanning) {
      return;
    }

    final bool isAvailable = await NfcManager.instance.isAvailable();
    if (!isAvailable) {
      return;
    }

    _isScanning = true;
    await NfcManager.instance.startSession(
      onDiscovered: (NfcTag tag) async {
        if (_isHandling) {
          return;
        }

        final String uid = _ntagSecurity.readTagId(tag);
        final DateTime now = DateTime.now();
        final bool isDuplicate =
            uid.isNotEmpty &&
            uid == _lastTagId &&
            now.difference(_lastReadTime).inMilliseconds < 1200;
        if (isDuplicate) {
          return;
        }

        _lastTagId = uid;
        _lastReadTime = now;
        _isHandling = true;

        await NfcManager.instance.stopSession();
        _isScanning = false;

        final String targetUserId = _readTargetUserId(tag);
        await _handleScan(uid, targetUserId);
        _isHandling = false;
      },
      onError: (_) async {
        await NfcManager.instance.stopSession();
        _isScanning = false;
        _isHandling = false;
      },
    );
  }

  Future<void> _handleScan(String uid, String targetUserId) async {
    deepLinks.publish(
      NfcScanRequest(
        userId: targetUserId,
        physicalUid: uid,
        launchEvidence: NfcLaunchEvidence.physicalTag,
      ),
    );
  }

  String _readTargetUserId(NfcTag tag) {
    final Ndef? ndef = Ndef.from(tag);
    final NdefMessage? message = ndef?.cachedMessage;
    if (message == null) {
      return '';
    }

    for (final NdefRecord record in message.records) {
      final String? uriText = _parseUriRecord(record);
      if (uriText == null) {
        continue;
      }

      final Uri? uri = Uri.tryParse(uriText);
      if (uri == null) {
        continue;
      }

      final bool hostMatches =
          uri.host.toLowerCase() == 'game.hitcon2026.online';
      final bool pathMatches = uri.path == '/b' || uri.path == '/b/';
      if (hostMatches && pathMatches) {
        return uri.queryParameters['u'] ?? '';
      }
    }

    return '';
  }

  String? _parseUriRecord(NdefRecord record) {
    if (record.typeNameFormat != NdefTypeNameFormat.nfcWellknown ||
        record.type.isEmpty ||
        record.type.first != 0x55 ||
        record.payload.isEmpty) {
      return null;
    }

    const List<String> uriPrefix = <String>[
      '',
      'http://www.',
      'https://www.',
      'http://',
      'https://',
    ];
    final int code = record.payload.first;
    final String prefix = code < uriPrefix.length ? uriPrefix[code] : '';
    final String uriBody = utf8.decode(
      record.payload.sublist(1),
      allowMalformed: true,
    );
    return '$prefix$uriBody';
  }

  void dispose() {
    NfcManager.instance.stopSession();
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

  String _status = '';
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_status.isEmpty) {
      _status = context.l10n.tr('initializing');
    }
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
          _status = context.l10n.tr('linkParseFailed');
        });
      },
    );
  }

  void _consumeIncomingUri(Uri uri) {
    final bool hostMatches = uri.host.toLowerCase() == _targetHost;
    final bool pathMatches =
        uri.path == _targetPath || uri.path == '$_targetPath/';
    if (!hostMatches || !pathMatches) {
      return;
    }

    final String userId = uri.queryParameters['u'] ?? '';
    final String secretKey = uri.queryParameters['k'] ?? '';

    setState(() {
      _lastIncomingUri = uri.toString();
      _status = context.l10n.tr('externalScanReceived');
    });

    if (userId.isNotEmpty && secretKey.isNotEmpty) {
      _userIdController.text = userId;
      _secretKeyController.text = secretKey;
      setState(() {
        _status = context.l10n.tr('externalCredentialsLoaded');
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
    final List<NdefRecord> records = <NdefRecord>[_buildUriRecord(uri)];

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
    final AppLocalizations l10n = context.l10n;
    final bool isAvailable = await NfcManager.instance.isAvailable();
    if (!isAvailable) {
      setState(() {
        _status = l10n.tr('nfcUnavailable');
        _isReading = false;
      });
      return;
    }

    if (_isReading) {
      return;
    }

    setState(() {
      _isReading = true;
      _status = l10n.tr('autoReadingNtag');
      _tagId = '-';
      _records = <String>[];
    });

    await NfcManager.instance.startSession(
      onDiscovered: (NfcTag tag) async {
        final Map<String, dynamic> data = tag.data;
        final dynamic idBytes =
            data['nfca']?['identifier'] ??
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
              : existingSecrets.length == 1 &&
                    existingSecrets.first == targetSecret;

          if (uriMatches && secretMatches) {
            writeMessage = targetSecret.isEmpty
                ? l10n.tr('tagAlreadyTarget')
                : l10n.tr('tagAlreadyTargetSecret');
          } else {
            try {
              final bool writeSuccess = await _writeUriToTag(tag, targetUri);
              writeMessage = writeSuccess
                  ? l10n.tr('uriWritten')
                  : l10n.tr('tagNotWritableShort');
            } catch (e) {
              writeMessage = l10n.tr('writeFailed', <String, Object?>{
                'error': e,
              });
            }
          }
        }

        setState(() {
          _tagId = parsedTagId.isEmpty ? l10n.tr('tagIdMissing') : parsedTagId;
          _records = parsedRecords;
          _status =
              '${l10n.tr(parsedRecords.isEmpty ? 'tagReadNoNdef' : 'tagReadWaiting')} $writeMessage';
        });
      },
      onError: (dynamic error) async {
        setState(() {
          _status = l10n.tr('nfcReadFailed', <String, Object?>{'error': error});
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
    return values
        .map((int b) => b.toRadixString(16).padLeft(2, '0'))
        .join(':')
        .toUpperCase();
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

    final String identifier = utf8.decode(
      record.identifier,
      allowMalformed: true,
    );
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
        title: Text(context.l10n.tr('ntagReader')),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '${context.l10n.tr('status')}: $_status',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Text('Tag ID: $_tagId'),
            const SizedBox(height: 8),
            Text('${context.l10n.tr('externalScanUri')}: $_lastIncomingUri'),
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
              title: Text(context.l10n.tr('autoWriteUri')),
              value: _autoWriteEnabled,
              contentPadding: EdgeInsets.zero,
              onChanged: (bool value) {
                setState(() {
                  _autoWriteEnabled = value;
                });
              },
            ),
            Text(
              '${context.l10n.tr('targetUri')}: ${_buildTargetUri()}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            Text(
              context.l10n.tr('ndefContents'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _records.isEmpty
                  ? Center(child: Text(context.l10n.tr('noNdefRecords')))
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
