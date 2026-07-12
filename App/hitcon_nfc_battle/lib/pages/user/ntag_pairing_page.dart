import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';

import '../../l10n/app_localizations.dart';
import '../../services/auth_service.dart';
import '../../services/nfc_session_controller.dart';
import '../../services/ntag_security_service.dart';
import 'pixel_theme.dart';

const Duration _tagDisposalGracePeriod = Duration(milliseconds: 120);

Future<void> _stopNfcSessionQuietly() async {
  try {
    await NfcManager.instance.stopSession();
  } catch (_) {
    // A stale Android Tag must not escape cleanup and break navigation.
  }
}

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
  bool _isHandlingTag = false;
  bool _isDisposed = false;
  NfcSessionLease? _nfcLease;

  @override
  void initState() {
    super.initState();
    _userId = AuthService().currentUserId ?? '';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startSession();
    });
  }

  Future<void> _startSession() async {
    if (_isReading || _isDisposed) {
      return;
    }

    final AppLocalizations l10n = context.l10n;
    bool isAvailable = false;
    try {
      isAvailable = await NfcManager.instance.isAvailable();
    } catch (error) {
      if (mounted) {
        setState(() {
          _status = l10n.tr('nfcReadFailed', <String, Object?>{'error': error});
        });
      }
      return;
    }
    if (!isAvailable) {
      if (mounted) {
        setState(() {
          _status = l10n.tr('nfcUnavailable');
        });
      }
      return;
    }

    if (_userId.trim().isEmpty) {
      setState(() {
        _status = l10n.tr('loginRequiredUserId');
      });
      return;
    }

    final NfcSessionLease? lease = await NfcSessionController.instance.acquire(
      NfcSessionOwner.badgePairing,
      preemptExisting: true,
      onPreempt: _handleSessionPreempted,
    );
    if (lease == null || _isDisposed) {
      lease?.release();
      if (mounted) {
        setState(() {
          _status = l10n.tr('nfcSessionBusy');
        });
      }
      return;
    }

    _nfcLease = lease;
    await _stopNfcSessionQuietly();
    if (!lease.isActive || _isDisposed) {
      lease.release();
      return;
    }

    if (mounted) {
      setState(() {
        _isReading = true;
        _status = l10n.tr('waitingForTag');
      });
    }

    try {
      await NfcManager.instance.startSession(
        pollingOptions: const <NfcPollingOption>{NfcPollingOption.iso14443},
        onDiscovered: (NfcTag tag) async {
          if (!lease.isActive || _isHandlingTag || _isDisposed) {
            return;
          }
          _isHandlingTag = true;

          String parsedTagId = '';
          bool pairSuccess = false;
          String status = '';
          try {
            parsedTagId = _security.readTagId(tag);
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
                          messageKey: 'ntagLockSecretFailed',
                        )
                      : await _security.protectForRewrite(tag, lockSecret)
                : const NtagSecurityResult(
                    success: false,
                    messageKey: 'ndefWriteUnsupported',
                  );

            if (ndefWritten && lockResult.success && parsedTagId.isNotEmpty) {
              pairSuccess = await AuthService().pairNfcTag(parsedTagId);
            }

            if (!ndefWritten || !lockResult.success) {
              status = l10n.tr(lockResult.messageKey, lockResult.values);
            } else if (!pairSuccess) {
              status =
                  '${l10n.tr(lockResult.messageKey, lockResult.values)}\n'
                  '${l10n.tr('apiPairFailed')}';
            } else {
              status = l10n.tr('ntagWriteLocked');
            }
          } catch (error) {
            status = l10n.tr('nfcReadFailed', <String, Object?>{
              'error': error,
            });
          }

          if (mounted) {
            setState(() {
              _tagId = parsedTagId.isEmpty
                  ? l10n.tr('tagIdMissing')
                  : parsedTagId;
              _status = status;
            });
          }

          unawaited(
            _finishTagHandling(
              lease,
              pairSuccess: pairSuccess,
              parsedTagId: parsedTagId,
            ),
          );
        },
        onError: (dynamic error) async {
          if (!lease.isActive || _isDisposed) {
            return;
          }
          await _stopOwnedSession(lease);
          if (!mounted) {
            return;
          }
          setState(() {
            _status = l10n.tr('nfcReadFailed', <String, Object?>{
              'error': error,
            });
            _isReading = false;
            _isHandlingTag = false;
          });
        },
      );
    } catch (error) {
      await _stopOwnedSession(lease);
      if (mounted) {
        setState(() {
          _status = l10n.tr('nfcReadFailed', <String, Object?>{'error': error});
          _isReading = false;
          _isHandlingTag = false;
        });
      }
    }
  }

  Future<void> _finishTagHandling(
    NfcSessionLease lease, {
    required bool pairSuccess,
    required String parsedTagId,
  }) async {
    await Future<void>.delayed(_tagDisposalGracePeriod);
    await _stopOwnedSession(lease);
    _isHandlingTag = false;
    _isReading = false;

    if (!mounted || _isDisposed) {
      return;
    }
    if (pairSuccess) {
      Navigator.of(context).pop(parsedTagId);
    } else {
      setState(() {});
    }
  }

  Future<void> _stopOwnedSession(NfcSessionLease lease) async {
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
    }
  }

  Future<void> _handleSessionPreempted() async {
    _nfcLease = null;
    _isReading = false;
    _isHandlingTag = false;
    await _stopNfcSessionQuietly();
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
    _isDisposed = true;
    final NfcSessionLease? lease = _nfcLease;
    _nfcLease = null;
    if (lease != null && lease.isActive && !_isHandlingTag) {
      unawaited(_stopNfcSessionQuietly().whenComplete(lease.release));
    }
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
  bool _isHandlingTag = false;
  bool _isDisposed = false;
  NfcSessionLease? _nfcLease;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startSession();
    });
  }

  Future<void> _startSession() async {
    if (_isReading || _isDisposed) {
      return;
    }

    final AppLocalizations l10n = context.l10n;
    bool isAvailable = false;
    try {
      isAvailable = await NfcManager.instance.isAvailable();
    } catch (error) {
      if (mounted) {
        setState(() {
          _status = l10n.tr('nfcReadFailed', <String, Object?>{'error': error});
        });
      }
      return;
    }
    if (!isAvailable) {
      if (mounted) {
        setState(() {
          _status = l10n.tr('nfcUnavailable');
        });
      }
      return;
    }

    final NfcSessionLease? lease = await NfcSessionController.instance.acquire(
      NfcSessionOwner.badgePairing,
      preemptExisting: true,
      onPreempt: _handleSessionPreempted,
    );
    if (lease == null || _isDisposed) {
      lease?.release();
      if (mounted) {
        setState(() {
          _status = l10n.tr('nfcSessionBusy');
        });
      }
      return;
    }

    _nfcLease = lease;
    await _stopNfcSessionQuietly();
    if (!lease.isActive || _isDisposed) {
      lease.release();
      return;
    }

    if (mounted) {
      setState(() {
        _isReading = true;
        _status = l10n.tr('holdOwnNtagNearPhone');
        _tagId = '-';
      });
    }

    try {
      await NfcManager.instance.startSession(
        pollingOptions: const <NfcPollingOption>{NfcPollingOption.iso14443},
        onDiscovered: (NfcTag tag) async {
          if (!lease.isActive || _isHandlingTag || _isDisposed) {
            return;
          }
          _isHandlingTag = true;

          String parsedTagId = '';
          NtagSecurityResult result;
          try {
            parsedTagId = _security.readTagId(tag);
            final NtagLockSecret? lockSecret = await AuthService()
                .requestNtagLockSecret(uid: parsedTagId, purpose: 'unlock');
            result = lockSecret == null
                ? const NtagSecurityResult(
                    success: false,
                    messageKey: 'unlockSecretFailed',
                  )
                : await _security.unlockForRewrite(tag, lockSecret);
          } catch (error) {
            result = NtagSecurityResult(
              success: false,
              messageKey: 'nfcReadFailed',
              values: <String, Object?>{'error': error},
            );
          }

          if (mounted) {
            setState(() {
              _tagId = parsedTagId.isEmpty
                  ? l10n.tr('tagIdMissing')
                  : parsedTagId;
              _status = l10n.tr(result.messageKey, result.values);
            });
          }

          unawaited(
            _finishUnlockHandling(lease, unlockSucceeded: result.success),
          );
        },
        onError: (dynamic error) async {
          if (!lease.isActive || _isDisposed) {
            return;
          }
          await _stopOwnedSession(lease);
          if (!mounted) {
            return;
          }
          setState(() {
            _status = l10n.tr('nfcReadFailed', <String, Object?>{
              'error': error,
            });
            _isReading = false;
            _isHandlingTag = false;
          });
        },
      );
    } catch (error) {
      await _stopOwnedSession(lease);
      if (mounted) {
        setState(() {
          _status = l10n.tr('nfcReadFailed', <String, Object?>{'error': error});
          _isReading = false;
          _isHandlingTag = false;
        });
      }
    }
  }

  Future<void> _stopSession() async {
    final NfcSessionLease? lease = _nfcLease;
    if (lease != null) {
      await _stopOwnedSession(lease);
    } else {
      await _stopNfcSessionQuietly();
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _isReading = false;
      _isHandlingTag = false;
      _status = context.l10n.tr('scanStopped');
    });
  }

  Future<void> _finishUnlockHandling(
    NfcSessionLease lease, {
    required bool unlockSucceeded,
  }) async {
    await Future<void>.delayed(_tagDisposalGracePeriod);
    await _stopOwnedSession(lease);
    _isHandlingTag = false;
    _isReading = false;

    if (!mounted || _isDisposed) {
      return;
    }
    setState(() {});
    if (unlockSucceeded) {
      await Future<void>.delayed(const Duration(milliseconds: 380));
      if (mounted && !_isDisposed) {
        Navigator.of(context).pop(true);
      }
    }
  }

  Future<void> _stopOwnedSession(NfcSessionLease lease) async {
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
    }
  }

  Future<void> _handleSessionPreempted() async {
    _nfcLease = null;
    _isReading = false;
    _isHandlingTag = false;
    await _stopNfcSessionQuietly();
  }

  @override
  void dispose() {
    _isDisposed = true;
    final NfcSessionLease? lease = _nfcLease;
    _nfcLease = null;
    if (lease != null && lease.isActive && !_isHandlingTag) {
      unawaited(_stopNfcSessionQuietly().whenComplete(lease.release));
    }
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
