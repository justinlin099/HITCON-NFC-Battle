import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';

/// Mock API 服務 - 用於前端開發階段測試
/// 模擬後端 API 的回應，無需實際的後端服務
class MockApiService {
  /// 測試用 JWT Token
  static const String _testJwt =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ0ZXN0X3VzZXJfMTIzIiwiaWF0IjoxNjA0NDkwNzk3fQ.test';

  /// 模擬用戶數據庫
  static final Map<String, dynamic> _mockUsers = {
    'test_user_123': {
      'user_id': 'test_user_123',
      'display_name': 'Admin_Test',
      'user_type': 'ADMIN',
      'emoji_icon': '🔧',
      'bio': 'Test Admin Account',
      'pixel_avatar_base64': 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
      'stats': {'score': 1000, 'cards_collected': 50}
    },
    'test_user_456': {
      'user_id': 'test_user_456',
      'display_name': 'Player_Test',
      'user_type': 'USER',
      'emoji_icon': '🎮',
      'bio': 'Test Player Account',
      'pixel_avatar_base64': 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
      'stats': {'score': 250, 'cards_collected': 15}
    },
    'test_user_789': {
      'user_id': 'test_user_789',
      'display_name': 'Staff_Test',
      'user_type': 'EVENT_STAFF',
      'emoji_icon': '🎯',
      'bio': 'Test Staff Account',
      'pixel_avatar_base64': 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
      'stats': {'score': 100, 'cards_collected': 5}
    },
  };

  /// 模擬 NFC 標籤數據庫
  static final List<Map<String, dynamic>> _mockTags = [
    {
      'uid': '04:1A:2B:3C:4D:5E:6F',
      'owner': 'test_user_456',
      'name': 'Card_001',
      'collected_at': '2026-04-20T10:30:00Z'
    },
    {
      'uid': '04:2B:3C:4D:5E:6F:7G',
      'owner': 'test_user_456',
      'name': 'Card_002',
      'collected_at': '2026-04-21T14:15:00Z'
    },
    {
      'uid': '04:3C:4D:5E:6F:7G:8H',
      'owner': 'test_user_456',
      'name': 'Card_003',
      'collected_at': '2026-04-22T09:45:00Z'
    },
    {
      'uid': '04:4D:5E:6F:7G:8H:9I',
      'owner': 'test_user_456',
      'name': 'Card_004',
      'collected_at': '2026-04-22T10:10:00Z'
    },
    {
      'uid': '04:5E:6F:7G:8H:9I:0J',
      'owner': 'test_user_456',
      'name': 'Card_005',
      'collected_at': '2026-04-22T11:05:00Z'
    },
    {
      'uid': '04:6F:7G:8H:9I:0J:1K',
      'owner': 'test_user_456',
      'name': 'Card_006',
      'collected_at': '2026-04-22T12:30:00Z'
    },
    {
      'uid': '04:7G:8H:9I:0J:1K:2L',
      'owner': 'test_user_456',
      'name': 'Card_007',
      'collected_at': '2026-04-22T13:45:00Z'
    },
    {
      'uid': '04:8H:9I:0J:1K:2L:3M',
      'owner': 'test_user_456',
      'name': 'Card_008',
      'collected_at': '2026-04-22T15:20:00Z'
    },
    {
      'uid': '04:9I:0J:1K:2L:3M:4N',
      'owner': 'test_user_456',
      'name': 'Card_009',
      'collected_at': '2026-04-22T16:50:00Z'
    },
  ];

  /// 釘選的贊助商與社群攤位
  static const List<Map<String, String>> featuredBooths = <Map<String, String>>[
    {
      'name': 'HITCON 贊助商 A',
      'tag': 'SPONSOR',
      'icon': '★',
      'accent': 'amber',
    },
    {
      'name': '社群攤位 / DEFCON',
      'tag': 'COMMUNITY',
      'icon': '☍',
      'accent': 'cyan',
    },
    {
      'name': '硬體實驗室',
      'tag': 'LAB',
      'icon': '✦',
      'accent': 'green',
    },
    {
      'name': 'CTF 攤位',
      'tag': 'GAME',
      'icon': '⬢',
      'accent': 'pink',
    },
  ];

