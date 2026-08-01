# HITCON NFC Battle 後端 API 缺口與契約建議

> 稽核日期：2026-07-14  
> App 稽核版本：`e99961c`  
> Staging：`https://nfc-battle-staging.hitcon2026.online`  
> API 文件：後端提供的 `openapi.yaml`，OpenAPI 3.0.3 / API version 1.0.0  
> 範圍：Flutter App、OpenAPI、staging 唯讀探測、舊版 `Backend/Readme.md` 的交叉比對

本文件的目的，是把以下三種情況明確分開：

1. **後端真的還沒有 API**：App 已有功能畫面，但目前只能停在 stub 或無法完成流程。
2. **後端已有 API，但 App 尚未接上**：不需要後端重做，只要確認契約後由 App 補接。
3. **API 已存在，但契約或資安設計需要調整**：現在可能可用，但正式活動、Google Play 封測或現場營運會有風險。

文件中的範例皆不包含 JWT、Cloudflare token、JWT secret、staff danger token 或任何正式憑證。

---

## 1. 結論摘要

### P0：活動流程會被卡住，建議最優先完成

| 項目 | 現況 | 影響 |
|---|---|---|
| API base path 不一致 | OpenAPI 宣告 `/v1`，staging 實際使用根路徑 | 依文件產生的 client 會全部打到 404 |
| 實體卡列印訂單 API | OpenAPI 無此 API，App 目前直接回傳 `null` | 使用者無法送出列印、取得收件編號與條碼 |
| 工作人員兌獎 API | OpenAPI 只有查自己的得獎結果，沒有現場核銷 | 管理者掃卡後無法確認領獎 |
| 工作人員解鎖 Tag credential API | App 只能取得目前登入者自己的 `nfc_tag_key` | STAFF 無法解鎖或重寫其他會眾的 Tag |
| Tag 配對缺乏 prepare/complete 交易 | App 先寫入與上鎖，最後才呼叫 `/tags/pair` | API 失敗時會留下「Tag 已鎖、server 未配對」的半完成狀態 |

### P1：正式上線與資安完整性

| 項目 | 現況 | 影響 |
|---|---|---|
| 登入 token 發行契約缺失 | API 只驗 JWT，未定義取得、換發、撤銷方式 | 換手機、token 過期、封測帳號與遺失處理沒有正式流程 |
| 使用者內容檢舉、封鎖、帳號刪除 API | 不存在 | App 有暱稱、大頭貼、自介與外部連結，需要營運與商店政策處理流程 |
| Profile 欄位不足 | link、卡色被塞進 bio marker；emoji 是未定義格式的字串 | 驗證、搜尋、遷移與跨版本相容性差 |
| Phishing API 信任 client 傳入 victim | victim 本來可以從 JWT 得知 | 惡意 client 可偽造受害者 ID |
| NTAG credential 暴露範圍過大 | `/users/me` 與 bootstrap 都回傳長期金鑰 | 一般 profile API 洩漏時會連帶暴露 Tag 寫入密碼 |

### P2：資料量、效能與維運

| 項目 | 現況 | 影響 |
|---|---|---|
| Bootstrap 回傳全部完整 profile 與 base64 大頭貼 | App 每次刷新及掃卡後都可能重抓 | 收藏增加後容易超過 App 的 5 MiB response 上限 |
| Collection 與 scoreboard 分頁資訊不足 | scoreboard 沒有 `total_count` / `has_more` | App 無法分辨「目前回傳 50 筆」和「總共有 50 人」 |
| Error envelope 缺少 request ID | App 只能看到 code/message | 現場問題難以從 App log 對到 Worker log |
| 寫入類 API 缺少一致的 idempotency | NFC intent、deep link、網路重試都可能重送 | 可能重複收藏、重複扣分、重複下單或重複核銷 |

---

## 2. 目前 API 與 App 使用矩陣

### 2.1 OpenAPI 已定義且 App 已接

| Method | Path | App 用途 | 結論 |
|---|---|---|---|
| GET | `/users/me` | 取得自己 profile、配對 UID、目前也取得 Tag 金鑰 | 已接，但不應在此回傳 Tag credential |
| PATCH | `/users/me` | 更新名字、emoji、bio、大頭貼 | 已接，但缺欄位限制與 link/card color 原生欄位 |
| GET | `/users/me/bootstrap` | 自己資料與完整收藏清單 | 已接，但 payload 會持續膨脹 |
| GET | `/users/{user_id}` | 查看其他使用者 profile | 已接 |
| GET | `/users/{user_id}/collection` | 查看其他使用者收藏 | 已接，建議分頁 |
| POST | `/tags/pair` | 綁定 physical UID | 已接，但呼叫順序有半完成風險 |
| POST | `/collection/scan` | 驗證實體 Tag 並收藏卡片 | 已接 |
| POST | `/collection/phishing` | 非實體 Tag deep link 事件 | 已接，但 request 不應接受 victim |
| GET | `/missions/stamp` | 集卡獎進度 | 已接 |
| GET | `/scoreboard` | 排行榜 | 已接，但缺總筆數資訊 |

### 2.2 OpenAPI 已定義，但 App 尚未完整使用

| Method | Path | 後端狀態 | App 待辦 |
|---|---|---|---|
| GET | `/users/me/prize` | 已存在；OPEN/FREEZING 時回 409 | 將收藏頁兌獎按鈕接到正式結果，不要只依賴 mission 畫面 |
| POST | `/users/batch` | 已存在 | 可用於 collection 增量更新，降低 bootstrap 負擔 |
| GET | `/staff/scoreboard_status` | 已存在 | 管理員頁可顯示 OPEN/FREEZING/FROZEN |
| POST | `/staff/replace_user_tag` | 已存在 | 管理員重綁流程應接此 API，並與 credential 流程整合 |
| POST | `/staff/freeze_scoreboard` | 已存在 | 管理員結算功能尚未完整整合 |
| POST | `/staff/resume_scoreboard` | 已存在 | 管理員恢復計分功能尚未完整整合 |

