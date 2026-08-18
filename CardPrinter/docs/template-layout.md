# 校正 Word 模板版面契約

`app/templates/card-template.docx` 是印卡機補償後的權威模板。產生列印文件時只能替換 `word/media/image1.png` 的 bytes，不得用 `python-docx`／Word API 重新插入圖片，也不得重算位置。

## 頁面

- 單一 portrait section。
- `w:pgSz`: `w=3112`, `h=4876` twips，約 `54.8922 × 86.0072 mm`。
- 上／右／下／左 margin 全為 `57` twips，約 `1.0054 mm`。
- header `851` twips、footer `992` twips、gutter `0`。

## 圖片 anchor

- Part：`word/media/image1.png`。
- Relationship：`rId6`。
- Drawing：唯一的 `wp:anchor`，`behindDoc=1`、`layoutInCell=1`、`allowOverlap=1`。
- Horizontal：`relativeFrom=margin`、`posOffset=11430` EMU（`0.3175 mm`）。
- Vertical：`relativeFrom=paragraph`、`posOffset=0`。
- Extent：`cx=1895475`, `cy=2995295` EMU，約 `52.6521 × 83.2026 mm`。
- 實際頁邊餘量：約 left `1.3229 mm`、top `1.0054 mm`、right `0.9172 mm`、bottom `1.7992 mm`。
- 相對幾何置中：刻意向右約 `0.2028 mm`、向上約 `0.3969 mm`。
- Geometry：`roundRect`，`adj=4484`；圓角是 Word shape 裁切，不是 PNG alpha。
- `a14:useLocalDpi=0`，實體顯示尺寸由固定 extent 決定。
- 無 `a:srcRect`，不得額外裁切或重採樣。

`distL=distR=114300` EMU 是 tight-wrap 的文字距離，不是圖片定位值；不可把它誤算成校正 offset。

## 輸入 PNG

- 只接受 PNG、portrait、與模板相近的卡片比例。
- 現行 App 輸出 `1276 × 2022`，可直接使用。
- 預設最大 10 MiB、單邊最大 20,000 px、總像素最大 50 MP。
- 服務驗證 PNG signature、IHDR 長度與 CRC；不修改來源 bytes。

## 不變性檢查

模板 SHA-256：

```text
B78877FC7E7F2B8EA8413EC727C44E71DE0B6066576D8C14697E3DADDEFB01A1
```

關鍵 preserve-only parts：

| Part | SHA-256 |
| --- | --- |
| `word/document.xml` | `F8A25F61771A5CF1C91EF5CD0EEB45F2FBF557295A03FEAE9B282FD38D4046A7` |
| `word/_rels/document.xml.rels` | `8D7F9080612B38A10FB4240DB44136FB44DD66C7ABF6CC68A314FDAB2E57FC12` |

每份輸出都必須滿足：

1. 上述兩個 XML parts 與模板 byte-identical。
2. 所有非 `word/media/image1.png` parts 解壓後與模板 byte-identical。
3. 仍只有一個 anchor、一個 `rId6` 圖片 relationship 與相同 section geometry。
4. 產生後以 Word／DOCX renderer 檢查唯一頁面，確認無 clipping、位移或縮放。
