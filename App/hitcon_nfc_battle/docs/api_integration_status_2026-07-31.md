# HITCON NFC Battle API / App 整合狀態

> 稽核日期：2026-07-31  
> API 契約：後端提供的 `openapi.yaml`，OpenAPI 3.0.3 / API 1.0.0  
> App：Flutter 專案目前工作目錄  
> Staging：`https://nfc-battle-staging.hitcon2026.online`

## 結論

新版 OpenAPI 共有 20 個 HTTP operations。這次修改後：

- 20 個都已由 App 流程使用。
- 原本的列印、STAFF 兌獎、STAFF 解鎖三個 stub 已改成正式 API。
- 管理者頁面已加入 STAFF 列印下載、指定使用者配卡，以及排行榜凍結控制。
- 收藏一般刷新已改用 `/users/batch`，bootstrap 只作為失敗回退。

## 已接上的 API

| Method | Path | App 使用位置 |
|---|---|---|
| GET | `/users/me` | 登入、session restore、自己資料、配對狀態、收藏索引 |
| PATCH | `/users/me` | Setup 與我的卡片編輯器 |
| GET | `/users/me/prize` | 收藏頁兌獎按鈕，排行榜凍結後顯示結果 |
| GET | `/users/me/bootstrap` | 收藏快取救援與 batch 失敗回退 |
| POST | `/users/batch` | 已收藏使用者 profile 增量刷新，最多每批 100 人 |
| GET | `/users/{user_id}` | 查看其他使用者 profile |
| GET | `/users/{user_id}/collection` | 查看其他使用者收藏 |
| POST | `/tags/pair` | 使用者配對自己的實體 Tag |
| POST | `/collection/scan` | 驗證 physical UID 並收藏卡片 |
| POST | `/collection/phishing` | 非實體掃描的連結事件 |
| GET | `/missions/stamp` | 集卡獎進度 |
| GET | `/scoreboard` | 排行榜與下拉刷新 |
| POST | `/print-cards` | 以 multipart/form-data 上傳 CR80 PNG，取得 `short_token` |
| GET | `/staff/print-cards/{short_token}` | STAFF 掃描或輸入 Code 128 token、預覽並下載 PNG |
| POST | `/staff/prize-claims` | STAFF 掃會眾 Tag 後核銷凍結獎項 |
| POST | `/staff/nfc-unlock-code` | STAFF 以 Tag URL user ID 加 physical UID 取得解鎖碼 |
| POST | `/staff/pair_user_tag` | STAFF 指定使用者、寫入 NDEF、伺服器配對並鎖定 NTAG |
| POST | `/staff/unpair_user_tag` | STAFF 掃描實體 Tag，依 user ID 與 physical UID 解除伺服器配對 |
| GET | `/staff/scoreboard_status` | 管理頁查詢凍結狀態與 cutoff 資訊 |
| POST | `/staff/freeze_scoreboard` | 管理頁二次確認後凍結排行榜 |
| POST | `/staff/resume_scoreboard` | 管理頁二次確認後恢復排行榜 |

列印畫面會把 `short_token` 同時當作本機收件編號與 Code 128
條碼內容。後端目前只回傳 `short_token`，沒有獨立的 order ID。

## API 有，但 App 尚未接上的功能

目前 OpenAPI 內沒有尚未接進 App 的 operation。

排行榜三個 danger operations 不會把全域 `STAFF_DANGER_TOKEN` 內嵌或保存
在 release App。操作人員每次進入控制頁都要手動輸入，token 只存在該頁面的
記憶體中，離開頁面即清除；freeze 與 resume 也都有二次確認。正式上線仍建議
後端改用短效、操作限定且可稽核的管理憑證。

### 已接 endpoint 仍未使用的契約能力

- `GET /users/{user_id}` 的 `profile_version` / `collection_version`
  query 尚未送出；目前單一使用者頁仍會拿完整 response。
- `GET /users/{user_id}/collection` 的 `collection_version` unchanged
  流程尚未使用。
