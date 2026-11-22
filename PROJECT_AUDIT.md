# Super Goose Desktop — Phase 1 專案稽核與修復報告 (`PROJECT_AUDIT.md`)

> 稽核日期：2026-11-22  
> 適用版本：`Goose` Swift Package（`swift-tools-version: 6.2`，macOS 26+，Zero third-party SPM dependencies）

---

## 1. 專案架構清單 (Project Architecture Inventory)

專案根目錄（`super-goose`），主程式碼位於 `Goose/Sources/Goose/`，測試位於 `Goose/Tests/GooseTests/`，打包腳本位於 `scripts/`。

### 模組總覽

| 模組 | 檔案 | 主要職責 |
|---|---|---|
| **進入點** | `main.swift` | CLI 測試旗標分派（`--selftest-*`, `--diagnose-permissions`, `--brain-dryrun`, `--browser-demo`）與 GUI `NSApplication`（`.accessory`）啟動 |
| **App 與視窗管理** | `AppDelegate.swift`, `OverlayWindow.swift`, `DisplayManager.swift`, `GooseController.swift`, `NotificationManager.swift` | `NSStatusItem` 選單列、透明點擊穿透 `OverlayWindow`（`.screenSaver` 層級）、多螢幕座標轉換與 `visibleFrame` 追蹤、執行狀態控制平面（`running/paused/hidden/stopped`）、系統通知 |
| **物理與多鵝引擎** | `GooseManager.swift`, `GooseInstance.swift`, `GooseSimulation.swift`, `GoosePersonality.swift`, `GooseInteractionSystem.swift`, `GameTime.swift`, `FootMark.swift`, `Easings.swift`, `Deck.swift`, `SamMath.swift`, `Vec2Math.swift` | 最多 5 隻鵝的生命週期、位置/速度/方向/步態模擬、64 格（16–128 可調）泥腳印環形緩衝區、動態疲勞/無聊/閃避個性、同儕社交互動 |
| **SpriteKit 場景** | `GooseScene.swift`, `GooseArt.swift`, `GooseRig.swift`, `GooseColors.swift`, `DesktopMessOverlay.swift`, `HeadphonesNode.swift`, `HeartParticles.swift`, `MusicNoteParticles.swift` | 骨架線條繪製鵝身、虛擬桌面雜物覆蓋層（最多 24 個，純視覺不碰真實檔案）、耳機/愛心/音符粒子、嘲諷氣泡與按住 ESC 驅逐進度條 |
| **AI 與排程** | `AgentDirector.swift`, `BehaviorScheduler.swift`, `GlobalActionCoordinator.swift`, `GooseBrain.swift`, `GooseAction.swift`, `GooseSceneEffects.swift`, `HonkTicker.swift`, `ChillingTicker.swift`, `Personality.swift`, `SettingsAwareLLM.swift`, `FoundationModelClient.swift`, `OpenAIClient.swift`, `LLMProvider.swift`, `LLMRouter.swift` | 感知→決策→任務排程迴圈、全域滑鼠與視窗互斥鎖（`ResourceLease`）、Apple 裝置端 Foundation Models 與 opt-in OpenAI 整合、隨機鳴叫與 Spotify 聽歌排程 |
| **螢幕感知** | `PerceptionEngine.swift`, `ScreenCapturer.swift`, `OCRRecognizer.swift`, `AccessibilityProbe.swift`, `FullscreenMonitor.swift`, `ContentSharingPickerController.swift`, `ContextSnapshot.swift`, `ScreenObservationMode.swift` | 前景 App 與視窗幾何讀取、全螢幕遊戲／簡報偵測、本機 `ScreenCaptureKit` 截圖與 `Vision` OCR |
| **惡作劇任務** | `GooseTask.swift`, `WanderTask.swift`, `NapTask.swift`, `DeepSleepTask.swift`, `ChillingTask.swift`, `NabMouseTask.swift`, `MouseChaseTask.swift`, `NotepadDeliveryTask.swift`, `MemeDeliveryTask.swift`, `DragWindowTask.swift`, `WindowPrankTask.swift`, `WindowPeekTask.swift`, `FakeErrorTask.swift`, `DesktopMessTask.swift`, `GooseTheftTask.swift`, `BrowseTask.swift`, `GooseInteractionTask.swift` | 17 種行為任務，涵蓋漫步、睡眠、搶滑鼠、拖入便條與迷因、推視窗、偷虛擬圖示、假錯誤視窗等 |
| **原生浮動視窗** | `GooseNotepadWindow.swift`, `MemeWindow.swift`, `FloatingWindow.swift`, `FakeErrorWindow.swift`, `RealBrowserWindow.swift` | 邊緣拖入的互動式便條紙、PNG/JPG/GIF 迷因視窗、相片視窗、假錯誤警告、只允許 `https://` 的無痕 `WKWebView` |
| **音效系統** | `AudioPlayer.swift`, `SoundEffectEngine.swift`, `SoundSynthesis.swift`, `SpotifyController.swift` | 程序化 DSP 鴨叫/鵝叫/腳步/滑紙合成、`AVAudioEngine` 6 通道混音與音高變化、自訂音效載入、AppleScript Spotify 控制 |
| **權限、輸入與內容** | `PermissionManager.swift`, `PermissionDiagnostics.swift`, `PermissionModels.swift`, `EscQuitMonitor.swift`, `GlobalHotkeyManager.swift`, `UserContentManager.swift`, `PhotoLibrary.swift` | TCC 螢幕錄影與輔助使用即時驗證、Carbon 全域快捷鍵、ESC 1.5 秒退出偵測、`Application Support/.../UserContent` 檔案監看 |
| **設定與 UI** | `GooseSettings.swift`, `L10n.swift`, `SettingsView.swift`, `SettingsComponents.swift`, `ContentManagerViews.swift`, `ControlCenterView.swift`, `PermissionCenterView.swift`, `SwiftUIWindowController.swift` | `UserDefaults` schema v5 持久化、英/繁中在地化、9 分頁設定介面、控制中心與權限中心 |
| **資源與建置設定** | `Resources/Sprites/Goose`, `scripts/build-app.sh` | 無第三方套件依賴；`LSUIElement = true`、`LSMinimumSystemVersion = 26.1`、Bundle ID `com.pkrutaa.supergoosedesktop`、僅在 `externalAIOptIn == true` 時連線 `api.openai.com` |

