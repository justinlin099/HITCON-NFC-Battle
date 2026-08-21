import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';

import '../../l10n/app_localizations.dart';
import '../../services/auth_service.dart';
import '../../services/nfc_deep_link_service.dart';
import '../../services/nfc_session_controller.dart';
import '../../services/nfc_tag_payload.dart';
import '../../services/ntag_security_service.dart';
import '../user/pixel_theme.dart';
import 'admin_nfc_session.dart';
import 'admin_pixel_widgets.dart';

class AdminUnpairUserTagPage extends StatefulWidget {
  const AdminUnpairUserTagPage({super.key});

  @override
  State<AdminUnpairUserTagPage> createState() => _AdminUnpairUserTagPageState();
}

class _AdminUnpairUserTagPageState extends State<AdminUnpairUserTagPage> {
  static const NtagSecurityService _security = NtagSecurityService();
  static const Duration _tagGracePeriod = Duration(milliseconds: 400);

  final TextEditingController _userIdController = TextEditingController();
  final AdminNfcSession _nfcSession = AdminNfcSession(
    owner: NfcSessionOwner.badgePairing,
  );

  String _status = '';
  String _lastUid = '-';
  bool _isScanning = false;
  bool _isReadingUserId = false;
  bool _isHandlingTag = false;
  bool _isSuppressingDeepLinks = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_status.isEmpty) {
      _status = context.l10n.tr('staffUnpairUserPrompt');
    }
  }

  @override
  void dispose() {
    _userIdController.dispose();
    unawaited(_endDeepLinkSuppression());
    if (!_isHandlingTag) {
      _nfcSession.dispose();
    }
    super.dispose();
  }

  Future<void> _startUnpairing() async {
    if (_isScanning) {
      return;
    }
    final AppLocalizations l10n = context.l10n;
    final String userId = _userIdController.text.trim();
    if (userId.isEmpty) {
      setState(() {
        _status = l10n.tr('staffUnpairUserIdRequired');
      });
      return;
    }

    final bool confirmed = await _confirmUnpair(userId);
    if (!confirmed || !mounted) {
      return;
    }

    bool available;
    try {
      available = await NfcManager.instance.isAvailable();
    } catch (error) {
      await _finishSession(null, error: error);
      return;
    }
    if (!available) {
      setState(() {
        _status = l10n.tr('nfcUnavailable');
      });
      return;
    }

    await _beginDeepLinkSuppression();
    if (!mounted) {
      return;
    }
    setState(() {
      _isScanning = true;
      _isReadingUserId = false;
      _lastUid = '-';
      _status = l10n.tr('staffUnpairHoldTag');
    });
    NfcSessionLease? sessionLease;
    try {
      sessionLease = await _nfcSession.acquire(onPreempt: _handlePreempted);
      if (sessionLease == null) {
        await _endDeepLinkSuppression();
        if (mounted) {
          setState(() {
            _isScanning = false;
            _status = l10n.tr('nfcSessionBusy');
          });
        }
        return;
      }
      if (!_isScanning || !mounted) {
        await _nfcSession.stop(sessionLease);
        return;
      }

      final NfcSessionLease activeLease = sessionLease;
      await NfcManager.instance.startSession(
        pollingOptions: const <NfcPollingOption>{NfcPollingOption.iso14443},
        onDiscovered: (NfcTag tag) async {
          if (!activeLease.isActive || _isHandlingTag || !mounted) {
            return;
          }
          _isHandlingTag = true;
          final String uid = _security.readTagId(tag);
          String status;
          try {
            if (uid.isEmpty) {
              throw StateError(l10n.tr('tagIdMissing'));
            }
            final AuthService auth = AuthService();
            final bool unpaired = await auth.unpairStaffUserTag(
              userId: userId,
              uid: uid,
            );
            if (!activeLease.isActive) {
              return;
            }
            if (!unpaired) {
              throw StateError(
                l10n.tr('staffUnpairApiFailed', <String, Object?>{
                  'error': auth.lastAuthError ?? l10n.tr('unknown'),
                }),
              );
            }
            status = l10n.tr('staffUnpairComplete');
          } catch (error) {
            status = error is StateError
                ? error.message.toString()
                : l10n.tr('nfcError', <String, Object?>{'error': error});
          }

          if (mounted && activeLease.isActive) {
            setState(() {
              _lastUid = uid.isEmpty ? '-' : uid;
              _status = status;
            });
          }
          await Future<void>.delayed(_tagGracePeriod);
          await _finishSession(activeLease);
        },
        onError: (dynamic error) async {
          await _finishSession(activeLease, error: error);
        },
      );
    } catch (error) {
      await _finishSession(sessionLease, error: error);
    }
  }

  Future<void> _startUserIdScan() async {
    if (_isScanning) {
      return;
    }
    final AppLocalizations l10n = context.l10n;
    bool available;
    try {
      available = await NfcManager.instance.isAvailable();
    } catch (error) {
      await _finishSession(null, error: error);
      return;
    }
    if (!available) {
      setState(() {
        _status = l10n.tr('nfcUnavailable');
      });
      return;
    }

    await _beginDeepLinkSuppression();
    if (!mounted) {
      return;
    }
    setState(() {
      _isScanning = true;
      _isReadingUserId = true;
      _lastUid = '-';
      _status = l10n.tr('staffPairReadUserIdHoldTag');
    });

    NfcSessionLease? sessionLease;
    try {
      sessionLease = await _nfcSession.acquire(onPreempt: _handlePreempted);
      if (sessionLease == null) {
        await _endDeepLinkSuppression();
        if (mounted) {
          setState(() {
            _isScanning = false;
            _isReadingUserId = false;
            _status = l10n.tr('nfcSessionBusy');
          });
        }
        return;
      }
      if (!_isScanning || !mounted) {
        await _nfcSession.stop(sessionLease);
        return;
      }

      final NfcSessionLease activeLease = sessionLease;
      await NfcManager.instance.startSession(
        pollingOptions: const <NfcPollingOption>{NfcPollingOption.iso14443},
        onDiscovered: (NfcTag tag) async {
          if (!activeLease.isActive || _isHandlingTag || !mounted) {
            return;
          }
          _isHandlingTag = true;
          final String uid = _security.readTagId(tag);
          String status;
          try {
            final String? userId = NfcTagPayload.readUserId(
              Ndef.from(tag)?.cachedMessage,
            );
            if (userId == null) {
              throw StateError(l10n.tr('staffPairUserIdReadMissing'));
            }
            _userIdController.text = userId;
            status = l10n.tr('staffUnpairUserIdReadComplete', <String, Object?>{
              'userId': userId,
            });
          } catch (error) {
            status = l10n.tr('staffPairUserIdReadFailed', <String, Object?>{
              'error': error,
            });
          }

          if (mounted && activeLease.isActive) {
            setState(() {
              _lastUid = uid.isEmpty ? '-' : uid;
              _status = status;
            });
          }
          await Future<void>.delayed(_tagGracePeriod);
          await _finishSession(activeLease);
        },
        onError: (dynamic error) async {
          await _finishSession(activeLease, error: error);
        },
      );
    } catch (error) {
      await _finishSession(sessionLease, error: error);
    }
  }

  Future<bool> _confirmUnpair(String userId) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return AlertDialog(
              backgroundColor: PixelTheme.bgMid,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
              ),
              title: Text(
                context.l10n.tr('staffUnpairConfirmTitle'),
                style: TextStyle(
                  color: PixelTheme.warning,
                  fontFamily: 'Unifont',
                  fontWeight: FontWeight.w900,
                ),
              ),
              content: Text(
                context.l10n.tr('staffUnpairConfirmBody', <String, Object?>{
                  'userId': userId,
                }),
                style: TextStyle(
                  color: PixelTheme.textWhite,
                  fontFamily: 'Unifont',
                  height: 1.5,
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(context.l10n.tr('cancel')),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(
                    context.l10n.tr('confirm'),
                    style: TextStyle(color: PixelTheme.warning),
                  ),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  Future<void> _finishSession(
    NfcSessionLease? sessionLease, {
    Object? error,
  }) async {
    if (sessionLease != null && !sessionLease.isActive) {
      return;
    }
    if (sessionLease != null) {
      await _nfcSession.stop(sessionLease);
    }
    _isHandlingTag = false;
    await _endDeepLinkSuppression();
    if (!mounted) {
      return;
    }
    setState(() {
      _isScanning = false;
      _isReadingUserId = false;
      if (error != null) {
        _status = context.l10n.tr('nfcError', <String, Object?>{
          'error': error,
        });
      }
    });
  }

  Future<void> _stopScanning() async {
    if (_isHandlingTag) {
      return;
    }
    await _nfcSession.stop();
    await _endDeepLinkSuppression();
    if (!mounted) {
      return;
    }
    setState(() {
      _isScanning = false;
      _isReadingUserId = false;
      _status = context.l10n.tr('scanStopped');
    });
  }

  Future<void> _handlePreempted() async {
    _isHandlingTag = false;
    await _endDeepLinkSuppression();
    if (!mounted) {
      return;
    }
    setState(() {
      _isScanning = false;
      _isReadingUserId = false;
      _status = context.l10n.tr('nfcSessionBusy');
    });
  }

  Future<void> _beginDeepLinkSuppression() async {
    if (_isSuppressingDeepLinks) {
      return;
    }
    _isSuppressingDeepLinks = true;
    await NfcDeepLinkService.instance.beginTagMaintenance();
  }

  Future<void> _endDeepLinkSuppression() async {
    if (!_isSuppressingDeepLinks) {
      return;
    }
    _isSuppressingDeepLinks = false;
    await NfcDeepLinkService.instance.endTagMaintenance();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: <Widget>[
        AdminPixelPanel(
          title: context.l10n.tr('staffUnpairUserTag'),
          children: <Widget>[
            Text(
              context.l10n.tr('staffUnpairUserDescription'),
              style: TextStyle(
                color: PixelTheme.textGray,
                fontFamily: 'Unifont',
                fontSize: 11,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 12),
            AdminPixelTextField(
              controller: _userIdController,
              label: 'User ID',
            ),
            const SizedBox(height: 8),
            AdminPixelButton(
              key: const ValueKey<String>('staff-unpair-read-user-id-button'),
              label: context.l10n.tr(
                _isScanning && _isReadingUserId
                    ? 'stopScan'
                    : 'staffPairReadUserId',
              ),
              icon: _isScanning && _isReadingUserId
                  ? Icons.stop_rounded
                  : Icons.contactless_rounded,
              color: _isScanning && _isReadingUserId
                  ? PixelTheme.warning
                  : PixelTheme.textWhite,
              onPressed: !_isScanning
                  ? _startUserIdScan
                  : _isReadingUserId
                  ? _stopScanning
                  : null,
            ),
            const SizedBox(height: 12),
            AdminStatusLine(label: context.l10n.tr('status'), value: _status),
            AdminStatusLine(label: 'UID', value: _lastUid),
            const SizedBox(height: 4),
            AdminPixelButton(
              key: const ValueKey<String>('staff-unpair-start-button'),
              label: context.l10n.tr(
                _isScanning && !_isReadingUserId
                    ? 'stopScan'
                    : 'staffUnpairStart',
              ),
              icon: _isScanning && !_isReadingUserId
                  ? Icons.stop_rounded
                  : Icons.link_off_rounded,
              color: PixelTheme.warning,
              onPressed: !_isScanning
                  ? _startUnpairing
                  : _isReadingUserId
                  ? null
                  : _stopScanning,
            ),
          ],
        ),
      ],
    );
  }
}
