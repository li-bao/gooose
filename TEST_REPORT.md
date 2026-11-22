# Super Goose 2.0 — Phase 2 測試報告 (`TEST_REPORT.md`)

> 測試日期：2026-11-22  
> 測試環境：macOS Apple Silicon (`arm64`), Xcode Toolchain (`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`)

---

## 1. 自動化單元與整合測試 (`swift test`)

執行指令：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`

| 測試項目 | 結果 | 耗時 | 涵蓋範圍 |
|---|---|---|---|
| `testBrainDryRun` | **PASSED** | 1.959s | `GooseBrain` 20 次情境決策輸出 |
| `testCoreLogicSelfTest` | **PASSED** | 0.253s | 設定持久化、行為開關、腳印環形緩衝區、排程器睡眠保護 |
| `testDiagnosePermissionsOutputsReport` | **PASSED** | 0.133s | TCC 診斷報告與回復指令輸出 |
| `testPermissionsSelfTest` | **PASSED** | 0.337s | ScreenCapture / AXError 分類、PermissionManager 狀態機 |
| `testPhase1AuditAndFixes` | **PASSED** | 0.696s | 20 次 `NotepadDeliveryTask` 邊緣拖入、全域/單鵝冷卻、睡眠禁叫、Mute、中途取消、`GameTime` 暫停 |
| `testPhase2Features` | **PASSED** | 0.417s | Meme Library、Taunt Library、Memo Editor、Animation Studio (6 種進場動畫 + 多螢幕)、Audio Packs + Quiet Hours、Emotion/Energy、Prank Presets |
| `testUltimateFeaturesSelfTest` | **PASSED** | 0.378s | DSP 合成音、GIF 解碼、UTF-8 繁中/Emoji、ScreenObservationMode |
| **合計** | **7 / 7 PASSED (0 failures)** | **4.172s** | — |

---

## 2. `--selftest-phase2` 詳細檢查結果 (`ALL PASSED`)
- **Meme Library**：PNG 匯入分類 `Gaming`、重複檔案拒絕、搜尋過濾、`manualOnly` 排除自動抽取但允許手動觸發、重載持久化通過。
- **Taunt Library**：新增、複製、停用分類過濾、重載持久化通過。
- **Memo Editor**：`NSTextView.isEditable == true`、文字編輯保留、視窗層級非 `.screenSaver`、支援 `MemeItem` 圖片+文字容器通過。
- **Animation Studio**：設定持久化通過；6 種進場風格（`dragFromLeft`, `dragFromRight`, `dragFromTop`, `dragFromBottom`, `randomEdge`, `gooseCarry`）於雙螢幕負座標環境皆平滑完成。
- **Audio Packs & Quiet Hours**：WAV 匯入自訂音效包、星期與時段過濾啟用通過。
- **Emotion, Energy & Persistence**：情緒與能量（0–100）重載持久化、活動消耗能量、睡眠恢復能量通過。
- **Prank Presets**：4 個內建 Preset、Chaos 安全冷卻下限（`>= 8s`）、自訂 Preset 建立與重載持久化通過。

---

## 3. Apple Silicon `.app` 與 `.dmg` 打包驗證

1. `./scripts/build-app.sh` — **PASSED**（`Build complete! (19.03秒)`，產生並簽署 `dist/Super Goose Desktop.app`）。
2. `./scripts/build-dmg.sh` — **PASSED**（產生 `dist/Super-Goose-Desktop-Apple-Silicon.dmg`，SHA-256: `f9b64b80d4498ffe7920a0da9fa6cda0126716c9156ec3f5a1d037cd7683f456`）。
3. `./scripts/verify-release.sh` — **PASSED**（掛載驗證 `arm64` 執行檔、`Info.plist`、`codesign --verify --deep --strict`、`--diagnose-permissions`、`--brain-dryrun` 與 `shasum -a 256 -c SHA256.txt` 全數 OK）。

---

## 4. 尚未解決的問題與備註
1. **UI 互動實機目視確認**：SwiftUI 設定分頁（`MemeLibraryPage`, `TauntLibraryPage`, `AnimationStudioPage`, `AudioPacksPage`, `PrankPresetsPage`）已完整接線至底層 Store 並通過編譯與整合測試；建議於實體雙螢幕桌面啟動 `.app` 進行最終視覺微調。
2. **工具鏈路徑**：建置時須保持 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` 以載入 `SwiftUIMacros`。
