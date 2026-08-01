import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';

typedef RemoteConfigLoader = Future<String> Function(Uri uri);

class RemoteAppConfigService {
  RemoteAppConfigService({
    Uri? configUri,
    RemoteConfigLoader? loader,
    this.minimumRefreshInterval = const Duration(seconds: 10),
  }) : configUri = configUri ?? Uri.parse(AppConfig.remoteConfigUrl),
       _loader = loader ?? _download;

  static final RemoteAppConfigService instance = RemoteAppConfigService();

  static const String _cachedApiBaseUrlKey = 'remote_api_base_url_v1';
  static const String _cachedAllowUserTagUnlockKey =
      'remote_allow_user_tag_unlock_v1';
  static const String _cachedShowPanasonicLogoKey =
      'remote_show_panasonic_logo_v1';
  static const String _cachedShowPanasonicLogoOnPrintKey =
      'remote_show_panasonic_logo_on_print_v1';
  static const Duration _timeout = Duration(seconds: 4);
  static const int _maxConfigBytes = 16 * 1024;

  final Uri configUri;
  final RemoteConfigLoader _loader;
  final Duration minimumRefreshInterval;

  Future<bool>? _inFlight;
  DateTime? _lastRefreshStartedAt;

  /// Loads the last valid value first, then checks the hosted config.
  /// Returns true only when a fresh remote value was accepted.
  Future<bool> refresh({bool force = false}) {
    final Future<bool>? current = _inFlight;
    if (current != null) {
      return current;
    }

    final DateTime now = DateTime.now();
    final DateTime? previous = _lastRefreshStartedAt;
    if (!force &&
        previous != null &&
        now.difference(previous) < minimumRefreshInterval) {
      return Future<bool>.value(false);
    }
    _lastRefreshStartedAt = now;

    final Future<bool> request = _refresh();
    _inFlight = request;
    return request.whenComplete(() {
      if (identical(_inFlight, request)) {
        _inFlight = null;
      }
    });
  }

  Future<bool> _refresh() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? cached = prefs.getString(_cachedApiBaseUrlKey);
    if (cached != null && !AppConfig.tryApplyRemoteApiBaseUrl(cached)) {
      await prefs.remove(_cachedApiBaseUrlKey);
    }
    final bool? cachedAllowUserTagUnlock = prefs.getBool(
      _cachedAllowUserTagUnlockKey,
    );
    if (cachedAllowUserTagUnlock != null) {
      AppConfig.applyRemoteAllowUserTagUnlock(cachedAllowUserTagUnlock);
    }
    final bool? cachedShowPanasonicLogo = prefs.getBool(
      _cachedShowPanasonicLogoKey,
    );
    if (cachedShowPanasonicLogo != null) {
      AppConfig.applyRemoteShowPanasonicLogo(cachedShowPanasonicLogo);
    }
    final bool? cachedShowPanasonicLogoOnPrint = prefs.getBool(
      _cachedShowPanasonicLogoOnPrintKey,
    );
    AppConfig.applyRemoteShowPanasonicLogoOnPrint(
      cachedShowPanasonicLogoOnPrint ?? cachedShowPanasonicLogo ?? true,
    );

