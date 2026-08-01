import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';

import '../../l10n/app_localizations.dart';
import '../../services/auth_service.dart';
import '../../services/nfc_deep_link_service.dart';
import '../../services/nfc_error_messages.dart';
import '../../services/nfc_session_controller.dart';
import '../../services/nfc_tag_payload.dart';
import '../../services/ntag_security_service.dart';
import '../user/pixel_theme.dart';
import 'admin_nfc_session.dart';
import 'admin_pixel_widgets.dart';

class AdminPairUserTagPage extends StatefulWidget {
  const AdminPairUserTagPage({super.key});

  @override
  State<AdminPairUserTagPage> createState() => _AdminPairUserTagPageState();
}

class _AdminPairUserTagPageState extends State<AdminPairUserTagPage> {
  static const NtagSecurityService _security = NtagSecurityService();
  static const Duration _tagGracePeriod = Duration(milliseconds: 400);

  final TextEditingController _userIdController = TextEditingController();
  final AdminNfcSession _nfcSession = AdminNfcSession(
    owner: NfcSessionOwner.badgePairing,
  );

  String _status = '';
  String _lastUid = '-';
  bool _isScanning = false;
  bool _isHandlingTag = false;
  bool _isSuppressingDeepLinks = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_status.isEmpty) {
      _status = context.l10n.tr('staffPairUserPrompt');
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

  Future<void> _startPairing() async {
    if (_isScanning) {
      return;
    }
    final AppLocalizations l10n = context.l10n;
    final String userId = _userIdController.text.trim();
    if (userId.isEmpty) {
      setState(() {
        _status = l10n.tr('staffPairUserIdRequired');
      });
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
      _lastUid = '-';
      _status = l10n.tr('staffPairHoldTag');
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
            final Ndef? ndef = Ndef.from(tag);
            if (ndef == null || !ndef.isWritable) {
              throw StateError(l10n.tr('tagNotWritable'));
            }

            final bool pairAccepted = await AuthService().pairStaffUserTag(
              userId: userId,
              uid: uid,
            );
            if (!activeLease.isActive) {
              return;
            }
            final NtagLockSecret? secret = await AuthService()
                .requestNtagLockSecret(
                  uid: uid,
                  purpose: 'unlock',
                  userId: userId,
                );
            if (!activeLease.isActive) {
              return;
            }
            if (!pairAccepted && secret == null) {
              throw StateError(l10n.tr('staffPairApiFailed'));
            }
            if (secret == null) {
              throw StateError(l10n.tr('adminUnlockSecretFailed'));
            }

            final Uri uri = Uri.https(
              'game.hitcon2026.online',
              '/b',
              <String, String>{'u': userId},
            );
            await ndef.write(NfcTagPayload.buildUriMessage(uri));
            if (!activeLease.isActive) {
              return;
            }
            final NtagSecurityResult lockResult = await _security
                .protectForRewrite(tag, secret);
            if (!lockResult.success) {
              throw StateError(
                l10n.tr(lockResult.messageKey, lockResult.values),
              );
            }
            status = l10n.tr('staffPairComplete');
          } catch (error) {
            status = l10n.tr('staffPairFailed', <String, Object?>{
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
        onError: (NfcError error) async {
          await _finishSession(activeLease, error: error);
        },
      );
    } catch (error) {
      await _finishSession(sessionLease, error: error);
    }
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
      if (error != null) {
        _status = nfcSessionErrorMessage(context.l10n, error);
      }
    });
  }

  Future<void> _stopPairing() async {
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
          title: context.l10n.tr('staffPairUserTag'),
          children: <Widget>[
            Text(
              context.l10n.tr('staffPairUserDescription'),
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
            const SizedBox(height: 12),
            AdminStatusLine(label: context.l10n.tr('status'), value: _status),
            AdminStatusLine(label: 'UID', value: _lastUid),
            const SizedBox(height: 4),
            AdminPixelButton(
              label: context.l10n.tr(
                _isScanning ? 'stopScan' : 'staffPairStart',
              ),
              icon: _isScanning ? Icons.stop_rounded : Icons.nfc_rounded,
              color: _isScanning ? PixelTheme.warning : PixelTheme.accent,
              onPressed: _isScanning ? _stopPairing : _startPairing,
            ),
          ],
        ),
      ],
    );
  }
}