### 2.3 App 已有畫面或方法，但後端 API 缺失

| 功能 | App 現況 | 缺少的 API |
|---|---|---|
| 實體卡列印 | `submitCardPrintOrder()` 只記錄「OpenAPI 沒有 endpoint」並回 `null` | 建立訂單、查狀態、staff 查單與更新狀態 |
| 現場兌獎 | `confirmPrizeClaim()` 只回 `null` | staff 辨識資格、原子核銷、查核銷紀錄 |
| STAFF 解鎖 Tag | 管理者 UI 會呼叫一般使用者的 credential 取得方法 | staff 專用、可稽核的解鎖 credential endpoint |
| 登入 token 發行 | App 可貼上/掃描 JWT 或開 email App | email magic link/兌換、refresh、revoke 的正式契約或外部 Auth 文件 |
| 檢舉/封鎖 | 無 | report、block/unblock、查封鎖名單 |
| 帳號與伺服器資料刪除 | 無 | delete/deactivate/anonymize request |

---

## 3. Staging 實測結果

2026-07-14 使用合法 ATTENDEE/STAFF 測試 JWT，只進行 GET 或 OPTIONS 探測，沒有建立、刪除或修改正式資料。

| Request | 結果 | 判讀 |
|---|---:|---|
| GET `/users/me` | 200 | 根路徑是目前實際 API |
| GET `/v1/users/me` | 404 | 與 OpenAPI `servers.url` 不一致 |
| GET `/users/me/bootstrap` | 200 | 現行 bootstrap 可用 |
| GET `/missions/stamp` | 200 | mission 可用 |
| GET `/scoreboard?limit=1` | 200 | scoreboard 可用 |
| GET `/users/me/prize` | 409 `SCOREBOARD_NOT_FROZEN` | 符合 OpenAPI 定義 |
| GET/OPTIONS `/print-orders` | 404 | OpenAPI 也未定義，判定缺少 |
| GET `/staff/prizes/identify` | 404 | OpenAPI 也未定義，判定缺少 |
| OPTIONS `/staff/prizes/redeem` | 404 | OpenAPI 也未定義，判定缺少 |
| GET/OPTIONS `/staff/tags/unlock-secret` | 404 | OpenAPI 也未定義，判定缺少 |
| OPTIONS `/auth/refresh` | 404 | 目前沒有 refresh 契約 |
| OPTIONS `/users/me/report` | 404 | 目前沒有檢舉契約 |

注意：OPTIONS 404 本身不一定能證明所有框架中的 method 都不存在；這裡是搭配 OpenAPI 缺席、App stub 與路由結果一起判讀。

---

## 4. P0 契約一：統一 API base path

### 問題

OpenAPI 宣告：

```yaml
servers:
  - url: https://{devHost}/v1
```

但 staging 實際可用的是：

```text
https://nfc-battle-staging.hitcon2026.online/users/me
```

`/v1/users/me` 目前回 404。任何依 OpenAPI 產生的 SDK、Postman collection 或後端測試都會走錯路徑。

### 建議

正式 API 建議採 `/v1`，並提供一段遷移期：

1. Worker 同時接受根路徑與 `/v1`。
2. 更新 App 的 `API_BASE_URL` 為帶 `/v1` 的 URL。
3. 確認封測版本全部更新後，再移除未版本化路徑。
4. OpenAPI 的 staging server 寫成固定可測 URL，不要用預設為 localhost 的 `devHost`。
5. CI 加入 contract smoke test，至少檢查 OpenAPI 中每個 operation 不會回 route-level 404。

若後端決定維持根路徑，也必須立即修正 OpenAPI；不可讓文件和實作各自成立。

另外，未知 API 路徑應回 JSON error，不應回純文字：

```json
{
  "status": "error",
  "code": "ROUTE_NOT_FOUND",
  "message": "API route not found.",
  "request_id": "req_01..."
}
```

### 4.1 Source of truth 也需要統一

目前 OpenAPI 說 `Backend/game-flow.md` 才是產品行為的 source of truth，但本次 checkout 找不到該檔案；現存的舊 `Backend/Readme.md` 又仍使用：

- `/collections/scan`，目前是 `/collection/scan`
- `/missions/sponsors`，目前是 `/missions/stamp`
- `/scoreboard/global`，目前是 `/scoreboard`
- 已消失的舊 `/staff/identify/{nfc_uid}` 與 `/staff/redeem`

建議只保留一個可執行的契約來源：

1. OpenAPI 作為 HTTP contract source of truth。
2. `game-flow.md` 只描述跨 API 狀態機與產品規則，並確實 commit 進 repo。
3. 舊 README 標示 deprecated 或移除，避免新工程師照舊路徑實作。
4. CI 由 OpenAPI 對 staging 做 route/response schema contract test。

---

## 5. P0 契約二：實體卡列印訂單

### 5.1 App 現有輸出

App 已能產生以下列印檔：

| 欄位 | 值 |
|---|---|
| Media type | `image/png` |
| 尺寸 | 638 × 1011 px |
| 解析度語意 | 300 DPI |
| 實體卡 | CR80 / ISO 7810 ID-1 / 53.98 × 85.60 mm |
| 方向 | 直式 |
| App format id | `EVOLIS_PRIMACY_CR80_300DPI_PNG` |
| 目標設備 | Evolis Primacy OEM |

