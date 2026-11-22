# Personal Meme Library & Custom Taunt Library (`MEME_LIBRARY.md`)

## 1. Personal Meme Library

### 狀態標記
- **支援格式（PNG / JPG / JPEG / WEBP / 動畫 GIF）**：**Implemented / Tested**
- **匯入機制（`NSOpenPanel` + 拖放、多選、重複 SHA-256 過濾、大小上限 25MB、ImageIO 解碼驗證）**：**Implemented / Tested**
- **分類系統（8 個預設分類 + 自訂分類 CRUD）**：**Implemented / Tested**
- **單一迷因設定（ID, Name, File Ref, Category, Enabled, ManualOnly, Weight, Usage Count, Last Used, Tags, Security-Scoped Bookmark）**：**Implemented / Tested**
- **收藏庫介面（Grid / List 切換、搜尋、分類篩選、預覽、編輯、排序、刪除、手動觸發）**：**Implemented / Tested**
- **儲存與安全（本機 JSON `UserContent/Settings/meme_library.json`，絕不存入 `UserDefaults`，不執行、不上傳）**：**Implemented / Tested**

### 運作細節
- 檔案實體存放於 `~/Library/Application Support/Super Goose Desktop/UserContent/Memes/`，由 `UserContentManager` 與 `MemeLibraryStore` 同步管理；若檔案被外部刪除或移動，`syncWithContentManager()` 會自動清理失效參照而不崩潰。
- `pickWeightedMeme(category:includeManualOnly:)` 會排除 `enabled == false` 與 `manualOnly == true`（除非手動觸發），並對近期使用過的迷因施加權重懲罰（`< 120s` 乘以 `0.20`、`< 360s` 乘以 `0.55`），使用後更新 `usageCount` 與 `lastUsed`。

---

## 2. Custom Taunt Library

### 狀態標記
- **文字管理（新增、編輯、刪除、複製、預覽、搜尋）**：**Implemented / Tested**
- **分類系統（8 個預設分類 + 自訂分類 + 暫時停用分類 `disabledCategories`）**：**Implemented / Tested**
- **智慧權重選擇（權重 `0.1–5.0` + 近期防重複懲罰）**：**Implemented / Tested**
- **實際串接 Goose 行為（`AgentDirector` 與 `GooseController.deliverNotepadNow` / `deliverTaunt`）**：**Implemented / Tested**

### 運作細節
- 資料保存於 `~/Library/Application Support/Super Goose Desktop/UserContent/Settings/taunt_library.json`。
- `TauntLibraryStore.pickWeightedTaunt(category:)` 確保 Goose 真正使用使用者建立的嘲諷文字，並避開已停用或禁用分類的項目。
