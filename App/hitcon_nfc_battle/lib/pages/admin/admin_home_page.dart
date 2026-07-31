import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';

import '../../l10n/app_localizations.dart';
import '../../services/auth_service.dart';
import '../../services/nfc_deep_link_service.dart';
import '../../services/nfc_tag_payload.dart';
import '../../services/ntag_security_service.dart';
import '../../widgets/admin_mode_switch_button.dart';
import '../user/pixel_theme.dart';
import 'admin_pair_user_tag_page.dart';
import 'admin_print_cards_page.dart';
import 'admin_scoreboard_control_page.dart';

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
        length: 6,
        child: Scaffold(
          backgroundColor: PixelTheme.bgDark,
          appBar: AppBar(
            backgroundColor: PixelTheme.bgMid,
            foregroundColor: PixelTheme.accent,
            leading: AdminModeSwitchButton(
              target: AdminModeTarget.gameplay,
              color: PixelTheme.accent,
            ),
            title: Text(context.l10n.tr('adminTools')),
            bottom: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorColor: PixelTheme.accent,
              labelColor: PixelTheme.accent,
              unselectedLabelColor: PixelTheme.textGray,
              tabs: [
                Tab(text: context.l10n.tr('writeTag')),
                Tab(text: context.l10n.tr('staffPairUserTagShort')),
                Tab(text: context.l10n.tr('confirmPrize')),
                Tab(text: context.l10n.tr('staffPrintShort')),
                Tab(text: context.l10n.tr('unlockTag')),
                Tab(text: context.l10n.tr('scoreboardControlShort')),
              ],
            ),
          ),
          body: const TabBarView(
            children: [
              AdminTagWriterPage(),
              AdminPairUserTagPage(),
              AdminPrizeClaimPage(),
              AdminPrintCardsPage(),
              AdminTagUnlockPage(),
              AdminScoreboardControlPage(),
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

  String _status = '';
  String _lastUid = '-';
  bool _isWriting = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_status.isEmpty) {
      _status = context.l10n.tr('prepareWritableTag');
    }
  }

  @override
  void dispose() {
    NfcManager.instance.stopSession();
    super.dispose();
  }

  Future<void> _writeTag() async {
    if (_isWriting) {
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
      _isWriting = true;
      _status = l10n.tr('holdTagToWrite');
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
            _status = l10n.tr('tagNotWritable');
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
            _status = l10n.tr('writeComplete');
          });
        } catch (error) {
          await NfcManager.instance.stopSession();
          if (!mounted) {
            return;
          }
          setState(() {
            _isWriting = false;
            _lastUid = uid.isEmpty ? '-' : uid;
            _status = l10n.tr('writeFailed', <String, Object?>{'error': error});
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
          _status = l10n.tr('nfcError', <String, Object?>{'error': error});
        });
      },
    );
  }

  NdefMessage _buildTagMessage() {
    return NfcTagPayload.buildUriMessage(Uri.parse(_blankAppUri));
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PixelPanel(
            title: context.l10n.tr('fixedAppUrl'),
            children: [
              _StatusLine(
                label: context.l10n.tr('purpose'),
                value: context.l10n.tr('blankUrlPurpose'),
              ),
              _StatusLine(
                label: context.l10n.tr('notice'),
                value: context.l10n.tr('pairingUrlNotice'),
              ),
              _StatusLine(label: 'URL', value: _blankAppUri),
            ],
          ),
          const SizedBox(height: 12),
          _PixelPanel(
            title: context.l10n.tr('writeStatus'),
            children: [
              _StatusLine(label: context.l10n.tr('status'), value: _status),
              _StatusLine(label: 'UID', value: _lastUid),
              _StatusLine(label: 'Landing URL', value: _previewLandingUrl),
            ],
          ),
          const SizedBox(height: 14),
          _PixelButton(
            label: context.l10n.tr(
              _isWriting ? 'waitingForTagShort' : 'writeTag',
            ),
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
  String _status = '';
  String _lastUid = '-';
  String _lastUserId = '-';
  String _claimCode = '-';
  bool _isScanning = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_status.isEmpty) {
      _status = context.l10n.tr('claimScanPrompt');
    }
  }

  @override
  void dispose() {
    NfcManager.instance.stopSession();
    super.dispose();
  }

  Future<void> _startScan() async {
    if (_isScanning) {
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
      _isScanning = true;
      _status = l10n.tr('scanAttendeeTag');
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
          _lastUserId = userId.isEmpty ? l10n.tr('tagHasNoUserId') : userId;
          if (result == null) {
            _status = l10n.tr('claimFailed');
            _claimCode = '-';
            return;
          }
          final bool alreadyClaimed = result['already_claimed'] == true;
          _status = l10n.tr(
            alreadyClaimed ? 'alreadyClaimed' : 'claimComplete',
          );
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
          _status = l10n.tr('nfcError', <String, Object?>{'error': error});
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
      _status = context.l10n.tr('scanStopped');
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
            title: context.l10n.tr('claimConfirmation'),
            children: [
              _StatusLine(label: context.l10n.tr('status'), value: _status),
              _StatusLine(label: 'UID', value: _lastUid),
              _StatusLine(label: 'User ID', value: _lastUserId),
              _StatusLine(
                label: context.l10n.tr('claimCode'),
                value: _claimCode,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _PixelButton(
            label: context.l10n.tr(_isScanning ? 'stopScan' : 'startScan'),
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
  static const Duration _tagDisposalGracePeriod = Duration(milliseconds: 400);

  String _status = '';
  String _lastUid = '-';
  String _lastUserId = '-';
  bool _isUnlocking = false;
  bool _isHandlingTag = false;
  bool _isFinishingUnlock = false;
  bool _isDisposed = false;
  bool _isSuppressingDeepLinks = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_status.isEmpty) {
      _status = context.l10n.tr('scanTagToUnlock');
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _endDeepLinkSuppression();
    if (!_isHandlingTag) {
      unawaited(_stopNfcSessionQuietly());
    }
    super.dispose();
  }

  Future<void> _unlockTag() async {
    if (_isUnlocking || _isDisposed) {
      return;
    }

    final AppLocalizations l10n = context.l10n;
    bool isAvailable = false;
    try {
      isAvailable = await NfcManager.instance.isAvailable();
    } catch (error) {
      if (mounted) {
        setState(() {
          _status = l10n.tr('nfcError', <String, Object?>{'error': error});
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

    _beginDeepLinkSuppression();
    setState(() {
      _isUnlocking = true;
      _status = l10n.tr('holdTagToUnlock');
      _lastUid = '-';
      _lastUserId = '-';
    });

    await _stopNfcSessionQuietly();
    try {
      await NfcManager.instance.startSession(
        pollingOptions: const <NfcPollingOption>{NfcPollingOption.iso14443},
        onDiscovered: (NfcTag tag) async {
          if (_isHandlingTag || _isDisposed) {
            return;
          }
          _isHandlingTag = true;

          String uid = '';
          Map<String, String> records = <String, String>{};
          NtagSecurityResult result;
          try {
            uid = _security.readTagId(tag);
            records = await _readTextRecords(tag);
            final String userId = records['user_id'] ?? '';
            final NtagLockSecret? secret = await AuthService()
                .requestNtagLockSecret(
                  uid: uid,
                  purpose: 'unlock',
                  userId: userId,
                );
            result = secret == null
                ? const NtagSecurityResult(
                    success: false,
                    messageKey: 'adminUnlockSecretFailed',
                  )
                : await _security.unlockForRewrite(tag, secret);
          } catch (error) {
            result = NtagSecurityResult(
              success: false,
              messageKey: 'nfcError',
              values: <String, Object?>{'error': error},
            );
          }

          if (mounted) {
            setState(() {
              _lastUid = uid.isEmpty ? '-' : uid;
              _lastUserId = records['user_id']?.trim().isNotEmpty == true
                  ? records['user_id']!
                  : l10n.tr('tagHasNoUserId');
              _status = l10n.tr(result.messageKey, result.values);
            });
          }
          unawaited(_finishUnlockHandling());
        },
        onError: (dynamic error) async {
          await _finishUnlockHandling(
            errorMessage: l10n.tr('nfcError', <String, Object?>{
              'error': error,
            }),
          );
        },
      );
    } catch (error) {
      await _finishUnlockHandling(
        errorMessage: l10n.tr('nfcError', <String, Object?>{'error': error}),
      );
    }
  }

  Future<void> _stopUnlock() async {
    if (_isHandlingTag) {
      return;
    }
    await _stopNfcSessionQuietly();
    _endDeepLinkSuppression();
    if (!mounted) {
      return;
    }
    setState(() {
      _isUnlocking = false;
      _status = context.l10n.tr('unlockStopped');
    });
  }

  Future<void> _finishUnlockHandling({String? errorMessage}) async {
    if (_isFinishingUnlock) {
      return;
    }
    _isFinishingUnlock = true;
    await Future<void>.delayed(_tagDisposalGracePeriod);
    await _stopNfcSessionQuietly();
    _isHandlingTag = false;
    _endDeepLinkSuppression();
    if (!mounted || _isDisposed) {
      return;
    }
    setState(() {
      _isUnlocking = false;
      _isFinishingUnlock = false;
      if (errorMessage != null) {
        _status = errorMessage;
      }
    });
  }

  Future<void> _stopNfcSessionQuietly() async {
    try {
      await NfcManager.instance.stopSession();
    } catch (_) {
      // The Android tag can already be disposed after a completed callback.
    }
  }

  void _beginDeepLinkSuppression() {
    if (_isSuppressingDeepLinks) {
      return;
    }
    _isSuppressingDeepLinks = true;
    NfcDeepLinkService.instance.beginTagMaintenance();
  }

  void _endDeepLinkSuppression() {
    if (!_isSuppressingDeepLinks) {
      return;
    }
    _isSuppressingDeepLinks = false;
    NfcDeepLinkService.instance.endTagMaintenance();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PixelPanel(
            title: context.l10n.tr('unlockTag'),
            children: [
              _StatusLine(label: context.l10n.tr('status'), value: _status),
              _StatusLine(label: 'UID', value: _lastUid),
              _StatusLine(label: 'User ID', value: _lastUserId),
              _StatusLine(
                label: context.l10n.tr('description'),
                value: context.l10n.tr('unlockTagDescription'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _PixelButton(
            label: context.l10n.tr(
              _isUnlocking ? 'stopScan' : 'unlockTagForRewrite',
            ),
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

  final String? uriUserId = NfcTagPayload.readUserId(message);
  if (uriUserId != null) {
    records['user_id'] = uriUserId;
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