  /// 獲取用戶個人資料
  static Future<Map<String, dynamic>> getUserProfile(String userId) async {
    _log('📋 Mock: GET /users/me for userId: $userId');
    
    await Future.delayed(Duration(milliseconds: AppConfig.mockNetworkDelay));

    if (_mockUsers.containsKey(userId)) {
      return {
        'status': 'success',
        'data': _mockUsers[userId]
      };
    }

    return {
      'status': 'error',
      'code': 'USER_NOT_FOUND',
      'message': 'User not found'
    };
  }

  /// 更新用戶資料
  static Future<Map<String, dynamic>> updateUserProfile(
    String userId,
    Map<String, dynamic> updates,
  ) async {
    _log('📋 Mock: PATCH /users/me with updates: $updates');
    
    await Future.delayed(Duration(milliseconds: AppConfig.mockNetworkDelay));

    if (_mockUsers.containsKey(userId)) {
      _mockUsers[userId]!.addAll(updates);
      return {
        'status': 'success',
        'message': 'Profile updated'
      };
    }

    return {
      'status': 'error',
      'code': 'USER_NOT_FOUND',
      'message': 'User not found'
    };
  }

  /// 綁定 NFC 標籤（現場報到）
  static Future<Map<String, dynamic>> pairTag(
    String userId,
    String uid,
  ) async {
    _log('🏷️  Mock: POST /tags/pair for uid: $uid');
    
    await Future.delayed(Duration(milliseconds: AppConfig.mockNetworkDelay + 300));

    // 檢查標籤是否已被使用
    final existingTagIndex = _mockTags.indexWhere((tag) => tag['uid'] == uid);

    if (existingTagIndex != -1 && _mockTags[existingTagIndex]['owner'] != null) {
      return {
        'status': 'error',
        'code': 'TAG_ALREADY_IN_USE',
        'message': 'This NFC tag is already bound to another user.'
      };
    }

    // 新增或更新標籤
    if (existingTagIndex != -1) {
      _mockTags[existingTagIndex]['owner'] = userId;
      _mockTags[existingTagIndex]['collected_at'] = DateTime.now().toIso8601String();
    } else {
      _mockTags.add({
        'uid': uid,
        'owner': userId,
        'name': 'Card_${_mockTags.length + 1}',
        'collected_at': DateTime.now().toIso8601String()
      });
    }

    return {
      'status': 'success',
      'message': 'Tag paired successfully'
    };
  }

  /// 獲取集卡記錄
  static Future<Map<String, dynamic>> getCollectionRecords(String userId) async {
    _log('📚 Mock: GET /users/$userId/collection');
    
    await Future.delayed(Duration(milliseconds: AppConfig.mockNetworkDelay + 100));

    final userRecords = _mockTags
        .where((tag) => tag['owner'] == userId)
        .map((tag) => {
          'user_id': tag['owner'],
          'display_name': _mockUsers[tag['owner']]?['display_name'] ?? 'Unknown',
          'emoji_icon': _mockUsers[tag['owner']]?['emoji_icon'] ?? '❓',
          'collected_at': tag['collected_at'] ?? DateTime.now().toIso8601String(),
          'tag_name': tag['name'],
          'physical_uid': tag['uid'],
        })
        .toList();

    return {
      'status': 'success',
      'data': {
        'owner_display_name': _mockUsers[userId]?['display_name'] ?? 'Unknown',
        'total_collected': userRecords.length,
        'collection': userRecords
      }
    };
  }

