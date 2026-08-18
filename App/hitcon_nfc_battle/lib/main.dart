import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show
        DeviceOrientation,
        MethodChannel,
        MissingPluginException,
        PlatformException,
        SystemChrome,
        SystemUiOverlayStyle;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'l10n/app_localizations.dart';
import 'pages/admin/admin_home_page.dart';
import 'pages/user/card_collection_page.dart';
import 'pages/user/panasonic_support_mark.dart';
import 'pages/user/setup_page.dart';
import 'pages/debug/test_login_page.dart';
import 'services/auth_service.dart';
import 'services/nfc_deep_link_service.dart';
import 'services/nfc_error_messages.dart';
import 'services/nfc_session_controller.dart';
import 'services/nfc_tag_payload.dart';
import 'services/ntag_security_service.dart';
import 'services/remote_app_config_service.dart';
import 'services/setup_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);
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
    await RemoteAppConfigService.instance.refresh(force: true);
    if (!mounted) {
      return;
    }

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

    final String routeName = auth.usesUserFlow
        ? (setupComplete ? '/collection' : '/setup')
        : '/admin';
    Navigator.of(context).pushReplacementNamed(routeName);
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF0F0018),
        body: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Center(
              child: Semantics(
                label: 'HITCON NFC Battle',
                image: true,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(36),
                  child: Image.asset(
                    'assets/app_icon/app_icon_master.png',
                    key: const ValueKey<String>('startup-app-icon'),
                    width: 160,
                    height: 160,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ),
            ),
            const SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: EdgeInsets.only(bottom: 48),
                  child: PanasonicSupportMark(
                    key: ValueKey<String>('startup-panasonic-mark'),
                    width: 160,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late final AutoNtagScanner _autoScanner;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(NfcDeepLinkService.instance.initialize());
    _autoScanner = AutoNtagScanner(deepLinks: NfcDeepLinkService.instance);
    NfcDeepLinkService.instance.registerInAppScanStarter(_autoScanner.start);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoScanner.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(RemoteAppConfigService.instance.refresh());
    }
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
      localeListResolutionCallback: resolveAppLocale,
      home: const _SessionGate(),
      routes: {
        '/home': (context) => const NTagReaderPage(),
        '/admin': (context) => const AdminHomePage(),
        '/collection': (context) => const CardCollectionPage(),
        '/setup': (context) => const SetupPage(),
      },
    );
  }
}

Locale resolveAppLocale(
  List<Locale>? preferredLocales,
  Iterable<Locale> supportedLocales,
) {
  final Set<String> supportedLanguageCodes = supportedLocales
      .map((Locale locale) => locale.languageCode)
      .toSet();
  for (final Locale locale in preferredLocales ?? const <Locale>[]) {
    final String country = locale.countryCode?.toUpperCase() ?? '';
    final String script = locale.scriptCode?.toLowerCase() ?? '';
    final bool traditionalChinese =
        locale.languageCode == 'zh' &&
        (script == 'hant' ||
            country == 'TW' ||
            country == 'HK' ||
            country == 'MO');
    if (traditionalChinese && supportedLanguageCodes.contains('zh')) {
      return const Locale.fromSubtags(languageCode: 'zh', countryCode: 'TW');
    }
    if (<String>{'en', 'ja', 'ko'}.contains(locale.languageCode) &&
        supportedLanguageCodes.contains(locale.languageCode)) {
      return Locale(locale.languageCode);
    }
  }
  return const Locale('en');
}

class AutoNtagScanner {
  AutoNtagScanner({
    required this.deepLinks,
    MethodChannel? iosCollectionScanner,
  }) : _iosCollectionScanner =
           iosCollectionScanner ?? _defaultIosCollectionScanner;

