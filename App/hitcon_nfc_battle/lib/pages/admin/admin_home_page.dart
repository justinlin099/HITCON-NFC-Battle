import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';

import '../../config/app_config.dart';
import '../../l10n/app_localizations.dart';
import '../../services/auth_service.dart';
import '../../services/nfc_deep_link_service.dart';
import '../../services/nfc_error_messages.dart';
import '../../services/nfc_session_controller.dart';
import '../../services/nfc_tag_payload.dart';
import '../../services/ntag_security_service.dart';
import '../../widgets/admin_mode_switch_button.dart';
import '../user/pixel_theme.dart';
import 'admin_nfc_session.dart';
import 'admin_pair_user_tag_page.dart';
import 'admin_print_cards_page.dart';
import 'admin_scoreboard_control_page.dart';
import 'admin_unpair_user_tag_page.dart';

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
  }

  @override
  Widget build(BuildContext context) {
    PixelTheme.active = PixelTheme.getPalette(PixelTheme.defaultScheme);

    return DefaultTextStyle.merge(
      style: const TextStyle(fontFamily: 'Unifont'),
      child: DefaultTabController(
        length: 7,
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
                Tab(text: context.l10n.tr('staffUnpairUserTagShort')),
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
              AdminUnpairUserTagPage(),
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
  static const Duration _sameTagCooldown = Duration(seconds: 3);
  static const Duration _tagHandlingGracePeriod = Duration(milliseconds: 500);

  final AdminNfcSession _nfcSession = AdminNfcSession();
  String _status = '';
  String _lastUid = '-';
  String _lastHandledUid = '';
  DateTime _lastHandledAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _isWriting = false;
  bool _isHandlingTag = false;
  bool _isDisposed = false;
  bool _isMaintainingNfc = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_status.isEmpty) {
      _status = context.l10n.tr('prepareWritableTag');
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    unawaited(_stopContinuousWriting(updateState: false));
    super.dispose();
  }

  Future<void> _writeTag() async {
    if (_isWriting) {
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

    await _beginNfcMaintenance();
    if (!mounted || _isDisposed) {
      return;
    }
    setState(() {
      _isWriting = true;
      _status = l10n.tr('holdTagToWrite');
      _lastUid = '-';
      _lastHandledUid = '';
    });

    NfcSessionLease? sessionLease;
    try {
      sessionLease = await _nfcSession.acquire(onPreempt: _handlePreempted);
      if (sessionLease == null) {
        await _endNfcMaintenance();
        if (mounted) {
          setState(() {
            _isWriting = false;
            _status = l10n.tr('nfcSessionBusy');
          });
        }
        return;
      }
      final NfcSessionLease activeLease = sessionLease;

      await NfcManager.instance.startSession(
        pollingOptions: const <NfcPollingOption>{NfcPollingOption.iso14443},
        onDiscovered: (NfcTag tag) =>
            _handleWritableTag(tag, l10n, activeLease),
        onError: (NfcError error) async {
          await _finishWritingWithError(error, l10n, activeLease);
        },
      );
    } catch (error) {
      await _finishWritingWithError(error, l10n, sessionLease);
    }
  }

  Future<void> _handlePreempted() async {
    _isHandlingTag = false;
    await _endNfcMaintenance();
    if (!mounted || _isDisposed) {
      return;
    }
    setState(() {
      _isWriting = false;
      _status = context.l10n.tr('nfcSessionBusy');
    });
  }

  Future<void> _handleWritableTag(
    NfcTag tag,
    AppLocalizations l10n,
    NfcSessionLease sessionLease,
  ) async {
    if (!sessionLease.isActive ||
        _isHandlingTag ||
        !_isWriting ||
        _isDisposed) {
      return;
    }

    final String uid = const NtagSecurityService().readTagId(tag);
    final DateTime now = DateTime.now();
    if (uid.isNotEmpty &&
        uid == _lastHandledUid &&
        now.difference(_lastHandledAt) < _sameTagCooldown) {
      return;
    }

    _isHandlingTag = true;
    _lastHandledUid = uid;
    _lastHandledAt = now;
    String status;
    try {
      final Ndef? ndef = Ndef.from(tag);
      if (ndef == null || !ndef.isWritable) {
        status = l10n.tr('tagNotWritableContinue');
      } else {
        await ndef.write(_buildTagMessage());
        status = l10n.tr('writeCompleteContinue');
      }
    } catch (error) {
      status = l10n.tr('writeFailedContinue', <String, Object?>{
        'error': nfcErrorDetail(l10n, error),
      });
    }

    if (mounted && !_isDisposed && sessionLease.isActive) {
      setState(() {
        _lastUid = uid.isEmpty ? '-' : uid;
        _status = status;
      });
    }
    await Future<void>.delayed(_tagHandlingGracePeriod);
    _isHandlingTag = false;
  }

  Future<void> _finishWritingWithError(
    Object error,
    AppLocalizations l10n,
    NfcSessionLease? sessionLease,
  ) async {
    if (sessionLease != null && !sessionLease.isActive) {
      return;
    }
    if (sessionLease != null) {
      await _nfcSession.stop(sessionLease);
    }
    await _endNfcMaintenance();
    _isHandlingTag = false;
    if (!mounted || _isDisposed) {
      return;
    }
    setState(() {
      _isWriting = false;
      _status = nfcSessionErrorMessage(l10n, error);
    });
  }

  Future<void> _stopContinuousWriting({bool updateState = true}) async {
    if (_isHandlingTag && updateState) {
      return;
    }
    await _nfcSession.stop();
    await _endNfcMaintenance();
    _isHandlingTag = false;
    if (!updateState || !mounted || _isDisposed) {
      return;
    }
    setState(() {
      _isWriting = false;
      _status = context.l10n.tr('scanStopped');
    });
  }

  Future<void> _beginNfcMaintenance() async {
    if (_isMaintainingNfc) {
      return;
    }
    _isMaintainingNfc = true;
    await NfcDeepLinkService.instance.beginTagMaintenance();
  }

  Future<void> _endNfcMaintenance() async {
    if (!_isMaintainingNfc) {
      return;
    }
    _isMaintainingNfc = false;
    await NfcDeepLinkService.instance.endTagMaintenance();
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
            label: context.l10n.tr(_isWriting ? 'stopScan' : 'writeTag'),
            color: _isWriting ? PixelTheme.warning : PixelTheme.accent,
            onTap: _isWriting ? _stopContinuousWriting : _writeTag,
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
  final AdminNfcSession _nfcSession = AdminNfcSession();
  String _status = '';
  String _lastUid = '-';
  String _lastUserId = '-';
  String _claimCode = '-';
  PrizeClaimType _selectedPrizeType = PrizeClaimType.stamp;
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
    _nfcSession.dispose();
    super.dispose();
  }

  Future<void> _startScan() async {
    if (_isScanning) {
      return;
    }

    final AppLocalizations l10n = context.l10n;
    final PrizeClaimType claimType = _selectedPrizeType;
    setState(() {
      _isScanning = true;
      _status = l10n.tr('scanAttendeeTag');
      _lastUid = '-';
      _lastUserId = '-';
      _claimCode = '-';
    });

    NfcSessionLease? sessionLease;
    try {
      final bool isAvailable = await NfcManager.instance.isAvailable();
      if (!isAvailable) {
        if (mounted) {
          setState(() {
            _isScanning = false;
            _status = l10n.tr('nfcUnavailable');
          });
        }
        return;
      }

      sessionLease = await _nfcSession.acquire(onPreempt: _handlePreempted);
      if (sessionLease == null) {
        if (mounted) {
          setState(() {
            _isScanning = false;
            _status = l10n.tr('nfcSessionBusy');
          });
        }
        return;
      }
      final NfcSessionLease activeLease = sessionLease;

      await NfcManager.instance.startSession(
        pollingOptions: const <NfcPollingOption>{NfcPollingOption.iso14443},
        onDiscovered: (NfcTag tag) async {
          final String uid = const NtagSecurityService().readTagId(tag);
          final Map<String, String> records = await _readTextRecords(tag);
          final String userId = records['user_id'] ?? records['owner'] ?? '';
          final Map<String, dynamic>? result = await _authService
              .confirmPrizeClaim(tagUid: uid, userId: userId, type: claimType);

          await _nfcSession.stop(activeLease);
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
        onError: (NfcError error) async {
          await _nfcSession.stop(activeLease);
          if (!mounted) {
            return;
          }
          setState(() {
            _isScanning = false;
            _status = nfcSessionErrorMessage(l10n, error);
          });
        },
      );
    } catch (error) {
      if (sessionLease != null) {
        await _nfcSession.stop(sessionLease);
      }
      if (mounted) {
        setState(() {
          _isScanning = false;
          _status = nfcSessionErrorMessage(l10n, error);
        });
      }
    }
  }

  Future<void> _stopScan() async {
    await _nfcSession.stop();
    if (!mounted) {
      return;
    }
    setState(() {
      _isScanning = false;
      _status = context.l10n.tr('scanStopped');
    });
  }

  Future<void> _handlePreempted() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _isScanning = false;
      _status = context.l10n.tr('nfcSessionBusy');
    });
  }

  void _selectPrizeType(PrizeClaimType type) {
    if (_isScanning || type == _selectedPrizeType) {
      return;
    }
    setState(() {
      _selectedPrizeType = type;
      _status = context.l10n.tr('claimScanPrompt');
      _lastUid = '-';
      _lastUserId = '-';
      _claimCode = '-';
    });
  }

  String _prizeTypeLabel(PrizeClaimType type) {
    return context.l10n.tr(switch (type) {
      PrizeClaimType.stamp => 'stampPrizeClaim',
      PrizeClaimType.ranking => 'rankingPrizeClaim',
      PrizeClaimType.external => 'externalPrizeClaim',
    });
  }

  String _prizeTypeHint(PrizeClaimType type) {
    return context.l10n.tr(switch (type) {
      PrizeClaimType.stamp => 'stampPrizeClaimHint',
      PrizeClaimType.ranking => 'rankingPrizeClaimHint',
      PrizeClaimType.external => 'externalPrizeClaimHint',
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _PixelPanel(
          title: context.l10n.tr('claimPrizeType'),
          children: <Widget>[
            for (final PrizeClaimType type in const <PrizeClaimType>[
              PrizeClaimType.stamp,
              PrizeClaimType.ranking,
              PrizeClaimType.external,
            ]) ...<Widget>[
              _PrizeTypeChoice(
                type: type,
                label: _prizeTypeLabel(type),
                hint: _prizeTypeHint(type),
                selected: type == _selectedPrizeType,
                enabled: !_isScanning,
                onTap: () => _selectPrizeType(type),
              ),
              if (type != PrizeClaimType.external) const SizedBox(height: 10),
            ],
          ],
        ),
        const SizedBox(height: 14),
        _PixelPanel(
          title: context.l10n.tr('claimConfirmation'),
          children: [
            _StatusLine(
              label: context.l10n.tr('claimPrizeType'),
              value: _prizeTypeLabel(_selectedPrizeType),
            ),
            _StatusLine(label: context.l10n.tr('status'), value: _status),
            _StatusLine(label: 'UID', value: _lastUid),
            _StatusLine(label: 'User ID', value: _lastUserId),
            _StatusLine(label: context.l10n.tr('claimCode'), value: _claimCode),
          ],
        ),
        const SizedBox(height: 14),
        _PixelButton(
          label: context.l10n.tr(_isScanning ? 'stopScan' : 'startScan'),
          color: _isScanning ? PixelTheme.warning : PixelTheme.accent,
          onTap: _isScanning ? _stopScan : _startScan,
        ),
      ],
    );
  }
}