App 送出後預期至少收到：

- `order_id`
- `barcode_value`
- `file_name`（可選）
- `format`（可選）

使用者會保存條碼，到紀念品攤位付款後由工作人員列印。

### 5.2 建議 API

#### 建立訂單

`POST /print-orders`  
Auth：ATTENDEE、STAFF  
Content-Type：`multipart/form-data`  
Header：`Idempotency-Key: <random UUID>`

Multipart parts：

| Part | 類型 | 必要 | 說明 |
|---|---|---:|---|
| `artwork` | PNG binary | 是 | 不要將圖片 base64 放進 JSON |
| `metadata` | JSON | 是 | 格式與尺寸資訊 |

`metadata`：

```json
{
  "format": "EVOLIS_PRIMACY_CR80_300DPI_PNG",
  "width_px": 638,
  "height_px": 1011,
  "dpi": 300,
  "orientation": "PORTRAIT",
  "printer_family": "EVOLIS_PRIMACY_OEM",
  "profile_version": 12
}
```

成功回應：

```json
{
  "status": "success",
  "data": {
    "order_id": "po_01J...",
    "barcode_value": "H26P-7K4M-92QD",
    "status": "SUBMITTED",
    "file_name": "po_01J....png",
    "format": "EVOLIS_PRIMACY_CR80_300DPI_PNG",
    "created_at": "2026-07-14T12:34:56Z"
  }
}
```

建議錯誤：

| HTTP | code | 條件 |
|---:|---|---|
| 400 | `INVALID_PRINT_METADATA` | 尺寸、DPI、format 不符 |
| 400 | `INVALID_PNG` | 非 PNG、檔案毀損、實際 IHDR 尺寸不符 |
| 401 | `UNAUTHORIZED` | JWT 無效 |
| 413 | `ARTWORK_TOO_LARGE` | 超過 5 MiB |
| 409 | `DUPLICATE_PRINT_ORDER` | 相同 idempotency key 已建立 |
| 422 | `PROFILE_NOT_READY` | 名字、圖片或必要卡片資料未完成 |
| 429 | `PRINT_ORDER_RATE_LIMITED` | 短時間重複送出 |

#### 使用者查詢訂單

`GET /print-orders/{order_id}`  
Auth：訂單擁有者或 STAFF

#### STAFF 以條碼查單

`POST /staff/print-orders/lookup`  
Auth：STAFF

```json
{
  "barcode_value": "H26P-7K4M-92QD"
}
```

#### STAFF 更新狀態

`PATCH /staff/print-orders/{order_id}`  
Auth：STAFF  
Header：`Idempotency-Key`

```json
{
  "status": "PAID",
  "note": "Paid at merchandise booth"
}
```

建議狀態機：

```text
SUBMITTED -> PAID -> PRINTING -> PRINTED
SUBMITTED -> CANCELLED
PAID/PRINTING -> FAILED -> PRINTING
```

### 5.3 儲存與安全要求

1. 圖檔放 R2/object storage，DB 只存 object key、hash、尺寸與狀態。
2. `barcode_value` 必須是隨機 opaque value，不可直接使用 user_id 或可猜的流水號。
3. 條碼內容不可帶 JWT、email 或其他 PII。
4. 後端必須解碼 PNG 驗證，不可只相信副檔名與 client metadata。
5. 設定檔案保存期限，例如活動結束後 30 天刪除原圖。
6. 記錄 `sha256`，避免同一 payload 因重試產生多張訂單。
7. STAFF 每次改狀態要有 audit log：staff user、時間、舊狀態、新狀態、request ID。

### 5.4 App 配合修改

目前 API client 只有 JSON GET/POST/PATCH，沒有 multipart。後端契約確認後，App 要增加：

- multipart upload
- 自訂 `Idempotency-Key` header
- upload progress/timeout
- 413 與 retryable error 顯示

---

## 6. P0 契約三：現場兌獎與防重複核銷

### 6.1 現況缺口

目前 `GET /users/me/prize` 只能讓使用者在 scoreboard frozen 後看自己的獎項，不能完成現場核銷。

管理者頁現有流程會掃：

- 實體 NFC UID
- Tag NDEF 中的 user_id

然後呼叫 App 的 `confirmPrizeClaim(tagUid, userId)`。但該方法目前沒有 API 可呼叫。

舊版 `Backend/Readme.md` 曾描述：

- `GET /staff/identify/{nfc_uid}`
- `POST /staff/redeem`

這兩個路由不在目前 OpenAPI，也不在 staging。建議用 current naming 與 POST body 重新納入正式契約。

### 6.2 建議 API

#### STAFF 辨識會眾與資格

`POST /staff/prizes/identify`  
Auth：STAFF

```json
{
  "physical_id": "04:1A:2B:3C:4D:5E:6F",
  "ndef_user_id": "attendee_123"
}
```

後端應以 `physical_id` 對 `nfc_tags` 查到的 user 為準，`ndef_user_id` 只用來檢查不一致與防偽，不可反過來信任 NDEF。

成功回應：

```json
{
  "status": "success",
  "data": {
    "user_id": "attendee_123",
    "display_name": "Hacker",
    "physical_id_verified": true,
    "stamp_progress": {
      "unique_stamp_count": 8,
      "target": 8
    },
    "prizes": [
      {
        "type": "STAMP",
        "eligible": true,
        "redeemed": false,
        "redeemed_at": null
      },
      {
        "type": "RANK",
        "eligible": false,
        "redeemed": false,
        "reason": "SCOREBOARD_NOT_FROZEN"
      }
    ],
    "freeze_id": null
  }
}
```

#### STAFF 原子核銷

