# Custom Audio Packs & Quiet Hours (`AUDIO_SYSTEM.md`)

## 1. 功能狀態標記

| 功能 | 狀態 | 實作位置 |
|---|---|---|
| **支援匯入 WAV / MP3 / M4A / AIFF** | **Implemented / Tested** | `UserContentManager.swift`, `AudioPackManager.swift` |
| **10 種事件音效對應**（`gooseHonk`, `gooseLaugh`, `gooseAngry`, `gooseHappy`, `gooseSleep`, `memoDrag`, `memoDrop`, `memeAppearance`, `memeExit`, `interaction`） | **Implemented / Tested** | `AudioPackEvent`, `AudioPlayer.swift`, `NotepadDeliveryTask.swift`, `MemeDeliveryTask.swift` |
| **音效包管理（建立、重新命名、刪除、切換、單一音效預覽/音量/啟用）** | **Implemented / Tested** | `AudioPackManager.swift`, `Phase2SettingsViews.swift` (`AudioPacksPage`) |
| **Quiet Hours（開始/結束時:分、每週星期複選、3 種模式：`fullMute` / `disableHonksOnly` / `keepUISounds`）** | **Implemented / Tested** | `QuietHoursConfig`, `SoundEffectEngine.swift`, `GooseSettings.swift` |
| **Phase 1 Honk Cooldown & Mute 完整保留** | **Implemented / Tested** | `SoundEffectEngine.canPlayVocal`, `AudioPlayer.playEvent`, `HonkTicker` |

## 2. 與第一階段冷卻系統的整合
- 所有由 `AudioPlayer.playEvent(...)` 播放的動物叫聲，無論是來自自訂音效包（`AudioPackManager.shared.playEventSound`）或內建 DSP 合成（`SoundEffectEngine`），皆統一經過 `SoundEffectEngine.shared.canPlayVocal(...)` 閘門（全域冷卻預設 `20s`、單鵝獨立冷卻 `20–40s`、重大事件最小間隔 `2.5s`、睡眠禁叫、Mute 立即停止）。
- Quiet Hours 啟動期間，多隻鵝皆無法繞過靜音規則，時段結束後自動恢復使用者設定。