    try {
      final String document = await _loader(configUri).timeout(_timeout);
      final _RemoteAppConfig config = _parseConfig(document);
      if (!AppConfig.tryApplyRemoteApiBaseUrl(config.apiBaseUrl)) {
        throw const FormatException('Remote API URL is not trusted.');
      }
      AppConfig.applyRemoteAllowUserTagUnlock(config.allowUserTagUnlock);
      AppConfig.applyRemoteShowPanasonicLogo(config.showPanasonicLogo);
      AppConfig.applyRemoteShowPanasonicLogoOnPrint(
        config.showPanasonicLogoOnPrint,
      );
      await prefs.setString(_cachedApiBaseUrlKey, AppConfig.apiBaseUrl);
      await prefs.setBool(
        _cachedAllowUserTagUnlockKey,
        AppConfig.allowUserTagUnlock,
      );
      await prefs.setBool(
        _cachedShowPanasonicLogoKey,
        AppConfig.showPanasonicLogo,
      );
      await prefs.setBool(
        _cachedShowPanasonicLogoOnPrintKey,
        AppConfig.showPanasonicLogoOnPrint,
      );
      _log('Remote API config updated: ${AppConfig.apiBaseUrl}');
      return true;
    } catch (error) {
      _log(
        'Remote API config unavailable; using ${AppConfig.apiBaseUrl}: $error',
      );
      return false;
    }
  }

  _RemoteAppConfig _parseConfig(String document) {
    final dynamic decoded = jsonDecode(document);
    if (decoded is! Map || decoded['schema'] != 1) {
      throw const FormatException('Unsupported remote config schema.');
    }
    final Object? value = decoded['api_base_url'];
    if (value is! String || value.trim().isEmpty) {
      throw const FormatException('Remote config has no API base URL.');
    }
    final Object? allowUserTagUnlock = decoded['allow_user_tag_unlock'];
    if (allowUserTagUnlock != null && allowUserTagUnlock is! bool) {
      throw const FormatException('Invalid user Tag unlock setting.');
    }
    final Object? showPanasonicLogo = decoded['show_panasonic_logo'];
    if (showPanasonicLogo != null && showPanasonicLogo is! bool) {
      throw const FormatException('Invalid Panasonic logo setting.');
    }
    final Object? showPanasonicLogoOnPrint =
        decoded['show_panasonic_logo_on_print'];
    if (showPanasonicLogoOnPrint != null && showPanasonicLogoOnPrint is! bool) {
      throw const FormatException('Invalid print Panasonic logo setting.');
    }
    final bool appPanasonicLogo = showPanasonicLogo as bool? ?? true;
    return _RemoteAppConfig(
      apiBaseUrl: value.trim(),
      allowUserTagUnlock: allowUserTagUnlock as bool? ?? true,
      showPanasonicLogo: appPanasonicLogo,
      showPanasonicLogoOnPrint:
          showPanasonicLogoOnPrint as bool? ?? appPanasonicLogo,
    );
  }

  static Future<String> _download(Uri uri) async {
    if (uri.scheme != 'https' || uri.host.isEmpty) {
      throw const FormatException('Remote config URL must use HTTPS.');
    }

    final HttpClient client = HttpClient()..connectionTimeout = _timeout;
    try {
      final HttpClientRequest request = await client
          .getUrl(uri)
          .timeout(_timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache, no-store');
      final HttpClientResponse response = await request.close().timeout(
        _timeout,
      );
      if (response.statusCode != HttpStatus.ok) {
        // Finish the response stream before the authentication request starts.
        await response.drain<void>().timeout(_timeout);
        throw HttpException(
          'Remote config returned HTTP ${response.statusCode}.',
          uri: uri,
        );
      }
      if (response.contentLength > _maxConfigBytes) {
        await response.drain<void>().timeout(_timeout);
        throw const FormatException('Remote config is too large.');
      }

      final BytesBuilder bytes = BytesBuilder(copy: false);
      bool exceedsLimit = false;
      await for (final List<int> chunk in response.timeout(_timeout)) {
        if (exceedsLimit || bytes.length + chunk.length > _maxConfigBytes) {
          exceedsLimit = true;
          continue;
        }
        bytes.add(chunk);
      }
      if (exceedsLimit) {
        throw const FormatException('Remote config is too large.');
      }
      return utf8.decode(bytes.takeBytes());
    } finally {
      client.close();
    }
  }

  void _log(String message) {
    if (AppConfig.enableDebugLogging) {
      debugPrint('[RemoteConfig] $message');
    }
  }
}

class _RemoteAppConfig {
  const _RemoteAppConfig({
    required this.apiBaseUrl,
    required this.allowUserTagUnlock,
    required this.showPanasonicLogo,
    required this.showPanasonicLogoOnPrint,
  });

  final String apiBaseUrl;
  final bool allowUserTagUnlock;
  final bool showPanasonicLogo;
  final bool showPanasonicLogoOnPrint;
}
