/// 應用程式設定
class AppConfig {
  /// 是否使用 Mock 服務（測試模式）
  /// true: 使用本地 Mock 服務，無需後端
  /// false: 使用真實後端 API
  static const bool useMockServices = true;

  /// 後端 API 基礎 URL
  static const String apiBaseUrl = 'https://game.hitcon2026.online/v1';

  /// 模擬網路延遲（毫秒）
  static const int mockNetworkDelay = 500;

  /// 是否在控制台輸出調試日誌
  static const bool enableDebugLogging = true;

  /// 當前是否為調試模式
  static bool get isDebugMode {
    return useMockServices;
  }
}
