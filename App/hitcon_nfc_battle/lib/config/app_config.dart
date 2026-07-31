import 'package:flutter/foundation.dart';

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
  static final ValueNotifier<bool> allowUserTagUnlockListenable =
      ValueNotifier<bool>(true);

  /// 當前 API 基礎 URL，可在啟動時由受信任的遠端設定更新。
  static String get apiBaseUrl => _apiBaseUrl;

  /// 是否允許一般使用者解除自己 Tag 的寫入保護。
  static bool get allowUserTagUnlock => _allowUserTagUnlock;

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
  }

  /// 是否在控制台輸出調試日誌
  static const bool enableDebugLogging = kDebugMode;
}