`POST /staff/prizes/redeem`  
Auth：STAFF  
Header：`Idempotency-Key`

```json
{
  "user_id": "attendee_123",
  "physical_id": "04:1A:2B:3C:4D:5E:6F",
  "prize_types": ["STAMP"]
}
```

成功或重送回應：

```json
{
  "status": "success",
  "data": {
    "claim_code": "PRIZE-2026-8F4K2M",
    "already_claimed": false,
    "results": [
      {
        "type": "STAMP",
        "redeemed": true,
        "redeemed_at": "2026-07-14T13:00:00Z"
      }
    ]
  }
}
```

若相同 idempotency key 重送，應回同一個 `claim_code`，不可新增第二筆。

建議錯誤：

| HTTP | code | 條件 |
|---:|---|---|
| 400 | `TAG_USER_MISMATCH` | UID 與 NDEF/user_id 不一致 |
| 403 | `STAFF_REQUIRED` | 非 STAFF |
| 404 | `TAG_NOT_PAIRED` | UID 無配對 |
| 409 | `PRIZE_NOT_ELIGIBLE` | 尚未達成資格 |
| 409 | `PRIZE_ALREADY_REDEEMED` | 已核銷；response 仍附原 claim data |
| 409 | `SCOREBOARD_NOT_FROZEN` | 嘗試兌換排名獎但尚未結算 |

### 6.3 必須先決定的產品規則

建議規則：

- **STAMP 集卡獎**：活動進行中即可兌換，依 live collection/stamp mission 判定。
- **RANK 排名獎**：只有 scoreboard freeze 後，依不可變的 freeze snapshot 判定。

若產品決定所有獎品都要 freeze 後才能領，也必須把收藏頁按鈕、錯誤訊息與現場 SOP 一起改掉。

### 6.4 DB 約束

建議 `prize_redemptions` 至少具有：

- `redemption_id`
- `user_id`
- `prize_type`
- `freeze_id`，STAMP live prize 可為 null 或使用活動期 ID
- `claim_code`，unique
- `redeemed_by_staff_user_id`
- `redeemed_at`
- `physical_id`
- `idempotency_key`
- `request_id`

必要 unique constraint：

```text
UNIQUE(event_id, user_id, prize_type)
UNIQUE(redeemed_by_staff_user_id, idempotency_key)
```

資格檢查與 INSERT 必須在同一個 transaction 完成，不能先查再另外寫入。

---

## 7. P0 契約四：Tag credential 與可恢復的配對流程

### 7.1 現況

OpenAPI 的 `UserProfileSelf` 會回傳：

```text
nfc_tag_key: 12 個小寫 hex 字元，共 6 bytes
```

App 將：

- 前 4 bytes 當 NTAG PWD
- 後 2 bytes 當 PACK

PACK 是驗證成功時 Tag 回傳的 2-byte acknowledgement，不是第二組密碼。

目前 credential 的主要問題：

1. OpenAPI 將它定義為 per-user key，不是 per-physical-tag key。
2. `/users/me` 與 `/users/me/bootstrap` 都會回傳長期 credential。
3. replacement tag 可能沿用同一把 key。
4. STAFF 只能拿到自己的 key，無法解鎖會眾的 Tag。
5. App 目前先寫 NDEF、再鎖 Tag、最後才呼叫 `/tags/pair`；server 寫入失敗就留下半完成狀態。

NTAG215 的 32-bit PWD 只能視為有限的防誤寫保護，不能作為高強度身分認證，也不能取代 server 端 `physical_id -> user_id` 驗證。

### 7.2 最低限度修正

1. 從 `GET /users/me` 與 `GET /users/me/bootstrap` 移除 `nfc_tag_key`。
2. credential 只由用途明確的 endpoint 短暫回傳。
3. credential 以 canonical physical UID 為單位，不以 user 為單位。
4. STAFF 解鎖必須有 reason 與 audit log。
5. 所有 UID 統一格式，例如大寫、colon-separated：

```text
04:1A:2B:3C:4D:5E:6F
```

### 7.3 建議的完整配對 API

#### Step 1：準備配對

`POST /tags/pair/prepare`  
Auth：ATTENDEE、STAFF  
Header：`Idempotency-Key`

```json
{
  "physical_id": "04:1A:2B:3C:4D:5E:6F"
}
```

```json
{
  "status": "success",
  "data": {
    "pairing_session_id": "tps_01J...",
    "user_id": "attendee_123",
    "physical_id": "04:1A:2B:3C:4D:5E:6F",
    "ndef_url": "https://game.hitcon2026.online/b?u=attendee_123",
    "pwd_hex": "A1B2C3D4",
    "pack_hex": "E5F6",
    "key_version": 1,
    "expires_at": "2026-07-14T13:05:00Z"
  }
}
```

Server 在 prepare 時只建立有時效的 reservation，不應立即讓舊 Tag 失效。

#### Step 2：App 寫入並鎖定

App 寫入 NDEF URL、設定 PWD/PACK、讀回驗證。這一步失敗時 pairing session 自動過期，不改變正式 mapping。

#### Step 3：完成配對

`POST /tags/pair/complete`  
Auth：與 prepare 相同的 user  
Header：`Idempotency-Key`

```json
{
  "pairing_session_id": "tps_01J...",
  "write_verified": true
}
```

完成時才在 transaction 中更新 `nfc_tags` 與 user mapping。重送同一 session 應回相同成功結果。

### 7.4 STAFF 解鎖 credential

`POST /staff/tags/unlock-credential`  
Auth：STAFF

```json
{
  "physical_id": "04:1A:2B:3C:4D:5E:6F",
  "reason": "User requested tag replacement at help desk"
}
```