- `/scoreboard` 支援 offset/limit，但 UI 目前只讀第一批 50 人，沒有載入更多。
- 一般使用者排行榜只顯示比賽結果；完整 `freeze_id`、cutoff 與 timeout
  會顯示在管理者排行榜控制頁。

## App 有，但 OpenAPI 沒有的功能

### 真正需要後端補契約

| 功能 | App 現況 | API 缺口 |
|---|---|---|
| 登入 token 發行 | 可貼上 JWT、掃 QR、從圖片辨識 QR、開啟 email App | 沒有 login exchange、email magic link、refresh、revoke、logout/revocation 契約 |
| 列印訂單生命週期 | App 會顯示收件 token，指示使用者到攤位付款列印 | API 只有上傳與 STAFF 下載，沒有 user history、付款、列印狀態、取消、重試或保存期限查詢 |

`link` 與 `card_color` 繼續由 App 編碼在 bio marker，不要求
後端新增原生欄位。

### 合理的本機功能，不需要後端 API

- 48x48 圖片繪製器、圖片裁切、預設像素大頭貼。
- 主題、繁中／英文、頁面動畫與卡片 3D 拖曳。
- JSON 檔案／剪貼簿備份還原；內容是本機 collection cache。
- NFC NDEF 寫入、Tag 密碼鎖定與實際解鎖指令；server 只負責配對與提供 credential。
- Deep link 接收、Android NFC intent、iOS 重新掃描提示。
- 條碼截圖／儲存、開啟外部連結前的安全確認。
- Setup 完成狀態與尚未配對 Tag 的本機提醒。
- 管理員將全新 Tag 寫成固定空白 App URL；或透過 STAFF 配卡流程直接指定
  使用者、寫入正式 URL、呼叫 API 並鎖卡。
- App 每次冷啟動與回到前景時，會從
  `https://game.hitcon2026.online/.well-known/nfc-battle-app-config.json`
  檢查 API base URL。遠端失敗時使用上次成功值，再回退到打包預設值。
  只接受 `hitcon2026.online` 旗下的 HTTPS API host。
  同一份設定的 `allow_user_tag_unlock` 可隨時停用一般使用者解鎖
  Tag 的按鈕，不影響 STAFF 管理解鎖。

## 契約與 staging 不一致

OpenAPI `servers` 仍宣告：

```text
https://{devHost}/v1
```

2026-07-31 不帶憑證的唯讀 route probe 結果：

- `GET https://nfc-battle-staging.hitcon2026.online/users/me` 回 `401`
  ，代表根路徑 route 存在。
- `GET https://nfc-battle-staging.hitcon2026.online/v1/users/me` 回 `404`
  ，代表 `/v1` route 不存在。
- 新接的 `/users/batch`、`/users/me/prize`、`/print-cards`、
  `/staff/prize-claims`、`/staff/nfc-unlock-code` 不帶 JWT 均回 `401`
  而非 `404`，確認新版 routes 已部署。此 probe 沒有寫入資料。
- 本次新增的 `/staff/print-cards/{short_token}`、`/staff/pair_user_tag`、
  `/staff/scoreboard_status`、`/staff/freeze_scoreboard` 與
  `/staff/resume_scoreboard` 不帶憑證也都回 `401`，同樣確認 routes
  與授權層存在；沒有執行真正的配卡或排行榜狀態變更。

App 暫時繼續使用根路徑。後端應修正 OpenAPI server URL，或真的部署
`/v1` 並安排 App 遷移，否則 generated client 會全部打錯路徑。

## 建議後續順序

1. 用 STAFF 測試帳號與實體 NTAG 完成配卡、解鎖、再配對的端到端測試。
2. 用實際列印訂單條碼驗證 STAFF PNG 下載與 Evolis 工作站流程。
3. 將 scoreboard danger operations 改用短效 challenge token，並補 audit log。
4. 補正式登入／refresh／revoke 契約。
5. 補其他使用者 cache version query 與排行榜載入更多。
