/// 應用程式設定
class AppConfig {
  /// 是否使用 Mock 服務（測試模式）
  /// true: 使用本地 Mock 服務，無需後端
  /// false: 使用真實後端 API
  static const bool useMockServices = bool.fromEnvironment(
    'USE_MOCK_SERVICES',
    defaultValue: false,
  );

  /// 後端 API 基礎 URL
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://nfc-battle-staging.hitcon2026.online',
  );

  static const String jwtSecret = String.fromEnvironment('JWT_SECRET');

  static const String staffDangerToken = String.fromEnvironment(
    'STAFF_DANGER_TOKEN',
  );

  static const String jwtIssuer = String.fromEnvironment(
    'JWT_ISSUER',
    defaultValue: 'hitcon-2026-staging',
  );

  static const String jwtAudience = String.fromEnvironment(
    'JWT_AUDIENCE',
    defaultValue: 'nfc-battle-api-server-staging',
  );

  /// 模擬網路延遲（毫秒）
  static const int mockNetworkDelay = 500;

  /// 是否在控制台輸出調試日誌
  static const bool enableDebugLogging = true;

  /// 當前是否為調試模式
  static bool get isDebugMode {
    return useMockServices;
  }
}