class _PrizeTypeChoice extends StatelessWidget {
  const _PrizeTypeChoice({
    required this.type,
    required this.label,
    required this.hint,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final PrizeClaimType type;
  final String label;
  final String hint;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color accent = selected ? PixelTheme.accent : PixelTheme.border;
    final Color foreground = enabled
        ? PixelTheme.textWhite
        : PixelTheme.textGray;
    return GestureDetector(
      key: ValueKey<String>('prize-type-${type.apiValue}'),
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Container(
        key: selected
            ? ValueKey<String>('selected-prize-type-${type.apiValue}')
            : null,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? PixelTheme.bgDark : PixelTheme.bgMid,
          border: Border.all(color: accent, width: 2),
          boxShadow: selected
              ? const <BoxShadow>[
                  BoxShadow(
                    color: Colors.black,
                    blurRadius: 0,
                    offset: Offset(3, 3),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 18,
              height: 18,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? PixelTheme.accent : PixelTheme.bgDark,
                border: Border.all(color: accent, width: 2),
              ),
              child: selected
                  ? Text(
                      '✓',
                      style: TextStyle(
                        color: PixelTheme.bgDark,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    label,
                    style: TextStyle(
                      color: selected ? PixelTheme.accent : foreground,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    hint,
                    style: TextStyle(
                      color: enabled ? PixelTheme.textGray : foreground,
                      fontSize: 11,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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

  final AdminNfcSession _nfcSession = AdminNfcSession();
  String _status = '';
  String _lastUid = '-';
  String _lastUserId = '-';
  bool _isUnlocking = false;
  bool _isHandlingTag = false;
  bool _isFinishingUnlock = false;
  bool _isDisposed = false;
  bool _isSuppressingDeepLinks = false;
  StaffNtagUnlockApiTarget _apiTarget = StaffNtagUnlockApiTarget.production;
  String? _stagingAuthToken;

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
    unawaited(_endDeepLinkSuppression());
    if (!_isHandlingTag) {
      _nfcSession.dispose();
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

    final StaffNtagUnlockApiTarget apiTarget = _apiTarget;
    final String? stagingAuthToken =
        apiTarget == StaffNtagUnlockApiTarget.staging
        ? _stagingAuthToken
        : null;

    await _beginDeepLinkSuppression();
    if (_isDisposed) {
      return;
    }
    setState(() {
      _isUnlocking = true;
      _status = l10n.tr('holdTagToUnlock');
      _lastUid = '-';
      _lastUserId = '-';
    });

    NfcSessionLease? sessionLease;
    try {
      sessionLease = await _nfcSession.acquire(onPreempt: _handlePreempted);
      if (sessionLease == null) {
        await _endDeepLinkSuppression();
        if (mounted) {
          setState(() {
            _isUnlocking = false;
            _status = l10n.tr('nfcSessionBusy');
          });
        }
        return;
      }
      final NfcSessionLease activeLease = sessionLease;

      await NfcManager.instance.startSession(
        pollingOptions: const <NfcPollingOption>{NfcPollingOption.iso14443},
        onDiscovered: (NfcTag tag) async {
          if (!activeLease.isActive || _isHandlingTag || _isDisposed) {
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
            final AuthService authService = AuthService();
            final NtagLockSecret? secret = await authService
                .requestNtagLockSecret(
                  uid: uid,
                  purpose: 'unlock',
                  userId: userId,
                  staffApiTarget: apiTarget,
                  stagingAuthToken: stagingAuthToken,
                );
            result = secret == null
                ? NtagSecurityResult(
                    success: false,
                    messageKey: 'adminUnlockSecretFailedWithReason',
                    values: <String, Object?>{
                      'reason':
                          authService.lastNtagSecretError ?? l10n.tr('unknown'),
                    },
                  )
                : await _security.unlockForRewrite(tag, secret);
          } catch (error) {
            result = NtagSecurityResult(
              success: false,
              messageKey: 'nfcError',
              values: <String, Object?>{'error': error},
            );
          }

          if (mounted && activeLease.isActive) {
            setState(() {
              _lastUid = uid.isEmpty ? '-' : uid;
              _lastUserId = records['user_id']?.trim().isNotEmpty == true
                  ? records['user_id']!
                  : l10n.tr('tagHasNoUserId');
              _status = l10n.tr(result.messageKey, result.values);
            });
          }
          unawaited(_finishUnlockHandling(activeLease));
        },
        onError: (NfcError error) async {
          await _finishUnlockHandling(
            activeLease,
            errorMessage: nfcSessionErrorMessage(l10n, error),
          );
        },
      );
    } catch (error) {
      if (sessionLease != null) {
        await _finishUnlockHandling(
          sessionLease,
          errorMessage: nfcSessionErrorMessage(l10n, error),
        );
      } else {
        await _endDeepLinkSuppression();
        if (mounted) {
          setState(() {
            _isUnlocking = false;
            _status = nfcSessionErrorMessage(l10n, error);
          });
        }
      }
    }
  }

  Future<void> _stopUnlock() async {
    if (_isHandlingTag) {
      return;
    }
    await _nfcSession.stop();
    await _endDeepLinkSuppression();
    if (!mounted) {
      return;
    }
    setState(() {
      _isUnlocking = false;
      _status = context.l10n.tr('unlockStopped');
    });
  }

  Future<void> _finishUnlockHandling(
    NfcSessionLease sessionLease, {
    String? errorMessage,
  }) async {
    if (_isFinishingUnlock || !sessionLease.isActive) {
      return;
    }
    _isFinishingUnlock = true;
    await Future<void>.delayed(_tagDisposalGracePeriod);
    if (!sessionLease.isActive) {
      _isFinishingUnlock = false;
      return;
    }
    await _nfcSession.stop(sessionLease);
    _isHandlingTag = false;
    await _endDeepLinkSuppression();
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

  Future<void> _handlePreempted() async {
    _isHandlingTag = false;
    _isFinishingUnlock = false;
    await _endDeepLinkSuppression();
    if (!mounted || _isDisposed) {
      return;
    }
    setState(() {
      _isUnlocking = false;
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

  Future<void> _selectStagingApi() async {
    if (_isUnlocking) {
      return;
    }
    final String? token = await _promptForStagingToken();
    if (!mounted || token == null) {
      return;
    }
    setState(() {
      _stagingAuthToken = token;
      _apiTarget = StaffNtagUnlockApiTarget.staging;
    });
  }

  Future<String?> _promptForStagingToken() async {
    final TextEditingController controller = TextEditingController();
    String? errorText;
    final String? token = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            void submit() {
              final String value = controller.text.trim();
              if (value.isEmpty) {
                setDialogState(() {
                  errorText = context.l10n.tr('stagingLoginTokenRequired');
                });
                return;
              }
              Navigator.of(dialogContext).pop(value);
            }

            return AlertDialog(
              backgroundColor: PixelTheme.bgMid,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
                side: BorderSide(color: PixelTheme.accent, width: 2),
              ),
              title: Text(
                context.l10n.tr('stagingLoginTokenTitle'),
                style: TextStyle(
                  color: PixelTheme.accent,
                  fontFamily: 'Unifont',
                  fontWeight: FontWeight.w900,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    context.l10n.tr('stagingLoginTokenDescription'),
                    style: TextStyle(
                      color: PixelTheme.textWhite,
                      fontFamily: 'Unifont',
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    key: const ValueKey<String>('staging-login-token-field'),
                    controller: controller,
                    autofocus: true,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    onSubmitted: (_) => submit(),
                    onChanged: (_) {
                      if (errorText != null) {
                        setDialogState(() {
                          errorText = null;
                        });
                      }
                    },
                    style: TextStyle(
                      color: PixelTheme.textWhite,
                      fontFamily: 'Unifont',
                      fontSize: 12,
                    ),
                    decoration: InputDecoration(
                      labelText: context.l10n.tr('stagingLoginTokenLabel'),
                      errorText: errorText,
                      labelStyle: TextStyle(
                        color: PixelTheme.textGray,
                        fontFamily: 'Unifont',
                      ),
                      errorStyle: TextStyle(
                        color: PixelTheme.warning,
                        fontFamily: 'Unifont',
                      ),
                      filled: true,
                      fillColor: PixelTheme.bgDark,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(
                          color: PixelTheme.border,
                          width: 2,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(
                          color: PixelTheme.accent,
                          width: 2,
                        ),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(
                          color: PixelTheme.warning,
                          width: 2,
                        ),
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(
                          color: PixelTheme.warning,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  key: const ValueKey<String>('cancel-staging-token'),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  style: TextButton.styleFrom(
                    foregroundColor: PixelTheme.textGray,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero,
                    ),
                  ),
                  child: Text(
                    context.l10n.tr('cancel'),
                    style: const TextStyle(
                      fontFamily: 'Unifont',
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                TextButton(
                  key: const ValueKey<String>('confirm-staging-token'),
                  onPressed: submit,
                  style: TextButton.styleFrom(
                    foregroundColor: PixelTheme.accent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero,
                      side: BorderSide(color: PixelTheme.accent, width: 2),
                    ),
                  ),
                  child: Text(
                    context.l10n.tr('confirm'),
                    style: const TextStyle(
                      fontFamily: 'Unifont',
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();
    return token;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: ListView(
        children: [
          _PixelPanel(
            title: context.l10n.tr('unlockCodeApiSource'),
            children: <Widget>[
              _UnlockApiChoice(
                target: StaffNtagUnlockApiTarget.production,
                label: context.l10n.tr('productionApi'),
                hint: context.l10n.tr('productionApiHint', <String, Object?>{
                  'url': AppConfig.apiBaseUrl,
                }),
                selected: _apiTarget == StaffNtagUnlockApiTarget.production,
                enabled: !_isUnlocking,
                onTap: () {
                  setState(() {
                    _stagingAuthToken = null;
                    _apiTarget = StaffNtagUnlockApiTarget.production;
                  });
                },
              ),
              const SizedBox(height: 10),
              _UnlockApiChoice(
                target: StaffNtagUnlockApiTarget.staging,
                label: context.l10n.tr('stagingApi'),
                hint: context.l10n.tr('stagingApiHint', <String, Object?>{
                  'url': AppConfig.staffUnlockStagingApiBaseUrl,
                }),
                selected: _apiTarget == StaffNtagUnlockApiTarget.staging,
                enabled: !_isUnlocking,
                onTap: _selectStagingApi,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _PixelPanel(
            title: context.l10n.tr('unlockTag'),
            children: [
              _StatusLine(
                label: context.l10n.tr('unlockCodeApiSource'),
                value: context.l10n.tr(
                  _apiTarget == StaffNtagUnlockApiTarget.production
                      ? 'productionApi'
                      : 'stagingApi',
                ),
              ),
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

class _UnlockApiChoice extends StatelessWidget {
  const _UnlockApiChoice({
    required this.target,
    required this.label,
    required this.hint,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final StaffNtagUnlockApiTarget target;
  final String label;
  final String hint;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  String get _targetKey => target.name;

  @override
  Widget build(BuildContext context) {
    final Color accent = selected ? PixelTheme.accent : PixelTheme.border;
    final Color foreground = enabled
        ? PixelTheme.textWhite
        : PixelTheme.textGray;
    return GestureDetector(
      key: ValueKey<String>('staff-unlock-api-$_targetKey'),
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Container(
        key: selected
            ? ValueKey<String>('selected-staff-unlock-api-$_targetKey')
            : null,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? PixelTheme.bgDark : PixelTheme.bgMid,
          border: Border.all(color: accent, width: 2),
          boxShadow: selected
              ? const <BoxShadow>[
                  BoxShadow(
                    color: Colors.black,
                    blurRadius: 0,
                    offset: Offset(3, 3),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 18,
              height: 18,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? PixelTheme.accent : PixelTheme.bgDark,
                border: Border.all(color: accent, width: 2),
              ),
              child: selected
                  ? Text(
                      '✓',
                      style: TextStyle(
                        color: PixelTheme.bgDark,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    label,
                    style: TextStyle(
                      color: selected ? PixelTheme.accent : foreground,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    hint,
                    style: TextStyle(
                      color: enabled ? PixelTheme.textGray : foreground,
                      fontSize: 11,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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
