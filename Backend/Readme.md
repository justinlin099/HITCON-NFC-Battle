# 🎮 HITCON 2026 駭客名片遊戲 API 規格書

## 🏗️ 系統架構與全域設定 (Architecture & Global Config)

* **Base URL (Production):** `https://game.hitcon2026.online/v1`
* **Base URL (Development):** `https://<ngrok-or-local-domain>/v1`
* **Content-Type:** `application/json`
* **Authentication:** 所有的請求皆須在 Header 帶入大會 SSO 核發的 JWT。
    * `Authorization: Bearer <SSO_JWT_Token>`
* **使用者識別 (User ID):** API 內部一律解析 JWT Payload 中的 `sub` (通常是 KKTIX ID 的雜湊值) 作為使用者的 Primary Key。絕對不信任前端傳入的使用者 ID。

---

## 🛡️ 統一錯誤碼與資安攔截 (Unified Error Responses)

前端 App 開發者請在 API 攔截器 (Interceptor) 中實作以下錯誤碼的處理，以呈現對應的 UI。

* **401 Unauthorized (認證失敗):**
    * 觸發：Token 過期、無效或未攜帶。
    * `{"status": "error", "code": "UNAUTHORIZED", "message": "Invalid or expired JWT token."}`
* **403 Forbidden (權限不足 / 防偽攔截):**
    * 觸發 A (Staff API)：一般會眾呼叫工作人員專用 API。
    * 觸發 B (核心防偽)：`POST /collections/scan` 時，目標帳號與物理 NFC UID 驗證不符（判定為重放攻擊或複製卡）。
    * `{"status": "error", "code": "SECURITY_VERIFICATION_FAILED", "message": "UID mismatch or insufficient permissions."}`
* **404 Not Found (找不到資源):**
    * 觸發：掃描到未綁定的空白 NFC Tag，或查詢不存在的使用者。
    * `{"status": "error", "code": "UUID_NOT_FOUND", "message": "User or physical tag does not exist."}`
* **409 Conflict (資源衝突):**
    * 觸發：試圖綁定一張已經被其他人綁定的 NFC Tag。
    * `{"status": "error", "code": "TAG_ALREADY_IN_USE", "message": "This NFC tag is already bound to another user."}`

---

## 🧑‍💻 一、 個人化與硬體綁定 (Profile & Hardware)

### 1. 初始化 / 獲取個人資料
* **Endpoint:** `GET /users/me`
* **後端邏輯:** Lazy Initialization。如果從 JWT 解出來的 `sub` 在資料庫中沒有紀錄，後端應自動建立預設檔案。
* **Response (200 OK):**
```json
{
  "status": "success",
  "data": {
    "user_id": "sub_hash_from_jwt",
    "display_name": "Hacker_Aries",
    "user_type": "CAT", 
    "emoji_icon": "🐱",
    "bio": "I love reverse engineering.",
    "pixel_avatar_base64": "iVBORw0KGgoAAAANSU...", 
    "stats": {
      "score": 450,
      "cards_collected": 45
    }
  }
}
```

### 2. 更新個人設定
* **Endpoint:** `PATCH /users/me`
* **Request Body:** (欄位皆為 Optional)
```json
{
  "display_name": "Aries_The_Great",
  "user_type": "TECH", 
  "bio": "Updated bio.",
  "pixel_avatar_base64": "iVBORw0KGgo..."
}
```
* **Response (200 OK):** `{"status": "success", "message": "Profile updated."}`

### 3. 查看他人收集紀錄
* **Endpoint:** `GET /users/{target_id}/collection`
* **Response (200 OK):**
```json
{
  "status": "success",
  "data": {
    "owner_display_name": "Cool_Doggy",
    "total_collected": 12,
    "collection": [
      {
        "user_id": "U_1X2Y3Z",
        "display_name": "Plant_Lover",
        "emoji_icon": "🌿",
        "collected_at": "2026-04-12T10:30:00Z"
      }
    ]
  }
}
```

### 4. 實體 NFC 標籤綁定 (現場報到)
* **Endpoint:** `POST /tags/pair`
* **Request Body:**
```json
{
  "physical_uid": "04:1A:2B:3C:4D:5E:6F" // 底層硬體 UID
}
```
* **Response (200 OK):** `{"status": "success", "message": "Tag paired successfully."}`