```json
{
  "status": "success",
  "data": {
    "physical_id": "04:1A:2B:3C:4D:5E:6F",
    "pwd_hex": "A1B2C3D4",
    "pack_hex": "E5F6",
    "key_version": 1,
    "expires_at": "2026-07-14T13:05:00Z",
    "audit_id": "audit_01J..."
  }
}
```

要求：

- 不可只依 request 中的 user_id 決定 key。
- 必須確認 role=STAFF。
- rate limit，例如每位 staff 每分鐘最多 10 次。
- 記錄 staff、UID、reason、時間、IP/request ID。
- response 加 `Cache-Control: no-store`。
- Worker log 不得輸出 PWD/PACK。

### 7.5 Credential 產生建議

兩種可接受方式：

1. **每張 Tag 隨機產生並加密保存**：容易輪替，但要安全管理資料庫密文金鑰。
2. **以 server secret、canonical UID、key version 做 KDF/HMAC 派生**：不需保存明文，但要保留 key version 並規劃 secret rotation。

不可：

- 用 UID 直接截斷或 hash 後不加 secret。
- 用 user_id 直接產生。
- 把 server master secret、JWT secret 放進 App。
- 在一般 profile response 或 bootstrap 中回傳 credential。

---

## 8. P1 契約：登入 token 的發行、換發與撤銷

### 8.1 現況

App 現在能：

- 貼上 JWT
- 掃描含 JWT 的 QR code
- 開啟預設 email App，沒有 email App 時開 Gmail 網頁

API 文件只描述 Bearer JWT 的驗證規則與 claims，沒有描述 token 如何取得。這可以由另一個 conference auth service 負責，不一定要由 NFC Battle Worker 實作；但正式上線前必須有一份明確、可測試的契約。

最低必要 claims：

- `sub`：不可變的 user ID
- `exp`：過期時間
- `iss`：issuer
- `aud`：NFC Battle API audience
- `role`：ATTENDEE / STAFF / SPONSOR / COMMUNITY

JWT signing secret 絕對不可進 App。若 issuer 與 API 是不同服務，長期建議改用非對稱簽章，讓 API 只持有 public key。

### 8.2 建議流程

若採 email magic link：

1. `POST /auth/email/start`：輸入 email，永遠回相同訊息避免帳號枚舉。
2. Email 裡放一次性、短效 exchange code，不直接放長期 JWT。
3. `POST /auth/email/exchange`：用 code 換 access/refresh token。
4. `POST /auth/refresh`：refresh rotation。
5. `POST /auth/revoke`：登出、遺失裝置或帳號停權。

Token response 範例：

```json
{
  "status": "success",
  "data": {
    "access_token": "<JWT>",
    "token_type": "Bearer",
    "expires_in": 3600,
    "refresh_token": "<opaque token>",
    "refresh_expires_in": 2592000
  }
}
```

若活動方會直接寄發一次性的長效 JWT，也至少要定義：

- 到期日
- 補發流程
- revoke/denylist
- STAFF token 的核發與撤權
- Google Play reviewer 測試帳號
- 同一使用者換手機時的處理

不要把 JWT 放在一般 https URL query 中，因為可能進入瀏覽器歷史、analytics 或 proxy log。QR 若直接承載 JWT，也應使用短效 token 或一次性 exchange code。

---

## 9. P1 契約：Profile 欄位、驗證與相容性

### 9.1 現況問題

OpenAPI 只允許更新：

- `display_name`
- `emoji_icon`
- `bio`
- `pixel_avatar_base64`

App 為了保存 link 與 card color，目前把 metadata 編進 bio：

```text
[[HITCON_CARD:v1:<base64url JSON>]]
```

JSON 內使用：

- `l`：link
- `c`：card color

這會讓 bio 驗證、後台顯示、其他 client 與資料遷移變複雜。

另外，OpenAPI 寫「48×48 avatar」，但 App 實際流程是：

- 邏輯繪圖網格：48×48
- 上傳 PNG：512×512，nearest-neighbor 放大後的成品

後端若突然嚴格限制 PNG IHDR 必須 48×48，現有 App 會全部更新失敗。

### 9.2 建議 Profile schema

```json
{
  "display_name": "Hacker",
  "bio": "I love reverse engineering.",
  "emoji_icons": ["✨", "💻", "🔥"],
  "link_url": "https://example.com/profile",
  "card_color_argb": 4294956800,
  "pixel_avatar_base64": "iVBOR...",
  "avatar_logical_width": 48,
  "avatar_logical_height": 48
}
```

建議限制：

| 欄位 | 建議限制 |
|---|---|
| `display_name` | trim 後 1–32 Unicode grapheme clusters；拒絕控制字元 |
| `bio` | 0–500 grapheme clusters；拒絕 NUL 與不可見控制字元 |
| `emoji_icons` | array，0–3 items；每個 item 為單一 emoji grapheme；去重 |
| `link_url` | 0–2048 chars；只能 HTTPS；不可有 username/password；後端不得主動抓取該 URL |
| `card_color_argb` | unsigned 32-bit，或改為固定格式 `#AARRGGBB` |
| `pixel_avatar_base64` | 僅接受 PNG；base64 decode 後設上限；驗證尺寸與解碼成功 |

Avatar 建議二選一：

1. 明確接受目前 App 的 512×512 PNG，另外記錄 logical grid=48。
2. 將 API 改為傳 48×48 indexed/grid data，由 server 產生各種顯示尺寸。

短期建議選 1，避免延誤；後端 decode 後可正規化並存 object storage。

### 9.3 相容性遷移