  /// 其他用戶的集卡記錄（查看他人集卡）
  static Future<Map<String, dynamic>> getUserCollection(String targetUserId) async {
    _log('👤 Mock: GET /users/$targetUserId/collection (view other\'s collection)');
    
    await Future.delayed(Duration(milliseconds: AppConfig.mockNetworkDelay + 150));

    if (!_mockUsers.containsKey(targetUserId)) {
      return {
        'status': 'error',
        'code': 'USER_NOT_FOUND',
        'message': 'User not found'
      };
    }

    final userRecords = _mockTags
        .where((tag) => tag['owner'] == targetUserId)
        .toList();

    return {
      'status': 'success',
      'data': {
        'owner_display_name': _mockUsers[targetUserId]?['display_name'] ?? 'Unknown',
        'total_collected': userRecords.length,
        'collection': userRecords
      }
    };
  }

  /// 保存測試 JWT（模擬登入）
  static Future<void> saveTestJwt(String userType) async {
    _log('🔐 Mock: Saving test JWT for userType: $userType');
    
    final prefs = await SharedPreferences.getInstance();

    // 根據角色選擇對應的測試用戶
    String testUserId;
    switch (userType.toUpperCase()) {
      case 'ADMIN':
        testUserId = 'test_user_123';
        break;
      case 'EVENT_STAFF':
        testUserId = 'test_user_789';
        break;
      default:
        testUserId = 'test_user_456';
    }

    await prefs.setString('test_jwt_token', _testJwt);
    await prefs.setString('test_user_id', testUserId);
    
    _log('✅ Test JWT saved for userId: $testUserId');
  }

  /// 清除測試數據
  static Future<void> clearTestData() async {
    _log('🗑️  Mock: Clearing test data');
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('test_jwt_token');
    await prefs.remove('test_user_id');
    
    _log('✅ Test data cleared');
  }

  /// 內部日誌輸出
  static void _log(String message) {
    if (AppConfig.enableDebugLogging) {
      debugPrint('[MockAPI] $message');
    }
  }

  /// 重置 Mock 數據（用於測試）
  static void resetMockData() {
    _log('🔄 Mock: Resetting all mock data to initial state');
    _mockTags.clear();
    _mockTags.addAll([
      {
        'uid': '04:1A:2B:3C:4D:5E:6F',
        'owner': 'test_user_456',
        'name': 'Card_001',
        'collected_at': '2026-04-20T10:30:00Z'
      },
      {
        'uid': '04:2B:3C:4D:5E:6F:7G',
        'owner': 'test_user_456',
        'name': 'Card_002',
        'collected_at': '2026-04-21T14:15:00Z'
      },
      {
        'uid': '04:3C:4D:5E:6F:7G:8H',
        'owner': 'test_user_456',
        'name': 'Card_003',
        'collected_at': '2026-04-22T09:45:00Z'
      },
      {
        'uid': '04:4D:5E:6F:7G:8H:9I',
        'owner': 'test_user_456',
        'name': 'Card_004',
        'collected_at': '2026-04-22T10:10:00Z'
      },
      {
        'uid': '04:5E:6F:7G:8H:9I:0J',
        'owner': 'test_user_456',
        'name': 'Card_005',
        'collected_at': '2026-04-22T11:05:00Z'
      },
      {
        'uid': '04:6F:7G:8H:9I:0J:1K',
        'owner': 'test_user_456',
        'name': 'Card_006',
        'collected_at': '2026-04-22T12:30:00Z'
      },
      {
        'uid': '04:7G:8H:9I:0J:1K:2L',
        'owner': 'test_user_456',
        'name': 'Card_007',
        'collected_at': '2026-04-22T13:45:00Z'
      },
      {
        'uid': '04:8H:9I:0J:1K:2L:3M',
        'owner': 'test_user_456',
        'name': 'Card_008',
        'collected_at': '2026-04-22T15:20:00Z'
      },
      {
        'uid': '04:9I:0J:1K:2L:3M:4N',
        'owner': 'test_user_456',
        'name': 'Card_009',
        'collected_at': '2026-04-22T16:50:00Z'
      },
    ]);
  }

  /// 取得釘選的贊助商與社群攤位
  static Future<List<Map<String, String>>> getFeaturedBooths() async {
    _log('📌 Mock: GET /featured/booths');
    await Future.delayed(Duration(milliseconds: AppConfig.mockNetworkDelay));
    return featuredBooths;
  }
}
