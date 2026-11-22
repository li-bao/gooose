# Goose Memo Editor (`MEMO_EDITOR.md`)

## 1. 設計與架構

- **核心類別**：`GooseNotepadWindow`（別名 `GooseMemoEditorWindow`），位於 `Goose/Sources/Goose/Windows/GooseNotepadWindow.swift`。
- **視窗樣式**：原生 macOS `NSWindow`（`styleMask: [.titled, .closable, .miniaturizable, .resizable]`，`minSize: 240×170`，`maxSize: 720×640`，原生標題列、陰影、關閉與縮放控制）。
- **層級整合**：依 `GooseSettings.shared.memoAlwaysOnTop` 使用 `.floating` 或 `.normal`，**絕不使用 `.screenSaver`**，確保不遮擋 macOS 系統授權對話框，也不會繼承 Goose Overlay 的滑鼠穿透設定。

---

## 2. 功能狀態標記

| 功能 | 狀態 | 說明 |
|---|---|---|
| 原生視窗外框與可調整大小／移動／關閉 | **Implemented / Tested** | 原生 `NSWindow` `.titled, .closable, .miniaturizable, .resizable` |
| 真正可編輯 `NSTextView`（點擊、選取、編輯、複製、貼上、全選、Undo） | **Implemented / Tested** | `isEditable = true`, `isSelectable = true`, `allowsUndo = true` |
| 統一迷因容器（PNG/JPG/JPEG/WEBP/動畫 GIF + 下方文字說明） | **Implemented / Tested** | 透過 `MemeDeliveryTask` 與 `GooseNotepadWindow(title:body:memeItem:)` 統一呈現 |
| 邊緣平滑拖入動畫（非瞬間跳入、依距離 `1.5–3.0s`、彈性落地） | **Implemented / Tested** | 覆寫 `constrainFrameRect` 於拖曳中允許緊貼邊緣滑入，完成後解鎖互動 |
| 多螢幕支援與 `NSScreen.visibleFrame` 安全邊界 | **Implemented / Tested** | 通過單螢幕、雙螢幕與負座標副螢幕測試 |
| 中途取消／暫停安全關閉視窗與釋放資源鎖 | **Implemented / Tested** | `stop(simulation:)` 即時關閉未完成視窗並釋放 `ResourceLease` |
| 多鵝行為仲裁不重疊建立動畫 | **Implemented / Tested** | 經 `GlobalActionCoordinator` `.window` 互斥鎖仲裁 |
