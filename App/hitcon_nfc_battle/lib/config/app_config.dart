import 'package:flutter/foundation.dart';

import 'achievement_config.dart';

/// 應用程式設定
class AppConfig {
  /// 打包時的後端 API 回退 URL。
  static const String bundledApiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://nfc-battle-staging.hitcon2026.online',
  );

  /// 與 Universal Links / App Links 一起部署的遠端設定。
  static const String remoteConfigUrl = String.fromEnvironment(
    'REMOTE_CONFIG_URL',
    defaultValue:
        'https://game.hitcon2026.online/.well-known/nfc-battle-app-config.json',
  );

  static String _apiBaseUrl = bundledApiBaseUrl;
  static bool _allowUserTagUnlock = true;
  static bool _showPanasonicLogo = true;
  static bool _showPanasonicLogoOnPrint = true;
  static String? _manualUrl;
  static AchievementRules? _achievementRules;
  static final ValueNotifier<bool> allowUserTagUnlockListenable =
      ValueNotifier<bool>(true);
  static final ValueNotifier<bool> showPanasonicLogoListenable =
      ValueNotifier<bool>(true);
  static final ValueNotifier<bool> showPanasonicLogoOnPrintListenable =
      ValueNotifier<bool>(true);
  static final ValueNotifier<String?> manualUrlListenable =
      ValueNotifier<String?>(null);
  static final ValueNotifier<AchievementRules?> achievementRulesListenable =
      ValueNotifier<AchievementRules?>(null);

  /// 當前 API 基礎 URL，可在啟動時由受信任的遠端設定更新。
  static String get apiBaseUrl => _apiBaseUrl;

  /// 是否允許一般使用者解除自己 Tag 的寫入保護。
  static bool get allowUserTagUnlock => _allowUserTagUnlock;

  /// Whether Panasonic branding is shown in app card interfaces.
  static bool get showPanasonicLogo => _showPanasonicLogo;

  /// Whether Panasonic branding is shown in print previews and print artwork.
  static bool get showPanasonicLogoOnPrint => _showPanasonicLogoOnPrint;

  /// GitHub-hosted user manual configured by the remote JSON.
  static String? get manualUrl => _manualUrl;

  /// Achievement rules from the hosted JSON. Null means no remote rules exist.
  static AchievementRules? get achievementRules => _achievementRules;

  /// 只接受 HITCON 2026 的 HTTPS host，避免 JWT 被導向第三方。
  static bool tryApplyRemoteApiBaseUrl(String value) {
    final Uri? uri = Uri.tryParse(value.trim());
    if (uri == null || !_isTrustedApiUri(uri)) {
      return false;
    }
    _apiBaseUrl = uri.replace(path: _normalizedPath(uri.path)).toString();
    return true;
  }

  static void applyRemoteAllowUserTagUnlock(bool value) {
    _allowUserTagUnlock = value;
    if (allowUserTagUnlockListenable.value != value) {
      allowUserTagUnlockListenable.value = value;
    }
  }

  static void applyRemoteShowPanasonicLogo(bool value) {
    _showPanasonicLogo = value;
    if (showPanasonicLogoListenable.value != value) {
      showPanasonicLogoListenable.value = value;
    }
  }

  static void applyRemoteShowPanasonicLogoOnPrint(bool value) {
    _showPanasonicLogoOnPrint = value;
    if (showPanasonicLogoOnPrintListenable.value != value) {
      showPanasonicLogoOnPrintListenable.value = value;
    }
  }

  /// Applies an optional public HTTPS manual URL from the remote config.
  static bool tryApplyRemoteManualUrl(String? value) {
    if (value == null) {
      _setManualUrl(null);
      return true;
    }
    final Uri? uri = Uri.tryParse(value.trim());
    if (!isTrustedRemoteManualUrl(value) || uri == null) {
      return false;
    }
    _setManualUrl(uri.toString());
    return true;
  }

  static bool isTrustedRemoteManualUrl(String? value) {
    if (value == null) {
      return true;
    }
    final Uri? uri = Uri.tryParse(value.trim());
    return uri != null && _isSafeManualUri(uri);
  }

  static void applyRemoteAchievementRules(AchievementRules? value) {
    _achievementRules = value;
    achievementRulesListenable.value = value;
  }

  static bool _isTrustedApiUri(Uri uri) {
    final String host = uri.host.toLowerCase();
    const String trustedDomain = 'hitcon2026.online';
    final bool trustedHost =
        host == trustedDomain || host.endsWith('.$trustedDomain');
    final bool validPath = !uri.pathSegments.any(
      (String segment) => segment == '.' || segment == '..',
    );
    return uri.scheme == 'https' &&
        trustedHost &&
        uri.userInfo.isEmpty &&
        !uri.hasQuery &&
        !uri.hasFragment &&
        (!uri.hasPort || uri.port == 443) &&
        validPath;
  }

  static bool _isSafeManualUri(Uri uri) {
    final bool validPath = !uri.pathSegments.any(
      (String segment) => segment == '.' || segment == '..',
    );
    return uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        (!uri.hasPort || uri.port == 443) &&
        validPath;
  }

  static void _setManualUrl(String? value) {
    _manualUrl = value;
    if (manualUrlListenable.value != value) {
      manualUrlListenable.value = value;
    }
  }

  static String _normalizedPath(String path) {
    if (path == '/' || path.isEmpty) {
      return '';
    }
    return path.replaceFirst(RegExp(r'/+$'), '');
  }

  @visibleForTesting
  static void resetApiBaseUrlForTesting() {
    _apiBaseUrl = bundledApiBaseUrl;
    applyRemoteAllowUserTagUnlock(true);
    applyRemoteShowPanasonicLogo(true);
    applyRemoteShowPanasonicLogoOnPrint(true);
    tryApplyRemoteManualUrl(null);
    applyRemoteAchievementRules(null);
  }

  /// 是否在控制台輸出調試日誌
  static const bool enableDebugLogging = kDebugMode;
}