1. 新版 API 先同時回傳原生 `link_url` / `card_color_argb` 與舊 bio。
2. Server migration 解析既有 `HITCON_CARD:v1` marker。
3. 新版 App 優先讀原生欄位，缺少時才 fallback 解 marker。
4. 所有支援中的 App 版本更新後，停止將 metadata 寫入 bio。
5. 不需要新增 `attribute_label`；emoji 顯示名稱可以由 App 的 emoji catalog 本地產生。

---

## 10. P1 契約：Phishing 事件不可信任 victim

### 現況

目前 request：

```json
{
  "victim": "current_user_id",
  "attacker": "user_id_from_link"
}
```

`victim` 就是 JWT 的 `sub`，不應由 client 自行聲明。惡意 client 可以替別人製造 phishing 事件。

### 建議

改為：

`POST /collection/phishing`  
Auth：ATTENDEE 等有效 user  
Header：`Idempotency-Key`

```json
{
  "attacker_user_id": "attendee_456",
  "source": "APP_LINK_WITHOUT_PHYSICAL_TAG"
}
```

Server：

1. `victim_user_id = JWT.sub`。
2. 拒絕 attacker=victim。
3. 對相同 victim、attacker、短時間窗口去重。
4. 對 deep link 重送設 idempotency。
5. 保留 evidence metadata，但不要存完整 JWT 或敏感 intent dump。

---

## 11. P1 契約：檢舉、封鎖與帳號資料處理

App 會公開顯示使用者產生的暱稱、大頭貼、自介、emoji 與外部連結。正式封測前至少需要明確決定內容治理與資料刪除流程。

### 建議 API

#### 檢舉使用者內容

`POST /reports`

```json
{
  "reported_user_id": "attendee_456",
  "content_type": "PROFILE",
  "reason": "INAPPROPRIATE_CONTENT",
  "details": "Optional short explanation",
  "profile_version": 12
}
```

Server 從 JWT 取得 reporter。建議 reason enum：

- `INAPPROPRIATE_CONTENT`
- `HARASSMENT`
- `IMPERSONATION`
- `MALICIOUS_LINK`
- `OTHER`

需要防重送、rate limit、staff review status 與 audit log。

#### 封鎖/解除封鎖

- `POST /users/{user_id}/block`
- `DELETE /users/{user_id}/block`
- `GET /users/me/blocks`

需先定義封鎖效果：至少在其他使用者 collection/profile 畫面隱藏對方自介與 link；是否影響實體收藏和 scoreboard 必須由產品決定。

#### 刪除或匿名化

- `DELETE /users/me`，或
- `POST /users/me/deletion-request` 回 202

因為 user 是由 conference JWT lazy initialize，建議先決定：

- 是刪除 NFC Battle profile，還是連活動帳號一起刪除。
- 已產生的 collection、scoreboard snapshot、prize audit 要刪除、匿名化或依法保留。
- print artwork 與 report evidence 的 retention。

---

## 12. P2：Bootstrap、分頁與圖片傳輸

### 12.1 問題

`GET /users/me/bootstrap` 目前回：

- 完整自己的 profile
- 所有已收藏使用者的完整 profile
- 每個 profile 的 base64 PNG

App API client 對單一 response 設定 5 MiB 上限。收藏數量和 512×512 PNG 增加後，bootstrap 會超過上限，並造成每次刷新與掃卡後的大量 decode、JSON parse 與記憶體複製。

### 12.2 建議

短期：

1. Bootstrap 回 slim profile，不要內嵌所有 base64 avatar。
2. 使用既有 `POST /users/batch` 搭配 `profile_version` 做增量更新。
3. Collection endpoint 加 cursor 或 offset/limit。
4. 加 `ETag` / `If-None-Match` 或 version query。

中期：

- Avatar 存 R2，profile 回 `avatar_url`、`avatar_sha256`、`avatar_version`。
- CDN URL 可公開讀取但不可列舉，或使用適當期限的 signed URL。
- App 本地快取依 sha/version 更新。

建議 collection response：

```json
{
  "status": "success",
  "data": {
    "items": [],
    "next_cursor": "cur_...",
    "has_more": true,
    "total_count": 83,
    "collection_version": 27
  }
}
```

### 12.3 Scoreboard

目前 `GET /scoreboard?offset=0&limit=50` 回一頁 entries，但 App 無法知道總人數。

建議加入：

```json
{
  "offset": 0,
  "limit": 50,
  "total_count": 137,
  "has_more": true,
  "next_offset": 50,
  "entries": []
}
```

後端應保證同一頁 `user_id` 唯一，並在 DB/query 層測試，避免 join 造成同一人重複多次。

---

## 13. 共通 API 規範

### 13.1 Error envelope

所有路由，包括 404、413、429 與 Worker 未捕捉例外，都應回 JSON：

```json
{
  "status": "error",
  "code": "TAG_USER_MISMATCH",
  "message": "The scanned physical tag does not belong to this user.",
  "request_id": "req_01J...",
  "details": {
    "field": "physical_id"
  }
}
```

Production 的 `message` 不要包含 stack trace、SQL、secret、JWT 或內部 object key。

### 13.2 Request tracing

每個 response：

- Header：`X-Request-Id`
- JSON：`request_id`

若 client 傳 `X-Request-Id`，後端可接受合法格式或自行覆寫。App 回報問題時即可提供 request ID。

### 13.3 Idempotency

至少套用於：

- `/collection/scan`
- `/collection/phishing`
- Tag prepare/complete/replace
- print order create/status
- prize redeem
- scoreboard freeze/resume

規則：

1. key scope 至少包含 authenticated user + route。
2. 保存 request body hash。
3. 同 key、同 body 回原 response。
4. 同 key、不同 body 回 409 `IDEMPOTENCY_KEY_REUSED`。
5. 明確設定保存期限。

