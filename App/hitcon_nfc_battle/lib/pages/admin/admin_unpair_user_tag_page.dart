import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';

import '../../l10n/app_localizations.dart';
import '../../services/auth_service.dart';
import '../../services/nfc_deep_link_service.dart';
import '../../services/ntag_security_service.dart';
import '../user/pixel_theme.dart';
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

  String _status = '';
  String _lastUid = '-';
  bool _isScanning = false;
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
      unawaited(_stopSessionQuietly());
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
      await _finishWithError(error);
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
      _status = l10n.tr('staffUnpairHoldTag');
    });
    await _stopSessionQuietly();
    try {
      await NfcManager.instance.startSession(
        pollingOptions: const <NfcPollingOption>{NfcPollingOption.iso14443},
        onDiscovered: (NfcTag tag) async {
          if (_isHandlingTag || !mounted) {
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

          if (mounted) {
            setState(() {
              _lastUid = uid.isEmpty ? '-' : uid;
              _status = status;
            });
          }
          await Future<void>.delayed(_tagGracePeriod);
          await _stopSessionQuietly();
          _isHandlingTag = false;
          await _endDeepLinkSuppression();
          if (mounted) {
            setState(() {
              _isScanning = false;
            });
          }
        },
        onError: (dynamic error) async {
          await _finishWithError(error);
        },
      );
    } catch (error) {
      await _finishWithError(error);
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

  Future<void> _finishWithError(Object error) async {
    await _stopSessionQuietly();
    _isHandlingTag = false;
    await _endDeepLinkSuppression();
    if (!mounted) {
      return;
    }
    setState(() {
      _isScanning = false;
      _status = context.l10n.tr('nfcError', <String, Object?>{'error': error});
    });
  }

  Future<void> _stopUnpairing() async {
    if (_isHandlingTag) {
      return;
    }
    await _stopSessionQuietly();
    await _endDeepLinkSuppression();
    if (!mounted) {
      return;
    }
    setState(() {
      _isScanning = false;
      _status = context.l10n.tr('scanStopped');
    });
  }

  Future<void> _stopSessionQuietly() async {
    try {
      await NfcManager.instance.stopSession();
    } catch (_) {
      // Android may already have disposed the tag after the callback.
    }
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
            const SizedBox(height: 12),
            AdminStatusLine(label: context.l10n.tr('status'), value: _status),
            AdminStatusLine(label: 'UID', value: _lastUid),
            const SizedBox(height: 4),
            AdminPixelButton(
              key: const ValueKey<String>('staff-unpair-start-button'),
              label: context.l10n.tr(
                _isScanning ? 'stopScan' : 'staffUnpairStart',
              ),
              icon: _isScanning ? Icons.stop_rounded : Icons.link_off_rounded,
              color: PixelTheme.warning,
              onPressed: _isScanning ? _stopUnpairing : _startUnpairing,
            ),
          ],
        ),
      ],
    );
  }
}