---

## 2. 發現的 Bug 與根本原因 (Discovered Bugs & Root Causes)

### A. 音效與 Honking 過於頻繁
1. **每步走路都觸發鴨叫 (`GooseManager.swift:52`)**：`instance.simulation.onFootLand` 被直接綁定到 `scene?.playSoundEvent(.pat)`，導致每隻鵝每秒踏步 5–10 次時都在播放 `happyQuack`（與撫摸愛心共用事件），多隻鵝時極度吵雜。
2. **缺少全域與單鵝 Honk 冷卻、睡眠防護與防疊加 (`SoundEffectEngine.swift`, `AudioPlayer.swift`, `HonkTicker.swift`)**：
   - `HonkTicker` 在 `NapTask`/`DeepSleepTask` 睡眠期間仍定時播放音效，且未檢查 `FullscreenMonitor`。
   - 缺乏全域 Honk 冷卻、每隻鵝獨立冷卻與同時疊加保護；`NotepadDeliveryTask` / `MemeDeliveryTask` 落地時同時觸發 `.notepadLand` 與 `.prank` 雙重音效。
   - 缺少 `RandomHonkFrequency`（Off/Low/Medium/High）與 `HonkCooldown` 設定項目；`AudioPlayer` 未提供 `stopAll()` 供 Mute / Pause / Quit 即時中斷。

### B. 嘲諷便條／迷因邊緣拖入動畫不自然
1. **視窗從螢幕外瞬間跳入畫面 (`NotepadDeliveryTask.swift`, `MemeDeliveryTask.swift`)**：
   - `beginDrag` 將視窗設於 `edgeGlobal.x - windowSize.width - 30`（完全在螢幕外），但下一幀 `tickDrag` 立刻將視窗中心對齊位於 `minX + 10` 的鵝身中心，造成便條第一幀瞬間從螢幕外「瞬移」進畫面一半，且全程倒退拖行（未更新 `simulation.direction` 沿切線朝前）。
   - 使用全螢幕外框而非 `NSScreen.visibleFrame`（忽略 Dock 與選單列），且未在拖動過程中鎖定互動、未在動畫結束時做彈性落地放置。
   - `stop()` 未清理拖動到一半的視窗，Pause 或搶佔時視窗會半掛在螢幕邊緣。

