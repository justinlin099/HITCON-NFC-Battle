import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import 'mock_api_service.dart';

/// 用戶角色枚舉
enum UserRole {
  admin,      // 管理者 - NFC 寫入工具
  user,       // 普通用戶 - 遊戲/集卡主介面
  eventStaff, // 活動管理人員 - 獎品發放
  unknown     // 未知
}

/// 認證服務 - 管理用戶登入狀態和權限
class AuthService {
  static final AuthService _instance = AuthService._internal();

  factory AuthService() {
    return _instance;
  }

  AuthService._internal();

  String? _currentUserId;
  UserRole _currentRole = UserRole.unknown;
  String? _jwtToken;
  Map<String, dynamic>? _userProfile;

  /// 用戶登入（支援 Mock 和真實 API）
  Future<bool> login(String userType) async {
    try {
      _log('🔐 Attempting login with userType: $userType');

      if (AppConfig.useMockServices) {
        // 測試模式：使用 Mock 服務
        await MockApiService.saveTestJwt(userType);

        final prefs = await SharedPreferences.getInstance();
        _jwtToken = prefs.getString('test_jwt_token');
        _currentUserId = prefs.getString('test_user_id');

        // 設定角色
        _setRoleFromString(userType.toUpperCase());

        // 從 Mock 服務獲取用戶資料
        if (_currentUserId != null) {
          final profileResult = await MockApiService.getUserProfile(_currentUserId!);
          if (profileResult['status'] == 'success') {
            _userProfile = profileResult['data'];
            _log('✅ Login successful - User: $_currentUserId, Role: $_currentRole');
            return true;
          }
        }
      } else {
        // 真實模式：調用後端 SSO
        _log('⚠️  Real API mode not yet implemented');
        // TODO: 實現真實 SSO 登入
        return false;
      }

      return false;
    } catch (e) {
      _log('❌ Login error: $e');
      return false;
    }
  }

  /// 登出
  Future<void> logout() async {
    try {
      _log('🚪 Logging out user: $_currentUserId');

      if (AppConfig.useMockServices) {
        await MockApiService.clearTestData();
      }

      _currentUserId = null;
      _jwtToken = null;
      _userProfile = null;
      _currentRole = UserRole.unknown;

      _log('✅ Logout successful');
    } catch (e) {
      _log('❌ Logout error: $e');
    }
  }

  /// 獲取用戶個人資料
  Future<Map<String, dynamic>?> fetchUserProfile() async {
    if (_currentUserId == null) {
      _log('⚠️  No user logged in');
      return null;
    }

    try {
      if (AppConfig.useMockServices) {
        final result = await MockApiService.getUserProfile(_currentUserId!);
        if (result['status'] == 'success') {
          _userProfile = result['data'];
          _log('📋 User profile fetched: ${_userProfile?['display_name']}');
          return _userProfile;
        }
      } else {
        // TODO: 呼叫真實 API
      }
    } catch (e) {
      _log('❌ Error fetching user profile: $e');
    }

    return null;
  }

  /// 更新用戶資料
  Future<bool> updateUserProfile(Map<String, dynamic> updates) async {
    if (_currentUserId == null) {
      _log('⚠️  No user logged in');
      return false;
    }

    try {
      if (AppConfig.useMockServices) {
        final result = await MockApiService.updateUserProfile(_currentUserId!, updates);
        if (result['status'] == 'success') {
          // 重新獲取更新後的資料
          await fetchUserProfile();
          _log('✅ User profile updated');
          return true;
        }
      } else {
        // TODO: 呼叫真實 API
      }
    } catch (e) {
      _log('❌ Error updating user profile: $e');
    }

    return false;
  }

  /// 綁定 NFC 標籤
  Future<bool> pairNfcTag(String uid) async {
    if (_currentUserId == null) {
      _log('⚠️  No user logged in');
      return false;
    }

    try {
      if (AppConfig.useMockServices) {
        final result = await MockApiService.pairTag(_currentUserId!, uid);
        if (result['status'] == 'success') {
          _log('✅ NFC tag paired successfully: $uid');
          return true;
        } else {
          _log('⚠️  NFC tag pairing failed: ${result['message']}');
          return false;
        }
      } else {
        // TODO: 呼叫真實 API
      }
    } catch (e) {
      _log('❌ Error pairing NFC tag: $e');
    }

    return false;
  }

  /// 獲取集卡記錄
  Future<Map<String, dynamic>?> fetchCollectionRecords() async {
    if (_currentUserId == null) {
      _log('⚠️  No user logged in');
      return null;
    }

    try {
      if (AppConfig.useMockServices) {
        final result = await MockApiService.getCollectionRecords(_currentUserId!);
        if (result['status'] == 'success') {
          _log('📚 Collection records fetched: ${result['data']['total_collected']} cards');
          return result['data'];
        }
      } else {
        // TODO: 呼叫真實 API
      }
    } catch (e) {
      _log('❌ Error fetching collection records: $e');
    }

    return null;
  }

  /// 獲取他人的集卡記錄
  Future<Map<String, dynamic>?> fetchUserCollection(String targetUserId) async {
    try {
      if (AppConfig.useMockServices) {
        final result = await MockApiService.getUserCollection(targetUserId);
        if (result['status'] == 'success') {
          _log('👤 Fetched collection for user: $targetUserId');
          return result['data'];
        }
      } else {
        // TODO: 呼叫真實 API
      }
    } catch (e) {
      _log('❌ Error fetching user collection: $e');
    }

    return null;
  }

  /// 內部：根據字符串設定角色
  void _setRoleFromString(String roleStr) {
    switch (roleStr) {
      case 'ADMIN':
        _currentRole = UserRole.admin;
        break;
      case 'EVENT_STAFF':
        _currentRole = UserRole.eventStaff;
        break;
      case 'USER':
      default:
        _currentRole = UserRole.user;
        break;
    }
  }

  /// 內部日誌輸出
  void _log(String message) {
    if (AppConfig.enableDebugLogging) {
      debugPrint('[AuthService] $message');
    }
  }

  // ========== Getters ==========

  String? get currentUserId => _currentUserId;
  UserRole get currentRole => _currentRole;
  String? get jwtToken => _jwtToken;
  Map<String, dynamic>? get userProfile => _userProfile;
  bool get isLoggedIn => _jwtToken != null && _currentUserId != null;
  bool get isAdmin => _currentRole == UserRole.admin;
  bool get isEventStaff => _currentRole == UserRole.eventStaff;
  bool get isRegularUser => _currentRole == UserRole.user;
}
