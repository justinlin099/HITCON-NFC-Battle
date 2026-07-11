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
      'pixel_avatar_base64':
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
      'stats': {'score': 1000, 'cards_collected': 50},
    },
    'test_user_456': {
      'user_id': 'test_user_456',
      'display_name': 'Player_Test',
      'user_type': 'USER',
      'emoji_icon': '🎮',
      'bio': 'Test Player Account',
      'pixel_avatar_base64':
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
      'stats': {'score': 250, 'cards_collected': 15},
    },
    'test_user_789': {
      'user_id': 'test_user_789',
      'display_name': 'Staff_Test',
      'user_type': 'EVENT_STAFF',
      'emoji_icon': '🎯',
      'bio': 'Test Staff Account',
      'pixel_avatar_base64':
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
      'stats': {'score': 100, 'cards_collected': 5},
    },
  };

  /// 模擬 NFC 標籤數據庫
  static final List<Map<String, dynamic>> _mockTags = _buildMockTags();
  static final Map<String, Map<String, dynamic>> _mockPrizeClaims =
      <String, Map<String, dynamic>>{};

  static List<Map<String, dynamic>> _buildMockTags() {
    const List<Map<String, String>> baseCards = <Map<String, String>>[
      {
        'card_title': 'Neon Dolphin',
        'image_file': 'dolphin_01.png',
        'attribute_emoji': '💧',
        'attribute_label': 'WATER',
      },
      {
        'card_title': 'Pixel Fox',
        'image_file': 'fox_02.png',
        'attribute_emoji': '🔥',
        'attribute_label': 'FIRE',
      },
      {
        'card_title': 'Circuit Owl',
        'image_file': 'owl_03.png',
        'attribute_emoji': '💨',
        'attribute_label': 'WIND',
      },
      {
        'card_title': 'Byte Panda',
        'image_file': 'panda_04.png',
        'attribute_emoji': '🌱',
        'attribute_label': 'EARTH',
      },
      {
        'card_title': 'Glitch Tiger',
        'image_file': 'tiger_05.png',
        'attribute_emoji': '✨',
        'attribute_label': 'LIGHT',
      },
      {
        'card_title': 'Turbo Bee',
        'image_file': 'bee_06.png',
        'attribute_emoji': '⚡',
        'attribute_label': 'ELECTRIC',
      },
      {
        'card_title': 'Star Koala',
        'image_file': 'koala_07.png',
        'attribute_emoji': '🌟',
        'attribute_label': 'STAR',
      },
      {
        'card_title': 'Neon Rabbit',
        'image_file': 'rabbit_08.png',
        'attribute_emoji': '💫',
        'attribute_label': 'SPEED',
      },
      {
        'card_title': 'Pixel Dragon',
        'image_file': 'dragon_09.png',
        'attribute_emoji': '🐉',
        'attribute_label': 'DRAGON',
      },
    ];

    final List<Map<String, dynamic>> tags = <Map<String, dynamic>>[];
    final DateTime start = DateTime(2026, 4, 20, 10, 30);

    String hexByte(int value) =>
        value.toRadixString(16).padLeft(2, '0').toUpperCase();

    for (int i = 0; i < 100; i++) {
      final int index = i + 1;
      final Map<String, String> base = baseCards[i % baseCards.length];
      final List<Map<String, String>> attributes = _pickMockAttributes(
        baseCards,
        i,
      );
      final int a = (index * 37) % 256;
      final int b = (index * 59) % 256;
      final int c = (index * 83) % 256;
      final int d = (index * 97) % 256;
      final int e = (index * 13) % 256;
      final int f = (index * 7) % 256;

      tags.add({
        'uid':
            '04:${hexByte(a)}:${hexByte(b)}:${hexByte(c)}:${hexByte(d)}:${hexByte(e)}:${hexByte(f)}',
        'owner': 'test_user_456',
        'name': 'Card_${index.toString().padLeft(3, '0')}',
        'card_title':
            '${base['card_title']} ${index.toString().padLeft(2, '0')}',
        'image_file': base['image_file'],
        'attribute_emoji': attributes
            .map((item) => item['attribute_emoji'] ?? '')
            .join(),
        'attribute_label': attributes
            .map((item) => item['attribute_label'] ?? '')
            .join(' / '),
        'link': 'https://hitcon.org',
        'collected_at': start.add(Duration(hours: i * 3)).toIso8601String(),
      });
    }

    return tags;
  }

  static List<Map<String, String>> _pickMockAttributes(
    List<Map<String, String>> baseCards,
    int seed,
  ) {
    return List<Map<String, String>>.generate(3, (int offset) {
      final int index = (seed * 7 + offset * 3) % baseCards.length;
      return baseCards[index];
    }, growable: false);
  }

  /// 釘選的贊助商與社群攤位
  static const List<Map<String, String>> featuredBooths = <Map<String, String>>[
    {'name': 'HITCON 贊助商 A', 'tag': 'SPONSOR', 'icon': '★', 'accent': 'amber'},
    {
      'name': '社群攤位 / DEFCON',
      'tag': 'COMMUNITY',
      'icon': '☍',
      'accent': 'cyan',
    },
    {'name': '硬體實驗室', 'tag': 'LAB', 'icon': '✦', 'accent': 'green'},
    {'name': 'CTF 攤位', 'tag': 'GAME', 'icon': '⬢', 'accent': 'pink'},
  ];

  /// 獲取用戶個人資料
  static Future<Map<String, dynamic>> getUserProfile(String userId) async {
    _log('📋 Mock: GET /users/me for userId: $userId');

    await Future.delayed(Duration(milliseconds: AppConfig.mockNetworkDelay));

    if (_mockUsers.containsKey(userId)) {
      return {
        'status': 'success',
        'data': Map<String, dynamic>.from(_mockUsers[userId] as Map),
      };
    }

    return {
      'status': 'error',
      'code': 'USER_NOT_FOUND',
      'message': 'User not found',
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
      final Map<String, dynamic> user = Map<String, dynamic>.from(
        _mockUsers[userId] as Map,
      );
      user.addAll(updates);
      _mockUsers[userId] = user;
      return {'status': 'success', 'message': 'Profile updated'};
    }

    return {
      'status': 'error',
      'code': 'USER_NOT_FOUND',
      'message': 'User not found',
    };
  }

  /// 綁定 NFC 標籤（現場報到）
  static Future<Map<String, dynamic>> pairTag(String userId, String uid) async {
    _log('🏷️  Mock: POST /tags/pair for uid: $uid');

    await Future.delayed(
      Duration(milliseconds: AppConfig.mockNetworkDelay + 300),
    );

    // 檢查標籤是否已被使用
    final existingTagIndex = _mockTags.indexWhere((tag) => tag['uid'] == uid);

    if (existingTagIndex != -1 &&
        _mockTags[existingTagIndex]['owner'] != null) {
      return {
        'status': 'error',
        'code': 'TAG_ALREADY_IN_USE',
        'message': 'This NFC tag is already bound to another user.',
      };
    }

    // 新增或更新標籤
    if (existingTagIndex != -1) {
      _mockTags[existingTagIndex]['owner'] = userId;
      _mockTags[existingTagIndex]['collected_at'] = DateTime.now()
          .toIso8601String();
    } else {
      _mockTags.add({
        'uid': uid,
        'owner': userId,
        'name': 'Card_${_mockTags.length + 1}',
        'collected_at': DateTime.now().toIso8601String(),
      });
    }

    return {'status': 'success', 'message': 'Tag paired successfully'};
  }

  static Future<Map<String, dynamic>> getNtagLockSecret({
    required String uid,
    required String purpose,
    required String requesterUserId,
  }) async {
    _log(
      'Mock: POST /ntag/lock-secret uid=$uid purpose=$purpose requester=$requesterUserId',
    );
    await Future.delayed(
      Duration(milliseconds: AppConfig.mockNetworkDelay + 120),
    );

    final String normalizedUid = uid
        .replaceAll(RegExp(r'[^0-9a-fA-F]'), '')
        .toUpperCase();
    if (normalizedUid.isEmpty) {
      return {
        'status': 'error',
        'code': 'EMPTY_UID',
        'message': 'Tag UID is required.',
      };
    }

    final int passwordSeed = _fnv1a32(
      'HITCON_NFC_BATTLE_2026:$normalizedUid:PWD',
    );
    final int packSeed = _fnv1a32('HITCON_NFC_BATTLE_2026:$normalizedUid:PACK');

    return {
      'status': 'success',
      'data': {
        'password': <int>[
          passwordSeed & 0xFF,
          (passwordSeed >> 8) & 0xFF,
          (passwordSeed >> 16) & 0xFF,
          (passwordSeed >> 24) & 0xFF,
        ],
        'pack': <int>[packSeed & 0xFF, (packSeed >> 8) & 0xFF],
      },
    };
  }

  static Future<Map<String, dynamic>> scanCollection({
    required String currentUserId,
    required String targetUserId,
    required String scannedNfcUid,
  }) async {
    _log(
      'Mock: POST /collections/scan current=$currentUserId target=$targetUserId uid=$scannedNfcUid',
    );

    await Future.delayed(
      Duration(milliseconds: AppConfig.mockNetworkDelay + 250),
    );

    final int tagIndex = _mockTags.indexWhere(
      (Map<String, dynamic> tag) => tag['uid'] == scannedNfcUid,
    );
    if (tagIndex == -1) {
      return {
        'status': 'error',
        'code': 'UID_NOT_FOUND',
        'message': 'User or physical tag does not exist.',
      };
    }

    final Map<String, dynamic> tag = _mockTags[tagIndex];
    final String ownerId = tag['owner'] as String? ?? '';
    if (targetUserId.trim().isNotEmpty && ownerId != targetUserId.trim()) {
      return {
        'status': 'error',
        'code': 'SECURITY_VERIFICATION_FAILED',
        'message': 'UID mismatch or insufficient permissions.',
      };
    }

    final String collectedAt = DateTime.now().toIso8601String();
    tag['collected_at'] = collectedAt;
    tag['collected_by'] = currentUserId;

    final Map<String, dynamic> owner =
        _mockUsers[ownerId] ?? <String, dynamic>{};
    return {
      'status': 'success',
      'type': tag['type'] ?? 'ATTENDEE',
      'data': {
        'target_info': {
          'user_id': ownerId,
          'display_name':
              owner['display_name'] ?? tag['card_title'] ?? 'Unknown',
          'user_type': owner['user_type'] ?? 'USER',
          'emoji_icon': owner['emoji_icon'] ?? tag['attribute_emoji'] ?? '',
          'total_tags':
              owner['stats']?['tags_collected'] ??
              owner['stats']?['cards_collected'] ??
              0,
          'tag_name': tag['name'],
          'card_title': tag['card_title'],
          'attribute_emoji': tag['attribute_emoji'],
          'attribute_label': tag['attribute_label'],
          'image_file': tag['image_file'],
          'link': tag['link'],
          'collected_at': collectedAt,
        },
        'ciphertext': 'MOCK-CIPHERTEXT-${scannedNfcUid.replaceAll(':', '')}',
        'pixel_avatar_base64': owner['pixel_avatar_base64'],
      },
    };
  }

  /// 獲取集卡記錄
  static Future<Map<String, dynamic>> getCollectionRecords(
    String userId,
  ) async {
    _log('📚 Mock: GET /users/$userId/collection');

    await Future.delayed(
      Duration(milliseconds: AppConfig.mockNetworkDelay + 100),
    );

    final userRecords = _mockTags
        .where((tag) => tag['owner'] == userId)
        .map(
          (tag) => {
            'user_id': tag['owner'],
            'display_name':
                _mockUsers[tag['owner']]?['display_name'] ?? 'Unknown',
            'emoji_icon': _mockUsers[tag['owner']]?['emoji_icon'] ?? '❓',
            'collected_at':
                tag['collected_at'] ?? DateTime.now().toIso8601String(),
            'tag_name': tag['name'],
            'card_title': tag['card_title'],
            'image_file': tag['image_file'],
            'attribute_emoji': tag['attribute_emoji'],
            'attribute_label': tag['attribute_label'],
            'physical_uid': tag['uid'],
          },
        )
        .toList();

    return {
      'status': 'success',
      'data': {
        'owner_display_name': _mockUsers[userId]?['display_name'] ?? 'Unknown',
        'total_collected': userRecords.length,
        'collection': userRecords,
      },
    };
  }

  /// 其他用戶的集卡記錄（查看他人集卡）
  static Future<Map<String, dynamic>> getUserCollection(
    String targetUserId,
  ) async {
    _log(
      '👤 Mock: GET /users/$targetUserId/collection (view other\'s collection)',
    );

    await Future.delayed(
      Duration(milliseconds: AppConfig.mockNetworkDelay + 150),
    );

    if (!_mockUsers.containsKey(targetUserId)) {
      return {
        'status': 'error',
        'code': 'USER_NOT_FOUND',
        'message': 'User not found',
      };
    }

    final userRecords = _mockTags
        .where((tag) => tag['owner'] == targetUserId)
        .toList();

    return {
      'status': 'success',
      'data': {
        'owner_display_name':
            _mockUsers[targetUserId]?['display_name'] ?? 'Unknown',
        'total_collected': userRecords.length,
        'collection': userRecords,
      },
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
    _mockPrizeClaims.clear();
    _mockTags.addAll([
      {
        'uid': '04:1A:2B:3C:4D:5E:6F',
        'owner': 'test_user_456',
        'name': 'Card_001',
        'link': 'https://hitcon.org',
        'collected_at': '2026-04-20T10:30:00Z',
      },
      {
        'uid': '04:2B:3C:4D:5E:6F:7G',
        'owner': 'test_user_456',
        'name': 'Card_002',
        'link': 'https://hitcon.org',
        'collected_at': '2026-04-21T14:15:00Z',
      },
      {
        'uid': '04:3C:4D:5E:6F:7G:8H',
        'owner': 'test_user_456',
        'name': 'Card_003',
        'link': 'https://hitcon.org',
        'collected_at': '2026-04-22T09:45:00Z',
      },
      {
        'uid': '04:4D:5E:6F:7G:8H:9I',
        'owner': 'test_user_456',
        'name': 'Card_004',
        'link': 'https://hitcon.org',
        'collected_at': '2026-04-22T10:10:00Z',
      },
      {
        'uid': '04:5E:6F:7G:8H:9I:0J',
        'owner': 'test_user_456',
        'name': 'Card_005',
        'link': 'https://hitcon.org',
        'collected_at': '2026-04-22T11:05:00Z',
      },
      {
        'uid': '04:6F:7G:8H:9I:0J:1K',
        'owner': 'test_user_456',
        'name': 'Card_006',
        'link': 'https://hitcon.org',
        'collected_at': '2026-04-22T12:30:00Z',
      },
      {
        'uid': '04:7G:8H:9I:0J:1K:2L',
        'owner': 'test_user_456',
        'name': 'Card_007',
        'link': 'https://hitcon.org',
        'collected_at': '2026-04-22T13:45:00Z',
      },
      {
        'uid': '04:8H:9I:0J:1K:2L:3M',
        'owner': 'test_user_456',
        'name': 'Card_008',
        'link': 'https://hitcon.org',
        'collected_at': '2026-04-22T15:20:00Z',
      },
      {
        'uid': '04:9I:0J:1K:2L:3M:4N',
        'owner': 'test_user_456',
        'name': 'Card_009',
        'link': 'https://hitcon.org',
        'collected_at': '2026-04-22T16:50:00Z',
      },
    ]);
  }

  /// 取得釘選的贊助商與社群攤位
  static Future<List<Map<String, String>>> getFeaturedBooths() async {
    _log('📌 Mock: GET /featured/booths');
    await Future.delayed(Duration(milliseconds: AppConfig.mockNetworkDelay));
    return featuredBooths;
  }

  static Future<Map<String, dynamic>> submitCardPrintOrder({
    required String userId,
    required Uint8List artworkPng,
    required Map<String, dynamic> metadata,
  }) async {
    _log(
      '?? Mock: POST /card-print-orders user=$userId bytes=${artworkPng.length}',
    );
    await Future.delayed(
      Duration(milliseconds: AppConfig.mockNetworkDelay + 350),
    );

    final int now = DateTime.now().millisecondsSinceEpoch;
    final String serial = now.toRadixString(36).toUpperCase();
    final String orderId = 'HITCON26-$serial';

    return {
      'status': 'success',
      'data': {
        'order_id': orderId,
        'barcode_value': 'PRINT:$orderId',
        'file_name': 'card-print-$orderId.png',
        'format': metadata['format'] ?? 'EVOLIS_PRIMACY_CR80_300DPI_PNG',
        'width_px': metadata['width_px'],
        'height_px': metadata['height_px'],
        'dpi': metadata['dpi'],
        'card_size': metadata['card_size'],
        'printer': metadata['printer'],
        'bytes': artworkPng.length,
      },
    };
  }

  static Future<Map<String, dynamic>> confirmPrizeClaim({
    required String tagUid,
    required String userId,
    required String staffUserId,
  }) async {
    _log(
      'Mock: POST /admin/prize-claims tag=$tagUid user=$userId staff=$staffUserId',
    );
    await Future.delayed(
      Duration(milliseconds: AppConfig.mockNetworkDelay + 250),
    );

    final String claimKey = userId.trim().isNotEmpty ? userId.trim() : tagUid;
    if (claimKey.isEmpty) {
      return {
        'status': 'error',
        'code': 'EMPTY_TAG',
        'message': 'Tag UID or user_id is required.',
      };
    }

    final Map<String, dynamic>? existing = _mockPrizeClaims[claimKey];
    if (existing != null) {
      return {
        'status': 'success',
        'data': <String, dynamic>{...existing, 'already_claimed': true},
      };
    }

    final int now = DateTime.now().millisecondsSinceEpoch;
    final String claimCode = 'PRIZE-${now.toRadixString(36).toUpperCase()}';
    final Map<String, dynamic> claim = <String, dynamic>{
      'claim_code': claimCode,
      'tag_uid': tagUid,
      'user_id': userId,
      'staff_user_id': staffUserId,
      'claimed_at': DateTime.now().toIso8601String(),
      'already_claimed': false,
    };
    _mockPrizeClaims[claimKey] = claim;

    return {'status': 'success', 'data': claim};
  }

  static int _fnv1a32(String input) {
    int hash = 0x811C9DC5;
    for (final int codeUnit in input.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }
}