### 13.4 Rate limit

建議 response headers：

- `RateLimit-Limit`
- `RateLimit-Remaining`
- `RateLimit-Reset`
- `Retry-After`（429）

STAFF credential、auth email、phishing、report、print order 都要單獨設限制。

### 13.5 Authorization

不可只在 UI 隱藏管理員按鈕。每個 `/staff/*` endpoint 都必須由 server 驗證 JWT role。

STAFF danger token 若仍保留，只能放 server-to-server 或受控後台，不可編進 App，也不可取代 staff identity/audit。

---

## 14. 建議資料表與唯一性約束

以下是契約需要的最小資料模型，不限制實際使用 D1、PostgreSQL 或其他資料庫。

### `nfc_tags`

- `physical_id` unique, canonicalized
- `user_id`，視產品規則可 unique，確保一人同時只有一張 active tag
- `status`：ACTIVE / REPLACED / REVOKED
- `key_version`
- `paired_at`
- `replaced_at`

### `tag_pairing_sessions`

- `session_id` unique
- `physical_id`
- `user_id`
- `expires_at`
- `completed_at`
- `idempotency_key`

### `collection_events` / `collections`

- unique collector + target
- 保存首次收藏時間
- 重掃可以更新 last_scanned_at，但不可新增第二張相同卡
- scan 交易內驗證 physical_id mapping

### `print_orders`

- `order_id` primary key
- `barcode_value` unique
- `user_id`
- `object_key`
- `artwork_sha256`
- `status`
- `profile_version`
- `created_at` / `updated_at`
- unique user + idempotency key

### `prize_redemptions`

- unique event + user + prize type
- `claim_code` unique
- staff identity、physical UID、freeze ID、request ID

### `audit_logs`

至少涵蓋：

- staff 取得 Tag credential
- replace tag
- prize redeem
- print status transition
- scoreboard freeze/resume
- moderation action

---

## 15. App 端需要配合，但不是後端缺 API 的項目

後端完成契約後，App 還需安排：

1. 接上既有 `GET /users/me/prize`。
2. 使用既有 `POST /users/batch` 做增量同步。
3. 管理者頁接 `scoreboard_status`、freeze、resume、replace tag。
4. API client 增加 multipart、DELETE、額外 headers、request ID、upload progress。
5. 將 `submitCardPrintOrder()` 與 `confirmPrizeClaim()` 的 stub 改成正式 API。
6. 將 Tag pairing 改為 prepare -> write/lock -> complete。
7. 從一般 profile 讀取 `nfc_tag_key` 的程式移除。
8. Profile 改讀原生 `link_url` / `card_color_argb` / `emoji_icons`，保留舊 bio marker fallback。
9. Scoreboard 顯示 `total_count`，不要用當頁陣列長度當總玩家數。
10. 所有寫入 request 產生並保存 idempotency key，重試時重用同一 key。

---

## 16. 後端驗收測試清單

### Auth / RBAC

- [ ] 缺 JWT、過期 JWT、錯 issuer、錯 audience 都回 401。
- [ ] ATTENDEE 呼叫所有 `/staff/*` 都回 403。
- [ ] STAFF 操作 audit log 有可追蹤的 staff user 與 request ID。
- [ ] JWT、PWD/PACK、refresh token 不出現在 log。

### Tag

- [ ] UID 不同格式會 canonicalize 成同一值。
- [ ] 同一 UID 不可配給兩人。
- [ ] 同一人 replacement 後舊 UID 立即失效。
- [ ] prepare 過期不改正式 mapping。
- [ ] complete 重送不產生重複 mapping。
- [ ] App 寫入/鎖定失敗時可恢復，不留下無法解鎖的 orphan tag。
- [ ] STAFF unlock credential 只能取指定 UID 的正確 key，並留下 audit。

### Collection / phishing

- [ ] 相同 collector + target 多次掃描只收藏一張。
- [ ] URL user_id 與 physical UID mapping 不符時拒絕。
- [ ] App 未開啟、背景、前景造成的重複 intent 不會重複計分。
- [ ] phishing victim 永遠取自 JWT。
- [ ] 同一 phishing event 重送不會重複扣分或重複寫事件。

### Profile

- [ ] 名稱空白、過長、控制字元被拒絕。
- [ ] emoji 最多三個 grapheme，不因 skin tone/ZWJ 被誤算成多個。
- [ ] link 只接受 HTTPS，拒絕 credentials 與 malformed URL。
- [ ] 非 PNG、超限檔案、解碼失敗圖片被拒絕。
- [ ] 明確測試現行 512×512 avatar 與 logical 48×48 契約。
- [ ] 舊 bio marker 能遷移且不遺失 link/card color。

### Prize

- [ ] 不符合資格不可核銷。
- [ ] UID/user mismatch 不可核銷。
- [ ] 同一獎項併發兩次只有一筆成功。
- [ ] 相同 idempotency key 回相同 claim code。
- [ ] STAMP live 與 RANK frozen 規則符合產品決策。

### Print

- [ ] 只接受 638×1011 PNG 與指定 format。
- [ ] 偽造 MIME、錯尺寸、超過 5 MiB 被拒絕。
- [ ] 相同 idempotency key 不建立第二張訂單。
- [ ] 非本人不能查訂單。
- [ ] 條碼不可推回 user_id。
- [ ] status transition 不合法時回 409。
- [ ] artwork retention job 能按規則刪除。

### Payload / pagination

- [ ] 100、500 或預估最大收藏數時 response 不超過 client 限制。
- [ ] collection pagination 不漏資料、不重複。
- [ ] scoreboard `total_count` 正確，entries 的 user_id 不重複。
- [ ] ETag/version 不變時能回 304 或 unchanged result。

