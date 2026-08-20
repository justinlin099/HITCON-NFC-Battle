# 卡片列印站

給 Windows 列印工作站使用的本機網頁工具。它延續 App 現有的 staff 流程：掃描 Code 128 短碼、以 STAFF JWT 向 `GET /staff/print-cards/{token}` 下載原始 PNG、先預覽，再下載套用印卡機偏移校正的 Word `.docx`。

工具跑在 Docker 內，但相機由瀏覽器直接開啟，不需要把相機裝置掛進容器。Word 檔也不會重新渲染、縮放或裁切 PNG；服務只替換校正模板中的 `word/media/image1.png`，完整保留原本的頁面、浮動錨點、圓角與偏移 XML。

## Windows 快速啟動

需求：已安裝並啟動 Docker Desktop，且使用 Linux containers／WSL2 模式。

```powershell
cd CardPrinter
Copy-Item .env.example .env
.\start.ps1
```

開啟 <http://localhost:18080>。

- `.env` 的 `STAFF_JWT` 留白：網頁會顯示密碼欄位；JWT 只留在目前頁面的記憶體，不寫入 `localStorage` 或 `sessionStorage`。
- `.env` 設定 `STAFF_JWT`：頁面不再要求輸入，適合受控的單一工作站。請勿提交含真實憑證的 `.env`；本機 Docker 管理員仍可透過 container metadata 看到環境變數，因此預設的瀏覽器記憶體模式較安全。
- 啟動時會讀取 App 的公開 Remote Config，再建立可攜帶 STAFF JWT 的 API client；頁面「工作站設定」會顯示實際 API origin 與設定來源。`API_BASE_URL` 只是在 Remote Config 暫時無法讀取時使用的可信 production 備援。
- 停止服務：執行 `.\stop.ps1`。

也可以直接使用：

```powershell
docker compose up --build -d --wait --wait-timeout 60
docker compose ps
```

## 使用流程

1. 在瀏覽器允許相機權限，掃描 App 顯示的 Code 128 列印短碼；也可以手動輸入 8–32 字元短碼。
2. 工具從既有 staff API 下載 PNG，並在畫面右側顯示預覽。
3. 確認卡面與直式方向後勾選確認。
4. 按「下載校正 Word」，取得 `hitcon-print-card-{token}.docx`。
5. 用 Windows 版 Microsoft Word 開啟並以原始頁面大小／100% 列印。印表機驅動請關閉「符合頁面」「縮放到紙張」等二次縮放選項。

網路或條碼不可用時，可以用「選擇 PNG」直接載入本機卡面，再產生同樣的 Word 檔。

## 用 USB 舊手機掃描

若筆電鏡頭近距離無法對焦，可以讓 Android 舊手機只負責掃碼，Windows 仍負責卡面核對與 Word 下載。

1. 手機開啟「開發人員選項 → USB 偵錯」，用 USB 接到 Windows，並在手機上允許這台電腦。
2. 使用 `.\start.ps1` 啟動卡片列印站。腳本會同時啟動目前 Windows 使用者的隱藏手機 helper；手機可以在啟動前或啟動後才插入。
3. 在 Windows 網頁按「用手機掃描」。Helper 偵測到這次掃描工作後，才會建立 ADB reverse、喚醒手機並開啟掃描頁，不必輸入配對碼。
4. 若 helper 無法啟動，才使用手動備援：

   ```powershell
   .\connect-phone-scanner.ps1
   ```

手機只會回傳符合格式的 Code 128 token；USB 連線憑證僅能領取掃描工作，不能存取 STAFF JWT、卡面 PNG、Word 檔或主站 API。畫面上的配對碼只保留給 helper／ADB 無法使用時手動備援。

Helper 不會以系統管理員或 Windows Service 執行，因此會沿用目前使用者已授權的 ADB 金鑰。`stop.ps1` 與 `disconnect-phone-scanner.ps1` 會停止 helper，且只移除由本工具建立、目前仍指向 companion port 的 reverse；不會呼叫 `adb reverse --remove-all` 或停止全域 ADB server。腳本只接受一台 USB ADB 手機，Android emulator 不影響選取；若同時接了多台實體 Android 裝置，請先拔除其他裝置。

Helper 狀態可用以下指令查看或控制：

```powershell
.\phone-scanner-helper.ps1 -Action Status
.\phone-scanner-helper.ps1 -Action Stop
```

直接執行 `docker compose up` 只會啟動容器，不會啟動 Windows helper；要使用按鈕自動喚醒手機，請執行 `start.ps1`。若自訂了工作站連接埠，也應由 `start.ps1` 把實際連接埠傳給 helper。

手機使用獨立的 companion listener（Windows loopback `18081`），該 listener 明確不提供 STAFF proxy、設定或 DOCX API。ADB 只把手機的 `localhost:18765` 轉到這個低權限 listener，不會把主站 `18080` 暴露給手機。

