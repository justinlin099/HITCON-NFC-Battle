import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/auth_service.dart';
import '../user/pixel_theme.dart';
import 'admin_pixel_widgets.dart';

class AdminScoreboardControlPage extends StatefulWidget {
  const AdminScoreboardControlPage({super.key});

  @override
  State<AdminScoreboardControlPage> createState() =>
      _AdminScoreboardControlPageState();
}

class _AdminScoreboardControlPageState
    extends State<AdminScoreboardControlPage> {
  final AuthService _authService = AuthService();
  final TextEditingController _dangerTokenController = TextEditingController();

  Map<String, dynamic> _scoreboard = <String, dynamic>{};
  bool _isBusy = false;
  String _status = '';

  String get _state => (_scoreboard['state'] as String? ?? '').toUpperCase();
  bool get _canFreeze => _state == 'OPEN';
  bool get _canResume =>
      _state == 'FROZEN' ||
      (_state == 'FREEZING' && _scoreboard['freezing_stale'] == true);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_status.isEmpty) {
      _status = context.l10n.tr('scoreboardAdminTokenPrompt');
    }
  }

  @override
  void dispose() {
    _dangerTokenController.clear();
    _dangerTokenController.dispose();
    super.dispose();
  }

  String? _dangerToken() {
    final String value = _dangerTokenController.text.trim();
    if (value.isEmpty) {
      setState(() {
        _status = context.l10n.tr('scoreboardDangerTokenRequired');
      });
      return null;
    }
    return value;
  }

  Future<void> _refresh() async {
    if (_isBusy) {
      return;
    }
    final String? dangerToken = _dangerToken();
    if (dangerToken == null) {
      return;
    }
    setState(() {
      _isBusy = true;
      _status = context.l10n.tr('scoreboardStatusLoading');
    });
    final Map<String, dynamic>? result = await _authService
        .fetchStaffScoreboardStatus(dangerToken);
    if (!mounted) {
      return;
    }
    setState(() {
      _isBusy = false;
      if (result == null) {
        _status = context.l10n.tr('scoreboardAdminRequestFailed');
      } else {
        _scoreboard = result;
        _status = context.l10n.tr('scoreboardStatusLoaded');
      }
    });
  }

  Future<void> _freeze() async {
    final String? dangerToken = _dangerToken();
    if (dangerToken == null ||
        !await _confirm(
          title: context.l10n.tr('freezeScoreboard'),
          body: context.l10n.tr('freezeScoreboardWarning'),
          action: context.l10n.tr('confirmFreeze'),
          color: PixelTheme.warning,
        )) {
      return;
    }
    setState(() {
      _isBusy = true;
      _status = context.l10n.tr('freezingScoreboard');
    });
    final Map<String, dynamic>? result = await _authService
        .freezeStaffScoreboard(dangerToken);
    if (!mounted) {
      return;
    }
    setState(() {
      _isBusy = false;
      _status = context.l10n.tr(
        result == null ? 'scoreboardAdminRequestFailed' : 'scoreboardFrozen',
      );
      if (result != null) {
        _scoreboard = <String, dynamic>{
          ..._scoreboard,
          ...result,
          'state': 'FROZEN',
        };
      }
    });
  }

  Future<void> _resume() async {
    final String? dangerToken = _dangerToken();
    if (dangerToken == null ||
        !await _confirm(
          title: context.l10n.tr('resumeScoreboard'),
          body: context.l10n.tr('resumeScoreboardWarning'),
          action: context.l10n.tr('confirmResume'),
          color: PixelTheme.warning,
        )) {
      return;
    }
    setState(() {
      _isBusy = true;
      _status = context.l10n.tr('resumingScoreboard');
    });
    final bool resumed = await _authService.resumeStaffScoreboard(dangerToken);
    if (!mounted) {
      return;
    }
    setState(() {
      _isBusy = false;
      _status = context.l10n.tr(
        resumed ? 'scoreboardResumed' : 'scoreboardAdminRequestFailed',
      );
      if (resumed) {
        _scoreboard = <String, dynamic>{'state': 'OPEN'};
      }
    });
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
    required Color color,
  }) async {
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
                title,
                style: TextStyle(
                  color: color,
                  fontFamily: 'Unifont',
                  fontWeight: FontWeight.w900,
                ),
              ),
              content: Text(
                body,
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
                  child: Text(action, style: TextStyle(color: color)),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  String _value(String key) {
    final Object? value = _scoreboard[key];
    return value == null || value.toString().trim().isEmpty
        ? '-'
        : value.toString();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: <Widget>[
        AdminPixelPanel(
          title: context.l10n.tr('scoreboardControl'),
          children: <Widget>[
            Text(
              context.l10n.tr('scoreboardDangerTokenNotice'),
              style: TextStyle(
                color: PixelTheme.warning,
                fontFamily: 'Unifont',
                fontSize: 11,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 12),
            AdminPixelTextField(
              controller: _dangerTokenController,
              label: 'STAFF_DANGER_TOKEN',
              obscureText: true,
              onSubmitted: (_) => _refresh(),
            ),
            const SizedBox(height: 12),
            AdminStatusLine(label: context.l10n.tr('status'), value: _status),
            AdminStatusLine(
              label: context.l10n.tr('scoreboardState'),
              value: _state.isEmpty ? '-' : _state,
            ),
            AdminStatusLine(label: 'Freeze ID', value: _value('freeze_id')),
            AdminStatusLine(
              label: context.l10n.tr('freezeStartedAt'),
              value: _value('freeze_started_at'),
            ),
            AdminStatusLine(
              label: context.l10n.tr('frozenAt'),
              value: _value('frozen_at'),
            ),
            AdminStatusLine(
              label: context.l10n.tr('scoringCutoffAt'),
              value: _value('scoring_cutoff_at'),
            ),
            AdminStatusLine(
              label: context.l10n.tr('freezeTimeout'),
              value: _value('freeze_timeout_seconds'),
            ),
            AdminStatusLine(
              label: context.l10n.tr('freezingStale'),
              value: _value('freezing_stale'),
            ),
            const SizedBox(height: 4),
            AdminPixelButton(
              label: context.l10n.tr('refreshStatus'),
              icon: Icons.refresh_rounded,
              onPressed: _isBusy ? null : _refresh,
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: AdminPixelButton(
                    label: context.l10n.tr('freezeScoreboard'),
                    icon: Icons.pause_rounded,
                    color: PixelTheme.warning,
                    onPressed: _isBusy || !_canFreeze ? null : _freeze,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AdminPixelButton(
                    label: context.l10n.tr('resumeScoreboard'),
                    icon: Icons.play_arrow_rounded,
                    color: PixelTheme.success,
                    onPressed: _isBusy || !_canResume ? null : _resume,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
