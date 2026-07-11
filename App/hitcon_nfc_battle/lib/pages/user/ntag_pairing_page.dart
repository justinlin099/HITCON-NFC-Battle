import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';

import '../../l10n/app_localizations.dart';
import '../../services/auth_service.dart';
import '../../services/ntag_security_service.dart';
import 'pixel_theme.dart';

Future<String?> openNtagPairingScanPage(BuildContext context) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute<String>(builder: (_) => const NtagPairingPage()),
  );
}

Future<bool?> openNtagUnlockPage(BuildContext context) {
  return Navigator.of(
    context,
  ).push<bool>(MaterialPageRoute<bool>(builder: (_) => const NtagUnlockPage()));
}

class NtagPairingPage extends StatefulWidget {
  const NtagPairingPage({super.key});

  @override
  State<NtagPairingPage> createState() => _NtagPairingPageState();
}

class _NtagPairingPageState extends State<NtagPairingPage> {
  static const String _targetHost = 'game.hitcon2026.online';
  static const String _targetPath = '/b';
  static const NtagSecurityService _security = NtagSecurityService();

  String _status = '';
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

    final AppLocalizations l10n = context.l10n;
    final bool isAvailable = await NfcManager.instance.isAvailable();
    if (!isAvailable) {
      setState(() {
        _status = l10n.tr('nfcUnavailable');
      });
      return;
    }

    if (_userId.trim().isEmpty) {
      setState(() {
        _status = l10n.tr('loginRequiredUserId');
      });
      return;
    }

    setState(() {
      _isReading = true;
      _status = l10n.tr('waitingForTag');
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
                  ? NtagSecurityResult(
                      success: false,
                      messageKey: 'ntagLockSecretFailed',
                    )
                  : await _security.protectForRewrite(tag, lockSecret)
            : NtagSecurityResult(
                success: false,
                messageKey: 'ndefWriteUnsupported',
              );

        bool pairSuccess = false;
        if (ndefWritten && lockResult.success && parsedTagId.isNotEmpty) {
          pairSuccess = await AuthService().pairNfcTag(parsedTagId);
        }

        if (!mounted) {
          return;
        }

        setState(() {
          _tagId = parsedTagId.isEmpty ? l10n.tr('tagIdMissing') : parsedTagId;
          if (!ndefWritten || !lockResult.success) {
            _status = l10n.tr(lockResult.messageKey, lockResult.values);
          } else if (!pairSuccess) {
            _status =
                '${l10n.tr(lockResult.messageKey, lockResult.values)}\n'
                '${l10n.tr('apiPairFailed')}';
          } else {
            _status = l10n.tr('ntagWriteLocked');
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
          _status = l10n.tr('nfcReadFailed', <String, Object?>{'error': error});
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

    final String targetUri = Uri.https(
      _targetHost,
      _targetPath,
      <String, String>{'u': userId},
    ).toString();
    final List<NdefRecord> records = <NdefRecord>[_buildUriRecord(targetUri)];

    await ndef.write(NdefMessage(records));
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
          title: Text(context.l10n.tr('ntagPairingPageTitle')),
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
                  context.l10n.tr('holdBadgeNearPhone'),
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

class NtagUnlockPage extends StatefulWidget {
  const NtagUnlockPage({super.key});

  @override
  State<NtagUnlockPage> createState() => _NtagUnlockPageState();
}

class _NtagUnlockPageState extends State<NtagUnlockPage> {
  static const NtagSecurityService _security = NtagSecurityService();

  String _status = '';
  String _tagId = '-';
  bool _isReading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startSession();
    });
  }

  Future<void> _startSession() async {
    if (_isReading) {
      return;
    }

    final AppLocalizations l10n = context.l10n;
    final bool isAvailable = await NfcManager.instance.isAvailable();
    if (!isAvailable) {
      setState(() {
        _status = l10n.tr('nfcUnavailable');
      });
      return;
    }

    setState(() {
      _isReading = true;
      _status = l10n.tr('holdOwnNtagNearPhone');
      _tagId = '-';
    });

    await NfcManager.instance.stopSession();
    await NfcManager.instance.startSession(
      onDiscovered: (NfcTag tag) async {
        final String parsedTagId = _security.readTagId(tag);
        final NtagLockSecret? lockSecret = await AuthService()
            .requestNtagLockSecret(uid: parsedTagId, purpose: 'unlock');
        final NtagSecurityResult result = lockSecret == null
            ? NtagSecurityResult(
                success: false,
                messageKey: 'unlockSecretFailed',
              )
            : await _security.unlockForRewrite(tag, lockSecret);

        await NfcManager.instance.stopSession();
        if (!mounted) {
          return;
        }

        setState(() {
          _isReading = false;
          _tagId = parsedTagId.isEmpty ? l10n.tr('tagIdMissing') : parsedTagId;
          _status = l10n.tr(result.messageKey, result.values);
        });

        if (result.success) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
          if (mounted) {
            Navigator.of(context).pop(true);
          }
        }
      },
      onError: (dynamic error) async {
        await NfcManager.instance.stopSession();
        if (!mounted) {
          return;
        }
        setState(() {
          _status = l10n.tr('nfcReadFailed', <String, Object?>{'error': error});
          _isReading = false;
        });
      },
    );
  }

  Future<void> _stopSession() async {
    await NfcManager.instance.stopSession();
    if (!mounted) {
      return;
    }
    setState(() {
      _isReading = false;
      _status = context.l10n.tr('scanStopped');
    });
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
          title: Text(context.l10n.tr('unlockNtag')),
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
                Icon(
                  Icons.lock_open_rounded,
                  size: 48,
                  color: PixelTheme.accent,
                ),
                const SizedBox(height: 12),
                Text(
                  context.l10n.tr('unlockOwnNtag'),
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
                const SizedBox(height: 14),
                GestureDetector(
                  onTap: _isReading ? _stopSession : _startSession,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: PixelTheme.bgDark,
                      border: Border.all(color: PixelTheme.accent, width: 2),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black,
                          blurRadius: 0,
                          offset: Offset(3, 3),
                        ),
                      ],
                    ),
                    child: Text(
                      context.l10n.tr(_isReading ? 'stopScan' : 'scanAgain'),
                      style: TextStyle(
                        color: PixelTheme.accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