### C. 效能、並行、記憶體與生命週期問題
1. **每幀約 240 次跨程序 Accessibility IPC (`FullscreenMonitor.swift` + `GooseScene.swift:344`)**：`GooseScene.update` 每幀讀取 `FullscreenMonitor.shared.recommendedFPS`，觸發 `AccessibilityProbe.frontmostExternalWindow()` 執行 4 次同步 `AXUIElementCopyAttributeValue` IPC。
2. **非同步 `Task` 強持有 `self` 形成無限背景迴圈 (`AgentDirector.swift`, `HonkTicker.swift`, `ChillingTicker.swift`)**：三個類別皆缺少 `deinit`，且迴圈中直接呼叫 `await self?.loop()` 或缺少 `guard let self else { return }`，被釋放時會成為永久背景迴圈。
3. **`ChillingTicker` 雙任務競態 (`ChillingTicker.swift`)**：`baseTask` 與 `watchTask` 可同時通過 `isBusy` 檢查並在 `await` 後覆蓋彼此的 `ChillingTask`。
4. **`FakeErrorTask` 未取消背景任務 (`FakeErrorTask.swift`)**：任務被搶佔後仍會完成 LLM 生成並強行 `setTask(WanderTask())`。
5. **`EscQuitMonitor` 每秒建立 60 個 `Task` 與未停止的 `Timer` (`EscQuitMonitor.swift`)**：重複 `start()` 會洩漏舊 `Timer`，且無 `deinit`。
6. **`ControlCenterView` 關閉後 0.5 秒 `Timer` 仍永久運作 (`ControlCenterView.swift`)**。
7. **`GooseScene.willMove(from:)` 未停止 `musicNotes` / `tauntHideWork` / 視窗與音訊**。
8. **`AppDelegate.applicationWillTerminate` 清理不完整**，未停止 `escMonitor`、音訊與浮動視窗。

### D. 多螢幕座標、狀態與崩潰風險
1. **多螢幕座標混用**：`DeepSleepTask`、`NapTask`、`MouseChaseTask` 直接將 `NSEvent.mouseLocation`（全域 Cocoa 座標）與 `simulation.position`（Scene 座標）比較；`GooseScene.attachDraggedWindow` / `updateDraggedWindowPosition` 未將 Scene 座標轉為 Cocoa 全域座標；`RealBrowserWindow.slideIn()` 忽略 `screen.origin`；`GooseInteractionSystem.flockGather` 使用 union rect 而非 `DisplayManager.randomVisiblePoint`。
2. **`ClosedRange` 潛在執行期崩潰**：`DesktopMessTask`、`GooseTheftTask`、`FakeErrorWindow` 在小螢幕或未初始化尺寸下可能產生 `lowerBound > upperBound` 致命錯誤。
3. **Pause／Hide／GameTime 不同步**：`GameTime` 未隨暫停凍結，恢復後腳印與計時器瞬間跳變；`pauseAll()` 在 `.hidden` 狀態會錯誤顯示遮罩；`hideAll()` 未停止音效；`toggleAllPranks()` 未關閉 Meme/Notepad 視窗。
4. **其他核心邏輯 Bug**：
   - `PerceptionEngine` 在無 OCR 變更或關閉截圖時直接回傳舊 `ContextSnapshot`，導致 `elapsedOnApp` 與 `idleSeconds` 永久凍結。
   - `SettingsAwareLLM.activeProviders()` 未檢查 `apple.status.isReady`。
   - `OpenAIClient` 對非推理模型（如 `gpt-4o-mini`）無條件傳送 `reasoning_effort: "low"`。
   - `BehaviorScheduler` 允許同優先權任務互相搶佔，且漏掉 `NotepadDeliveryTask` / `MemeDeliveryTask` 的視窗鎖定檢查。
   - `GooseBrain` 第 74 行 `??` 與 `+` 運算子優先序錯誤、與 `AgentDirector` 的 `recentActions` 鍵值不匹配。
   - `PermissionManager` 在同一次啟動內 Live Capture 成功後，下次切換回 App 時會被 `screenPreflightAtLaunch` 覆寫回 `.restartRequired`；`.systemContentPicker` 模式錯誤要求 TCC 螢幕錄影權限。
   - `UserContentManager` `ctx.makeImage()!` 強制解包風險與 `scheduleReload()` MainActor 隔離問題。
   - `MemeWindow` 尚未顯示時 GIF 計時器會永久中止。
   - `GooseTests.runGoose` 先 `waitUntilExit()` 再讀 pipe 的死鎖風險。