---

## 🎮 二、 核心遊戲機制 (Gameplay Core)

### 5. 實體掃描收集 (名片交換 / 攤位集點)
會自動判定目標為會眾或贊助商。**後端必須嚴格驗證 UID 防止複製卡。**
* **Endpoint:** `POST /collections/scan`
* **Request Body:**
```json
{
  "target_user_id": "U_9V8W7X",             // 從 URL 解析出的 ID
  "scanned_nfc_uid": "04:99:88:77:66:55:44" // 從底層硬體讀出的 UID
}
```
* **Response (200 OK - 若目標為【會眾 Attendee】):**
```json
{
  "status": "success",
  "type": "ATTENDEE",
  "data": {
    "target_info": { 
      "user_type": "CAT", 
      "emoji_icon": "🐱", 
      "total_cards": 45 
    },
    "ciphertext": "U2FsdGVkX1+xxyz...", // App 本地端解密用
    "pixel_avatar_base64": "iVBORw0KGgo..."
  }
}
```
* **Response (200 OK - 若目標為【贊助商 Sponsor】):**
```json
{
  "status": "success",
  "type": "SPONSOR",
  "data": {
    "sponsor_name": "Google",
    "booth_message": "Welcome to Google! We are hiring.",
    "current_stamps": 9,
    "required_for_prize": 10
  }
}
```

### 6. 釣魚彩蛋觸發 (社交工程陷阱)
App 經由點擊連結被喚醒，且未偵測到實體 NFC 訊號時觸發。
* **Endpoint:** `POST /collections/phishing`
* **Request Body:**
```json
{
  "target_user_id": "U_9V8W7X"
}
```
* **Response (200 OK - 特殊狀態):**
```json
{
  "status": "phished",
  "data": {
    "alert_title": "Social Engineering Alert!",
    "alert_message": "來路不明的連結你也敢點？請回歸實體世界連線！",
    "score_penalty": -20
  }
}
```

---

## 🏆 三、 任務與排行榜 (Missions & Scoreboard)

### 7. 取得贊助商集點進度
* **Endpoint:** `GET /missions/sponsors`
* **Response (200 OK):**
```json
{
  "status": "success",
  "data": {
    "collected_count": 8,
    "required_for_prize": 10,
    "sponsors": [
      { "id": "sp_01", "name": "Google", "status": "collected" },
      { "id": "sp_02", "name": "Microsoft", "status": "pending" }
    ]
  }
}
```

### 8. 全域排行榜
* **Endpoint:** `GET /scoreboard/global`
* **Query Params:** `?limit=50`
* **Response (200 OK):**
```json
{
  "status": "success",
  "data": {
    "last_updated": "2026-04-12T15:00:00Z",
    "rankings": [
      { "rank": 1, "display_name": "Root_User", "score": 2500, "emoji_icon": "💻" },
      { "rank": 2, "display_name": "CTF_Player", "score": 2480, "emoji_icon": "🐱" }
    ]
  }
}
```

---

## 🛠️ 四、 工作人員快速核銷 (Staff Only)

**授權要求:** 呼叫此區 API 的 JWT Payload 必須具備 `role: "STAFF"` 等級之權限。

### 9. 實體硬體掃描核驗身分
工作人員用手機掃描會眾實體卡，直接獲取身分與領獎資格。
* **Endpoint:** `GET /staff/identify/{nfc_uid}`
* **Response (200 OK):**
```json
{
  "status": "success",
  "data": {
    "user_id": "sub_hash_from_jwt",
    "display_name": "Hacker_Aries",
    "pixel_avatar_base64": "iVBORw0K...",
    "eligibility": {
      "sponsor_prize": { "can_redeem": true, "already_redeemed": false },
      "scoreboard_prize": { "can_redeem": false, "reason": "Ranked #87 (Not in Top 10)" }
    }
  }
}
```

### 10. 確認核銷獎品
* **Endpoint:** `POST /staff/redeem`
* **Request Body:**
```json
{
  "user_id": "sub_hash_from_jwt",
  "prize_category": "SPONSOR" // 或 "SCOREBOARD"
}
```
* **Response (200 OK):** `{"status": "success", "message": "Prize redeemed successfully."}`