---

## 17. 建議交付順序

### Milestone A：先解除現場流程阻塞

1. 修正 OpenAPI base URL 與 staging 路由。
2. 完成 print order create/query/staff status。
3. 完成 staff prize identify/redeem。
4. 完成 staff Tag unlock credential。
5. 將 pair 改為 prepare/complete 或至少提供可回滾、可重試的等價交易。

### Milestone B：正式封測安全線

1. 從 profile/bootstrap 移除 `nfc_tag_key`。
2. 修正 phishing victim trust。
3. 定義正式 auth issuance/refresh/revoke 或外部 auth 契約。
4. 加入 profile server-side validation。
5. 加入 report/block/delete 或明確的替代營運流程。
6. 所有寫入 API 加 idempotency 與 request ID。

### Milestone C：容量與維運

1. Bootstrap slim 化與 avatar object storage。
2. Collection/scoreboard pagination + total count。
3. Audit log 查詢與營運後台。
4. OpenAPI contract test、load test 與告警。

---

## 18. 後端與產品需要回覆的決策

請後端工程師或產品負責人逐項確認：

1. 正式 API 是否統一使用 `/v1`？
2. Auth token 由 NFC Battle Worker 發，還是由外部活動登入服務發？
3. Access token 與 refresh token 的有效期限是多少？
4. STAMP 集卡獎是否活動中即可兌換？RANK 是否只在 freeze 後兌換？
5. 一位使用者是否同時只能有一張 active Tag？
6. Tag credential 採 DB 隨機保存，還是由 UID + key version 派生？
7. replacement 後舊 Tag 是否立即 revoke？
8. 列印訂單是否允許一人多次送出？是否有次數或付款限制？
9. 列印原圖保存多久？誰可以下載？
10. Profile avatar 正式契約要 48×48 原圖，還是接受 App 現行 512×512 輸出？
11. 是否同意將 link、card color、emoji array 變成原生欄位？
12. 封鎖是否影響收藏、計分或只影響內容顯示？
13. 帳號刪除時，score/prize/audit 如何匿名化或保留？
14. STAFF 是否要細分權限，例如 TAG_SUPPORT、PRIZE_DESK、PRINT_DESK、SCOREBOARD_ADMIN？

---

## 19. Definition of Done

每一組 API 完成時，請一起交付：

- 更新後的 OpenAPI，包含 request/response/error examples。
- staging 可測 endpoint。
- DB migration 與 rollback 計畫。
- RBAC、idempotency、併發與 validation 測試。
- curl/Postman 範例，但不得把正式 token commit 進 repo。
- App 需要的環境變數與 base URL。
- 錯誤 code 對照表。
- request ID 與 Worker log 查詢方式。
- 資料 retention 與 audit 規則。

OpenAPI、staging 實作與 App contract test 三者一致後，才算完成；只更新其中一份會再次造成目前 `/v1` 這類落差。

---

## 20. 稽核證據索引

後端若要重現本文件的判讀，可從以下位置開始：

| 證據 | 檔案與行號 | 說明 |
|---|---|---|
| API client response 上限 | `lib/services/nfc_battle_api_client.dart:25` | 單一 response 最大 5 MiB |
| API client 支援 method | `lib/services/nfc_battle_api_client.dart:27`、`:35`、`:44` | 目前只有 GET、POST、PATCH |
| Tag credential 來源 | `lib/services/auth_service.dart:266`、`:287`、`:292` | 解鎖他人 Tag 會失敗；只讀目前 profile 的 `nfc_tag_key` |
| Bootstrap | `lib/services/auth_service.dart:308` | App 直接抓完整 collected users |
| 實體收藏 | `lib/services/auth_service.dart:360` | 呼叫 `/collection/scan` |
| Phishing | `lib/services/auth_service.dart:401` | client 同時送 victim 與 attacker |
| 列印 stub | `lib/services/auth_service.dart:478` | 沒有 API，直接回 `null` |
| 兌獎 stub | `lib/services/auth_service.dart:490` | 沒有 API，直接回 `null` |
| Bio metadata marker | `lib/services/card_bio_codec.dart:14` | link/card color 被編入 `HITCON_CARD:v1` |
| Avatar 實際輸出 | `lib/pages/user/my_card_editor_page.dart:158`、`:160`、`:356` | 48×48 logical grid 輸出成 512×512 PNG |
| 列印格式 metadata | `lib/pages/user/my_card_editor_page.dart:1491`、`:1494` | App 準備送出 Evolis/CR80 格式 |
| 列印像素尺寸 | `lib/pages/user/my_card_editor_page.dart:2122`、`:2123` | 638×1011 |
| 現行配對順序 | `lib/pages/user/ntag_pairing_page.dart:141`、`:154`、`:161` | 寫 NDEF -> 上鎖 -> 呼叫 pair API |
| OpenAPI base path | 提供的 `openapi.yaml:113` | 宣告 `https://{devHost}/v1` |
| OpenAPI self key | 提供的 `openapi.yaml:1023` | `nfc_tag_key` 為 per-user 6-byte key |
| OpenAPI avatar 描述 | 提供的 `openapi.yaml:996`、`:1118` | 文件描述為 48×48，與 App 傳輸圖不一致 |
| OpenAPI phishing body | 提供的 `openapi.yaml:1312` | request 同時要求 victim 與 attacker |
| 舊兌獎契約 | `Backend/Readme.md:213`、`:231` | 舊文件曾有 identify/redeem，但已不在目前 OpenAPI |

Staging 探測結果以 2026-07-14 為準；後端部署新版本後，請重新執行 smoke test 並更新本文件的第 3 節。