---

## 3. 修復內容與修改檔案 (Fixes & Modified Files)

### 重點架構與功能修復
1. **平滑邊緣拖入便條／迷因動畫 (`NotepadDeliveryTask.swift`, `MemeDeliveryTask.swift`, `GooseNotepadWindow.swift`, `DisplayManager.swift`)**：
   - 新增 `DisplayManager.visibleScreenFrames` 與 `visibleFrame(forScreenIndex:fallbackSize:)`，精確對應多螢幕 `NSScreen.visibleFrame`。
   - 便條與迷因改為從可見螢幕邊緣平滑進入（`startOriginX` 緊貼螢幕邊緣，完全消除瞬移），沿平滑 `cubicEaseInOut` 二次貝茲曲線進入目標區域（依距離自適應 `1.5–3.0s`），搭配輕微旋轉（±2.5°）與上下晃動重量感，鵝朝切線方向前進拉動。
   - 落地時播放 0.24s 彈性放置動畫（`settling` 階段），動畫完成後才呼叫 `win.setInteractive(true)` 允許使用者閱讀、選字與操作。
   - `stop()` 中途取消／暫停時會立即重設外觀並關閉未完成的拖動視窗；全程最多僅觸發一次 `.delivery` 鳴叫。
2. **音效冷卻與防吵雜系統 (`GooseSettings.swift`, `SoundEffectEngine.swift`, `AudioPlayer.swift`, `GooseManager.swift`, `HonkTicker.swift`, `SettingsView.swift`, `L10n.swift`)**：
   - 修正 `onFootLand` 改播 `.tinyFootstep` / `.runningFootstep` 腳步聲而非 `.pat` 鴨叫；`onBite` 改播 `.beakPeck`。
   - 新增全域冷卻（預設 `20s`，範圍 `5–90s`）、單鵝獨立冷卻（`max(20, min(40, honkCooldown * 1.4))`）、重大事件最小間隔（`2.5s`）與防疊加鎖定；睡眠狀態嚴格禁止一般隨機叫聲；`muteGoose` / `masterSoundEnabled = false` / `pauseAll` / `hideAll` / `emergencyStop` / `quit` 均立即呼叫 `stopAll()`。
   - 新增 `RandomHonkFrequency`（預設 `.low`）與 `HonkCooldown` 設定並完整綁定至 `AudioPage` 與 `UserDefaults`（schema v5）。
