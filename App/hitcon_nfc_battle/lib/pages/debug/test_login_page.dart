import 'package:flutter/material.dart';
import '../../config/app_config.dart';
import '../../services/auth_service.dart';
import '../../services/mock_api_service.dart';

/// 測試登入頁面 - 用於快速切換不同角色進行測試
class TestLoginPage extends StatefulWidget {
  const TestLoginPage({super.key});

  @override
  State<TestLoginPage> createState() => _TestLoginPageState();
}

class _TestLoginPageState extends State<TestLoginPage> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🧪 角色測試面板'),
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 測試模式警告
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  border: Border.all(color: Colors.amber.shade700),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.amber.shade700,
                      size: 32,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '🔴 測試模式已啟用',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: Colors.amber.shade900,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '使用 Mock 服務進行開發測試\n無需後端 API',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.amber.shade800,
                          ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),

              // 角色選擇標題
              Text(
                '選擇角色進行測試',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),

              const SizedBox(height: 8),
              Text(
                '各角色有不同的功能和權限',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                    ),
              ),

              const SizedBox(height: 40),

              // 管理者按鈕
              _buildRoleButton(
                context,
                userType: 'ADMIN',
                label: '🔧 管理者',
                description: 'NFC 卡片寫入工具',
                color: Colors.blue,
              ),

              const SizedBox(height: 16),

              // 玩家按鈕
              _buildRoleButton(
                context,
                userType: 'USER',
                label: '🎮 玩家',
                description: '遊戲和集卡介面',
                color: Colors.green,
              ),

              const SizedBox(height: 16),

              // 活動管理員按鈕
              _buildRoleButton(
                context,
                userType: 'EVENT_STAFF',
                label: '🎯 活動管理員',
                description: '獎品發放管理',
                color: Colors.purple,
              ),

              const SizedBox(height: 48),

              // 底部信息
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Text(
                      '📌 Mock 服務信息',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 12),
                    _buildInfoRow('模式', 'Mock（本地測試）'),
                    const SizedBox(height: 8),
                    _buildInfoRow('網路延遲', '${AppConfig.mockNetworkDelay}ms'),
                    const SizedBox(height: 8),
                    _buildInfoRow(
                      '調試日誌',
                      AppConfig.enableDebugLogging ? '已啟用' : '已禁用',
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // 重置數據按鈕
              ElevatedButton.icon(
                onPressed: _resetMockData,
                icon: const Icon(Icons.refresh),
                label: const Text('重置 Mock 數據'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey.shade600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 建立角色選擇按鈕
  Widget _buildRoleButton(
    BuildContext context, {
    required String userType,
    required String label,
    required String description,
    required Color color,
  }) {
    return ElevatedButton(
      onPressed: _isLoading ? null : () => _handleLogin(userType),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 建立信息行
  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
      ],
    );
  }

  /// 登入處理
  Future<void> _handleLogin(String userType) async {
    setState(() => _isLoading = true);

    try {
      final authService = AuthService();
      final success = await authService.login(userType);

      if (mounted) {
        if (success) {
          final AuthService authService = AuthService();
          final String routeName = authService.isRegularUser ? '/collection' : '/home';
          Navigator.of(context).pushReplacementNamed(routeName);
        } else {
          // 登入失敗
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('登入失敗，請重試'),
              backgroundColor: Colors.red.shade600,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('錯誤: $e'),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// 重置 Mock 數據
  void _resetMockData() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重置 Mock 數據'),
        content: const Text('確定要重置所有 Mock 數據到初始狀態嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              MockApiService.resetMockData();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('✅ Mock 數據已重置'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            child: const Text('確定'),
          ),
        ],
      ),
    );
  }
}