## 相機注意事項

- `http://localhost` 與 `http://127.0.0.1` 可在瀏覽器的安全內容規則下使用相機；請優先使用 README 中的 `localhost` URL。
- 純 HTTP 的區網 IP（例如 `http://192.168.x.x:18080`）通常不能取得相機權限。若要讓別台裝置存取，必須在前方配置受信任的 HTTPS reverse proxy／憑證。
- 筆電相機優先要求 1920×1080；鏡頭支援時會套用連續對焦，並顯示重新對焦與縮放控制。手機螢幕太近而模糊時，先拿遠到約 25–40 公分。
- 掃碼優先使用瀏覽器原生 `BarcodeDetector` 的 `code_128`；無結果時會加入中央區域的多尺度離線 ZXing 辨識。掃描成功、切換相機或關閉視窗時都會停止 media tracks。
- 相機無法使用時，手動輸入與本機 PNG 仍可運作。

## 設定

`.env.example` 提供所有設定：

| 變數 | 預設值 | 說明 |
| --- | --- | --- |
| `REMOTE_CONFIG_URL` | `https://game.hitcon2026.online/.well-known/nfc-battle-app-config.json` | App 的公開執行期設定；只接受這個固定 HTTPS 文件，啟動時讀取一次 |
| `API_BASE_URL` | `https://nfc-battle-api.hitcon2026.online` | Remote Config 無法讀取時的 production API 備援 |
| `STAFF_JWT` | 空白 | 選填；空白時由網頁逐次提供 |
| `CARDPRINTER_PORT` | `18080` | Windows loopback port；可在 `.env` 自訂 |
| `CARDPRINTER_COMPANION_PORT` | `18081` | ADB 手機掃描器的獨立 Windows loopback port |
| `CARDPRINTER_MAX_PNG_BYTES` | `10485760` | PNG 上限，預設 10 MiB |
| `CARDPRINTER_ALLOWED_API_HOSTS` | 空白 | 開發用的明確 host allow-list，逗號分隔；設定後會略過 Remote Config，使用 `API_BASE_URL` |
| `CARDPRINTER_ALLOW_HTTP_API` | `false` | 僅搭配明確 allow-list 的本機開發 API 使用 |
| `CARDPRINTER_ALLOWED_WEB_HOSTS` | 空白 | HTTPS reverse proxy 使用的額外瀏覽器 Host；一般本機使用請留白 |

Remote Config 請求不帶 STAFF JWT／Cookie，限制 4 秒與 16 KiB，且拒絕 redirect。遠端選出的 API 套用與 App 相同的規則：只接受 `hitcon2026.online` 或其子網域的 HTTPS／443 URL，以及不含歧義路徑的安全 base path；實際卡面下載也會拒絕 30x redirect，避免 STAFF JWT 被轉送。服務不會記錄 Authorization header，access log 會遮蔽列印 Token。

## 校正模板

模板頁面是直式 CR80，約 `54.8922 × 86.0072 mm`。圖片框約 `52.6521 × 83.2026 mm`，相對幾何置中刻意向右約 `0.2028 mm`、向上約 `0.3969 mm`，並保留 Word 的 `roundRect` 圓角裁切。

詳細 OOXML 數值與維護規則見 [`docs/template-layout.md`](docs/template-layout.md)。模板與 manifest 在：

```text
app/templates/card-template.docx
app/templates/card-template-manifest.json
```

服務啟動時會驗證整份模板、`document.xml` 與 relationship XML 的 SHA-256；任何位置或關係被意外修改都會拒絕啟動。

## 測試與本機開發

CardPrinter runtime 只使用 Python 3.12 standard library，不需要 `pip install`。

```powershell
cd CardPrinter
python -m unittest discover -s tests -v
python -m app.server
```

容器驗證：

```powershell
docker compose config --quiet
docker compose build
docker compose up -d --wait --wait-timeout 60
Invoke-RestMethod http://localhost:18080/healthz
Invoke-RestMethod http://localhost:18081/healthz
```

測試涵蓋 token／API host policy、JWT header、20 秒 timeout、10 MiB streaming cap、PNG signature／IHDR CRC／尺寸／比例、DOCX 只替換圖片 part、模板 checksum、HTTP 錯誤對應、USB 手機自動連線與每張卡的一次性 capability，以及 companion listener 的權限隔離。

## 來源與第三方元件

- App staff 行為參考 `App/hitcon_nfc_battle/lib/pages/admin/admin_print_cards_page.dart` 與 `lib/services/auth_service.dart`。
- App 列印 PNG 目前是直式 `1276 × 2022`，本工具會原樣嵌入而不重採樣。
- 相機 fallback 使用 `@zxing/browser` 0.2.1（MIT）；授權檔位於 `app/static/vendor/zxing-browser.LICENSE.txt`。