  final NfcDeepLinkService deepLinks;
  static const NtagSecurityService _ntagSecurity = NtagSecurityService();
  static const MethodChannel _defaultIosCollectionScanner = MethodChannel(
    'hitcon_nfc_battle/ios_collection_nfc_scanner',
  );
  final MethodChannel _iosCollectionScanner;
  bool _isStarting = false;
  bool _isIosScanRunning = false;
  bool _iosScanQueued = false;
  bool _isHandling = false;
  bool _isDisposed = false;
  NfcSessionLease? _nfcLease;
  Completer<void>? _sessionInvalidated;
  DateTime _nextSessionStartAt = DateTime.fromMillisecondsSinceEpoch(0);
  String _lastTagId = '';
  DateTime _lastReadTime = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> start() async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await _startIosScan();
      return;
    }
    await _startPluginScan();
  }

  Future<void> _startIosScan() async {
    if (_isDisposed) {
      return;
    }
    if (_isIosScanRunning) {
      // A tap can arrive while iOS is finishing the dismissal animation. Do
      // not lose it; reopen as soon as didInvalidateWithError has completed.
      _iosScanQueued = true;
      return;
    }

    _isIosScanRunning = true;
    try {
      do {
        _iosScanQueued = false;
        await _runIosScan();
      } while (_iosScanQueued && !_isDisposed);
    } finally {
      _isIosScanRunning = false;
    }
  }

  Future<void> _runIosScan() async {
    NfcSessionLease? lease;
    try {
      lease = await NfcSessionController.instance.acquire(
        NfcSessionOwner.collectionScanner,
        onPreempt: _stopForPreempt,
      );
      if (lease == null || _isDisposed) {
        lease?.release();
        return;
      }

      final NfcSessionLease acquiredLease = lease;
      _nfcLease = acquiredLease;
      for (int attempt = 0; attempt < 3; attempt++) {
        if (!acquiredLease.isActive || _isDisposed) {
          return;
        }
        debugPrint(
          '[NFCCollection] invoking native scan attempt ${attempt + 1}',
        );
        final Map<String, dynamic>? response = await _iosCollectionScanner
            .invokeMapMethod<String, dynamic>('scan');
        final String status = response?['status'] as String? ?? 'error';
        final String errorType = response?['type'] as String? ?? '';
        debugPrint(
          '[NFCCollection] native scan completed status=$status type=$errorType',
        );
        if (status == 'error' && errorType == 'systemIsBusy' && attempt < 2) {
          // The native scanner only completes after Core NFC confirms the old
          // reader is invalidated. Older iPhones can need more than one retry
          // after the cancellation sheet has disappeared.
          await Future<void>.delayed(
            Duration(milliseconds: 250 * (attempt + 1)),
          );
          continue;
        }
        if (status == 'scanned' && acquiredLease.isActive && !_isDisposed) {
          await _handleScan(
            response?['uid'] as String? ?? '',
            response?['userId'] as String? ?? '',
          );
        }
        return;
      }
    } on MissingPluginException catch (error) {
      // Only possible on a non-iOS test host or an out-of-date installation.
      debugPrint('[NFCCollection] native scanner missing: $error');
    } on PlatformException catch (error) {
      // Core NFC errors are normally returned as structured scan responses.
      debugPrint('[NFCCollection] native scanner platform error: $error');
    } finally {
      if (lease != null) {
        if (identical(_nfcLease, lease)) {
          _nfcLease = null;
        }
        lease.release();
      }
    }
  }

  Future<void> _startPluginScan() async {
    if (_isStarting || _isDisposed) {
      return;
    }

    _isStarting = true;
    NfcSessionLease? lease;
    try {
      final NfcSessionLease? staleLease = _nfcLease;
      final Completer<void>? staleInvalidation = _sessionInvalidated;
      if (staleLease != null && staleLease.isActive) {
        // When the user closes the Core NFC sheet, iOS invalidates the reader
        // before the Dart error callback arrives. Wait for that callback first
        // so an old invalidation cannot be delivered to the next session.
        if (staleInvalidation != null) {
          try {
            await staleInvalidation.future.timeout(
              const Duration(milliseconds: 1200),
            );
          } on TimeoutException {
            // Fall back to explicitly stopping a genuinely stuck session.
          }
        }
      }
      if (staleLease != null && staleLease.isActive) {
        await _stopOwnedSession(staleLease);
      }
      await _waitForCoreNfcCooldown();
      if (_isDisposed) {
        return;
      }

      final bool isAvailable = await NfcManager.instance.isAvailable();
      if (!isAvailable || _isDisposed) {
        return;
      }

      lease = await NfcSessionController.instance.acquire(
        NfcSessionOwner.collectionScanner,
        onPreempt: _stopForPreempt,
      );
      if (lease == null || _isDisposed) {
        lease?.release();
        return;
      }

      final NfcSessionLease acquiredLease = lease;
      if (!acquiredLease.isActive) {
        return;
      }
      final Completer<void> sessionInvalidated = Completer<void>();
      _nfcLease = acquiredLease;
      _sessionInvalidated = sessionInvalidated;
      await NfcManager.instance.startSession(
        pollingOptions: const <NfcPollingOption>{NfcPollingOption.iso14443},
        alertMessage: '請將卡片靠近 iPhone 頂部',
        onDiscovered: (NfcTag tag) async {
          if (!acquiredLease.isActive || _isHandling || _isDisposed) {
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

          try {
            await _stopOwnedSession(acquiredLease);
            _completeInvalidation(acquiredLease, sessionInvalidated);
            final String targetUserId = _readTargetUserId(tag);
            await _handleScan(uid, targetUserId);
          } finally {
            _isHandling = false;
          }
        },
        onError: (_) async {
          if (!acquiredLease.isActive || _isDisposed) {
            _completeInvalidation(acquiredLease, sessionInvalidated);
            return;
          }
          // didInvalidateWithError means Core NFC has already ended this
          // session. Calling stopSession() again here can produce a delayed
          // second invalidation that shuts down the following scan.
          _releaseInvalidatedSession(acquiredLease);
          _completeInvalidation(acquiredLease, sessionInvalidated);
          _isHandling = false;
        },
      );
    } catch (_) {
      if (lease != null) {
        await _stopOwnedSession(lease);
      }
    } finally {
      _isStarting = false;
    }
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

  Future<void> _stopOwnedSession(NfcSessionLease lease) async {
    final Completer<void>? invalidation = identical(_nfcLease, lease)
        ? _sessionInvalidated
        : null;
    if (!lease.isActive) {
      if (identical(_nfcLease, lease)) {
        _nfcLease = null;
      }
      if (invalidation != null) {
        _completeInvalidation(lease, invalidation);
      }
      return;
    }

    try {
      await NfcManager.instance.stopSession();
      _startCoreNfcCooldown();
    } catch (_) {
      // The session may already have been stopped by iOS.
    } finally {
      if (identical(_nfcLease, lease)) {
        _nfcLease = null;
      }
      lease.release();
      if (invalidation != null) {
        _completeInvalidation(lease, invalidation);
      }
    }
  }

  void _releaseInvalidatedSession(NfcSessionLease lease) {
    if (identical(_nfcLease, lease)) {
      _nfcLease = null;
    }
    lease.release();
  }

  void _completeInvalidation(
    NfcSessionLease lease,
    Completer<void> invalidation,
  ) {
    if (!invalidation.isCompleted) {
      invalidation.complete();
    }
    if (identical(_sessionInvalidated, invalidation) &&
        !identical(_nfcLease, lease)) {
      _sessionInvalidated = null;
    }
  }

  void _startCoreNfcCooldown() {
    final DateTime nextStart = DateTime.now().add(
      const Duration(milliseconds: 1200),
    );
    if (nextStart.isAfter(_nextSessionStartAt)) {
      _nextSessionStartAt = nextStart;
    }
  }

  Future<void> _waitForCoreNfcCooldown() async {
    final Duration remaining = _nextSessionStartAt.difference(DateTime.now());
    if (remaining > Duration.zero) {
      // stopSession() returns before Core NFC finishes invalidating. Keep the
      // next begin() outside that window on older devices such as iPhone 8.
      await Future<void>.delayed(remaining);
    }
  }

  Future<void> _stopForPreempt() async {
    _nfcLease = null;
    final Completer<void>? invalidation = _sessionInvalidated;
    _sessionInvalidated = null;
    _isHandling = false;
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await _iosCollectionScanner.invokeMethod<void>('stop');
      } else {
        await NfcManager.instance.stopSession();
        _startCoreNfcCooldown();
      }
    } catch (_) {
      // The new owner can continue even if the old iOS sheet already closed.
    } finally {
      if (invalidation != null && !invalidation.isCompleted) {
        invalidation.complete();
      }
    }
  }

  void dispose() {
    _isDisposed = true;
    final NfcSessionLease? lease = _nfcLease;
    _nfcLease = null;
    final Completer<void>? invalidation = _sessionInvalidated;
    _sessionInvalidated = null;
    if (invalidation != null && !invalidation.isCompleted) {
      invalidation.complete();
    }
    if (lease != null && lease.isActive) {
      final Future<void> stopFuture =
          defaultTargetPlatform == TargetPlatform.iOS
          ? _iosCollectionScanner.invokeMethod<void>('stop')
          : NfcManager.instance.stopSession();
      unawaited(stopFuture.catchError((_) {}).whenComplete(lease.release));
    }
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
  bool _isStartingRead = false;
  bool _isDisposed = false;
  bool _autoWriteEnabled = true;
  NfcSessionLease? _nfcLease;
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
    final List<NdefRecord> additionalRecords = <NdefRecord>[];

    // 如果有 secret，額外寫入文本記錄
    if (secretKey.isNotEmpty) {
      additionalRecords.add(_buildTextRecord('secret_key', secretKey));
    }

    final NdefMessage message = NfcTagPayload.buildUriMessage(
      Uri.parse(uri),
      additionalRecords: additionalRecords,
    );
    final Ndef? ndef = Ndef.from(tag);

    if (ndef == null || !ndef.isWritable) {
      return false;
    }

    await ndef.write(message);
    return true;
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
    if (_isReading || _isStartingRead || _isDisposed) {
      return;
    }

    _isStartingRead = true;
    final AppLocalizations l10n = context.l10n;
    NfcSessionLease? lease;
    try {
      final bool isAvailable = await NfcManager.instance.isAvailable();
      if (!isAvailable || _isDisposed) {
        if (mounted) {
          setState(() {
            _status = l10n.tr('nfcUnavailable');
            _isReading = false;
          });
        }
        return;
      }

      lease = await NfcSessionController.instance.acquire(
        NfcSessionOwner.ntagReader,
        preemptExisting: true,
        onPreempt: _handleReaderPreempted,
      );
      if (lease == null || _isDisposed) {
        lease?.release();
        if (mounted) {
          setState(() {
            _status = l10n.tr('nfcSessionBusy');
            _isReading = false;
          });
        }
        return;
      }

      final NfcSessionLease acquiredLease = lease;
      _nfcLease = acquiredLease;
      await _stopNfcSessionQuietly();
      if (!acquiredLease.isActive || _isDisposed) {
        acquiredLease.release();
        return;
      }

      if (mounted) {
        setState(() {
          _isReading = true;
          _status = l10n.tr('autoReadingNtag');
          _tagId = '-';
          _records = <String>[];
        });
      }

      await NfcManager.instance.startSession(
        pollingOptions: const <NfcPollingOption>{NfcPollingOption.iso14443},
        onDiscovered: (NfcTag tag) async {
          if (!acquiredLease.isActive || _isDisposed) {
            return;
          }

          final String parsedTagId = const NtagSecurityService().readTagId(tag);
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
                writeMessage = nfcWriteErrorMessage(l10n, e);
              }
            }
          }

          if (mounted) {
            setState(() {
              _tagId = parsedTagId.isEmpty
                  ? l10n.tr('tagIdMissing')
                  : parsedTagId;
              _records = parsedRecords;
              _status =
                  '${l10n.tr(parsedRecords.isEmpty ? 'tagReadNoNdef' : 'tagReadWaiting')} $writeMessage';
            });
          }
        },
        onError: (NfcError error) async {
          if (!acquiredLease.isActive || _isDisposed) {
            return;
          }
          await _stopOwnedReaderSession(acquiredLease);
          if (mounted) {
            setState(() {
              _status = nfcSessionErrorMessage(l10n, error);
              _isReading = false;
            });
          }
        },
      );
    } catch (error) {
      if (lease != null) {
        await _stopOwnedReaderSession(lease);
      }
      if (mounted) {
        setState(() {
          _status = nfcSessionErrorMessage(l10n, error);
          _isReading = false;
        });
      }
    } finally {
      _isStartingRead = false;
    }
  }

  Future<void> _stopNfcSessionQuietly() async {
    try {
      await NfcManager.instance.stopSession();
    } catch (_) {
      // The platform session may already be closed.
    }
  }

  Future<void> _stopOwnedReaderSession(NfcSessionLease lease) async {
    if (!lease.isActive) {
      return;
    }
    try {
      await _stopNfcSessionQuietly();
    } finally {
      if (identical(_nfcLease, lease)) {
        _nfcLease = null;
      }
      lease.release();
      _isReading = false;
    }
  }

  Future<void> _handleReaderPreempted() async {
    _nfcLease = null;
    _isReading = false;
    await _stopNfcSessionQuietly();
    if (mounted && !_isDisposed) {
      setState(() {
        _status = context.l10n.tr('nfcSessionBusy');
      });
    }
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
    _isDisposed = true;
    _linkSubscription?.cancel();
    _userIdController.dispose();
    _secretKeyController.dispose();
    final NfcSessionLease? lease = _nfcLease;
    _nfcLease = null;
    if (lease != null && lease.isActive) {
      unawaited(_stopNfcSessionQuietly().whenComplete(lease.release));
    }
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
