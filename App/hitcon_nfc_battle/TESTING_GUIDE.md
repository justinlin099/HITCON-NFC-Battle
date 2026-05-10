# 🧪 Mock 測試環境指南

## 概述

這個 Mock 測試環境允許你在**沒有後端 API 的情況下**進行前端開發和測試。所有數據都存儲在本地，可以快速切換不同的角色進行測試。

---

## 📋 檔案結構

```
lib/
├── config/
│   └── app_config.dart              # 應用設定（開啟/關閉 Mock 模式）
├── services/
│   ├── mock_api_service.dart       # Mock API 實現
│   └── auth_service.dart           # 認證和角色管理
└── pages/
    └── debug/
        └── test_login_page.dart    # 角色測試面板
```

---

## 🚀 快速開始

### 1. 啟用 Mock 模式

編輯 `lib/config/app_config.dart`：

```dart
class AppConfig {
  static const bool useMockServices = true;  // ✅ 啟用 Mock
  // ... 其他設定
}
```

### 2. 執行應用

```bash
flutter run
```

你會看到 **🧪 角色測試面板**，可以選擇：
- 🔧 **管理者** - 測試 NFC 寫入功能
- 🎮 **玩家** - 測試遊戲和集卡介面
- 🎯 **活動管理員** - 測試獎品發放功能

### 3. 選擇角色登入

點擊任何角色按鈕，應用會自動：
1. 載入對應的 Mock 用戶資料
2. 導向主應用介面 (`NTagReaderPage`)
3. 設定角色權限和 JWT Token

---

## 🔄 Mock 服務內容

### 用戶資料

```json
{
  "test_user_123": {
    "display_name": "Admin_Test",
    "user_type": "ADMIN",
    "emoji_icon": "🔧"
  },
  "test_user_456": {
    "display_name": "Player_Test",
    "user_type": "USER",
    "emoji_icon": "🎮"
  },
  "test_user_789": {
    "display_name": "Staff_Test",
    "user_type": "EVENT_STAFF",
    "emoji_icon": "🎯"
  }
}
```

### 模擬 API 端點

| 功能 | Mock 實現 |
|------|---------|
| `GET /users/me` | `MockApiService.getUserProfile()` |
| `PATCH /users/me` | `MockApiService.updateUserProfile()` |
| `POST /tags/pair` | `MockApiService.pairTag()` |
| `GET /users/{id}/collection` | `MockApiService.getCollectionRecords()` |
| `GET /users/{id}/collection` (他人) | `MockApiService.getUserCollection()` |

---

## 📝 使用 AuthService

### 登入

```dart
final authService = AuthService();
final success = await authService.login('ADMIN');

if (success) {
  print('用戶已登入: ${authService.currentUserId}');
  print('角色: ${authService.currentRole}');
}
```

### 獲取用戶資料

```dart
final profile = await authService.fetchUserProfile();
print('使用者名稱: ${profile?['display_name']}');
```

### 綁定 NFC 標籤

```dart
final success = await authService.pairNfcTag('04:1A:2B:3C:4D:5E:6F');
if (success) {
  print('✅ NFC 標籤綁定成功');
}
```

### 獲取集卡記錄

```dart
final collection = await authService.fetchCollectionRecords();
print('已集卡數: ${collection?['total_collected']}');
```

### 登出

```dart
await authService.logout();
```

---

## 🔧 配置選項

在 `lib/config/app_config.dart` 中調整：

```dart
class AppConfig {
  /// 啟用/禁用 Mock 服務
  static const bool useMockServices = true;

  /// 模擬網路延遲（毫秒）
  static const int mockNetworkDelay = 500;

  /// 啟用調試日誌輸出
  static const bool enableDebugLogging = true;
}
```

### 調試日誌

當 `enableDebugLogging = true` 時，會輸出如下日誌：

```
[MockAPI] 🏷️  Mock: POST /tags/pair for uid: 04:1A:2B:3C:4D:5E:6F
[AuthService] 🔐 Attempting login with userType: ADMIN
[AuthService] ✅ Login successful - User: test_user_123, Role: UserRole.admin
```

---

## 🔄 切換到真實 API

當後端完成後，只需修改一個常量：

```dart
// lib/config/app_config.dart
class AppConfig {
  static const bool useMockServices = false;  // ❌ 切換到真實 API
}
```

應用會自動：
1. 跳過測試登入頁面
2. 調用真實的後端 API（需要實現 `AuthService` 中的 TODO）
3. 使用真實的 JWT 認證

---

## 🧼 重置 Mock 數據

在測試面板中點擊 **「重置 Mock 數據」** 按鈕，會將所有 Mock 數據恢復到初始狀態。

或在代碼中：

```dart
MockApiService.resetMockData();
```

---

## ⚠️ 已知限制

- ❌ 真實 SSO 登入未實現（標記為 TODO）
- ❌ 真實後端 API 調用未實現
- ✅ Mock 數據會在每次應用重啟時恢復到初始狀態
- ✅ 本地 `SharedPreferences` 存儲 JWT（測試用）

---

## 📚 下一步

當後端 API 完成後：

1. 在 `AuthService` 中實現真實 SSO 登入邏輯
2. 在各個 `if (AppConfig.useMockServices)` 分支中實現真實 API 調用
3. 修改 `app_config.dart` 中的 `useMockServices = false`
4. 測試數據遷移和功能確認

---

## 💡 最佳實踐

✅ **開發期間** - 使用 Mock 服務，快速迭代功能  
✅ **功能完成後** - 切換到真實 API 進行集成測試  
✅ **部署前** - 在生產環境中 `useMockServices = false` 並禁用調試日誌  
✅ **測試不同角色** - 使用測試登入面板快速切換  

---

## 🐛 故障排除

### 問題：應用閃退

**解決**：檢查是否執行了 `flutter pub get`
```bash
flutter pub get
flutter clean
flutter run
```

### 問題：Mock 數據未更新

**解決**：點擊測試面板上的「重置 Mock 數據」按鈕

### 問題：調試日誌不顯示

**解決**：確認 `AppConfig.enableDebugLogging = true`

---

享受開發！ 🚀