3. **穩定性與 Bug 修復（共修改 47 個檔案）**：
   - `Goose/Sources/Goose/AI/`: `AgentDirector.swift`, `BehaviorScheduler.swift`, `ChillingTicker.swift`, `GooseBrain.swift`, `GooseSceneEffects.swift`, `HonkTicker.swift`, `OpenAIClient.swift`, `SettingsAwareLLM.swift`
   - `Goose/Sources/Goose/App/`: `AppDelegate.swift`, `DisplayManager.swift`, `GooseController.swift`
   - `Goose/Sources/Goose/Audio/`: `AudioPlayer.swift`, `SoundEffectEngine.swift`
   - `Goose/Sources/Goose/Content/`: `UserContentManager.swift`
   - `Goose/Sources/Goose/Engine/`: `GameTime.swift`, `GooseInteractionSystem.swift`, `GooseManager.swift`, `GoosePersonality.swift`, `GooseSimulation.swift`
   - `Goose/Sources/Goose/Input/`: `EscQuitMonitor.swift`, `GlobalHotkeyManager.swift`
   - `Goose/Sources/Goose/Perception/`: `FullscreenMonitor.swift`, `PerceptionEngine.swift`
   - `Goose/Sources/Goose/Permissions/`: `PermissionManager.swift`
   - `Goose/Sources/Goose/Scene/`: `GooseScene.swift`, `HeadphonesNode.swift`
   - `Goose/Sources/Goose/Settings/`: `GooseSettings.swift`, `L10n.swift`
   - `Goose/Sources/Goose/Tasks/`: `DeepSleepTask.swift`, `DesktopMessTask.swift`, `FakeErrorTask.swift`, `GooseTheftTask.swift`, `MemeDeliveryTask.swift`, `MouseChaseTask.swift`, `NabMouseTask.swift`, `NapTask.swift`, `NotepadDeliveryTask.swift`, `WanderTask.swift`
   - `Goose/Sources/Goose/Tools/`: `SelfTest.swift`
   - `Goose/Sources/Goose/UI/`: `ControlCenterView.swift`, `SettingsView.swift`
   - `Goose/Sources/Goose/Windows/`: `FakeErrorWindow.swift`, `GooseNotepadWindow.swift`, `MemeWindow.swift`, `RealBrowserWindow.swift`
   - `Goose/Sources/Goose/main.swift`
   - `Goose/Tests/GooseTests/GooseTests.swift`

---

## 4. 測試結果 (Test Results)

### `swift test` 完整測試結果
執行指令：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
- `testBrainDryRun` — **PASSED** (2.669s)
- `testCoreLogicSelfTest` — **PASSED** (0.253s)
- `testDiagnosePermissionsOutputsReport` — **PASSED** (0.136s)
- `testPermissionsSelfTest` — **PASSED** (0.361s)
- `testPhase1AuditAndFixes` — **PASSED** (0.748s)
- `testUltimateFeaturesSelfTest` — **PASSED** (0.394s)
- **總計：6 tests, 0 failures (4.561s)**

### `--selftest-phase1` 詳細驗證項目 (`ALL PASSED`)
- `randomHonkFrequency` 預設 `.low`、`honkCooldown` 預設 `20s`，重載 `UserDefaults` 持久化通過
- 全域冷卻（+2s 阻擋第 2 隻鵝、+21s 放行第 2 隻鵝）、單鵝獨立冷卻（+21s 仍阻擋第 1 隻鵝）、睡眠禁止隨機叫聲、重大事件防連續疊加（+3s 允許、+4s 阻擋）、`muteGoose` 全靜音皆通過
- **連續 20 次 `NotepadDeliveryTask` 邊緣拖入動畫測試**（涵蓋 `1440x900`、雙螢幕 `1920x1080 + 2560x1440`、負座標左側副螢幕 `-1920x0`）：全部 20 次平滑完成無瞬移、無卡住（`maxStep=43.9px`）、拖曳中 `isInteractive == false`、完成後解鎖互動，且總鳴叫次數 `totalHonks=20`（每次至多 1 次）
- 拖曳中途取消安全關閉視窗與釋放 `ResourceLease` 通過
- `GameTime` 暫停期間時鐘凍結驗證通過

### Release 建置
執行指令：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build -c release --arch arm64`
結果：**`Build complete! (18.37秒)`**（Exit code 0，無任何編譯錯誤）。

---

## 5. 尚未解決的問題與後續建議 (Remaining Items)

1. **工具鏈路徑環境**：本機預設 `xcode-select` 指向 `/Library/Developer/CommandLineTools`，編譯 SwiftUI Macro 需指定 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`（或執行 `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`）。
2. **實體多螢幕與桌面 GUI 互動目視確認**：本次自動化測試已涵蓋負座標／雙螢幕／單螢幕模擬與 20 次連續動畫軌跡驗證；建議實際啟動 `.app` 進行實體雙螢幕桌面拖曳與聲音體感微調。
3. **Phase 2 預留項目**：使用者自訂迷因／嘲諷內容編輯器強化與自訂全域快捷鍵錄製 UI 將於下一階段處理。
