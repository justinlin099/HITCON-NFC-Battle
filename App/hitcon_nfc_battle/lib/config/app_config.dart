import 'package:flutter/foundation.dart';

/// 應用程式設定
class AppConfig {
  /// 後端 API 基礎 URL
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://nfc-battle-staging.hitcon2026.online',
  );

  /// 是否在控制台輸出調試日誌
  static const bool enableDebugLogging = kDebugMode;
}
