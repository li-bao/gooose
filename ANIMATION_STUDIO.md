# Meme Animation Studio (`ANIMATION_STUDIO.md`)

## 1. 功能狀態標記

| 功能 | 狀態 | 實作位置 |
|---|---|---|
| **6 種進場動畫**（`dragFromLeft`, `dragFromRight`, `dragFromTop`, `dragFromBottom`, `randomEdge`, `gooseCarry`） | **Implemented / Tested** | `AnimationStudioConfig.swift`, `NotepadDeliveryTask.swift`, `MemeDeliveryTask.swift` |
| **進場參數**（Entry Duration `1.5–3.0s`, Movement Speed, Paper Rotation, Landing Bounce, Drag Offset, Ease Curve） | **Implemented / Tested** | `AnimationStudioSettings`, `MemoEaseCurve` (`easeInOut`, `easeOut`, `springSoft`, `linear`) |
| **6 種退場動畫**（`dragAwayLeft`, `dragAwayRight`, `slideDown`, `fadeOut`, `gooseTakesItAway`, `randomExit`） | **Implemented / Tested** | `GooseNotepadWindow.dismissWithAnimation(style:)` |
| **退場參數**（Exit Duration, Fade Speed, Exit Rotation, Randomize Exit） | **Implemented / Tested** | `AnimationStudioSettings`, `GooseNotepadWindow.swift` |
| **安全即時預覽**（Preview 按鈕不碰系統滑鼠、不搶鎖） | **Implemented / Tested** | `GooseNotepadWindow.showPreview(title:body:memeItem:)` |
| **設定持久化**（`animation_studio.json`） | **Implemented / Tested** | `AnimationStudioStore` |
| **Settings UI 整合**（`Animation Studio` 分頁） | **Implemented** | `Phase2SettingsViews.swift` (`AnimationStudioPage`) |

## 2. 多螢幕與平滑曲線技術說明
- 進場起點與終點皆以 `DisplayManager.shared.visibleFrame(forScreenIndex:fallbackSize:)` 計算，確保無論在主螢幕、擴展右螢幕或負座標左側螢幕，視窗皆緊貼可見邊緣平滑滑入，並依曲線切線調整鵝的前進方向。
- 拖曳中關閉 `isInteractive` 並於 `constrainFrameRect` 放行邊緣座標，徹底防止 AppKit 在第一幀將視窗強制彈回螢幕內造成瞬移。
