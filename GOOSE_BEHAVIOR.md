# Goose Emotion, Energy, Interaction & Prank Presets (`GOOSE_BEHAVIOR.md`)

## 1. Emotion & Energy (0–100)

| 功能 | 狀態 | 說明 |
|---|---|---|
| **7 種情緒狀態**（`Happy`, `Angry`, `Bored`, `Excited`, `Sleepy`, `Curious`, `Mischievous`） | **Implemented / Tested** | `GooseEmotion`, `GoosePersonality.updateEmotion` |
| **Energy 0–100（活動消耗、睡眠恢復 +4.5/s、不永久鎖死）** | **Implemented / Tested** | `GoosePersonality.tick` |
| **情緒影響移動速度與惡作劇倍率** | **Implemented / Tested** | `speedEmotionMultiplier`, `prankMultiplier`, `GooseManager.tickAll` |
| **跨啟動持久化（`goose_states.json`）** | **Implemented / Tested** | `GooseStatePersistence`, `GooseInstance.teardown`, `AppDelegate.applicationWillTerminate` |

## 2. 多鵝社交互動
- 擴充 `SocialInteractionKind`（`GooseInteractionTask.swift`, `GooseInteractionSystem.swift`）：
  - `chasePeer`（Goose Chasing）
  - `greetPeer`（Goose Greeting）
  - `argue`（Goose Fighting）
  - `playTogether`（Goose Playing）
  - `sleepTogether`（Goose Sleeping Together）
  - `stealMeme`（Goose Stealing Meme）
  - `shareMemo`（Goose Sharing Memo）
  - `spectateHolder`（Goose Watching Another Goose）
- 狀態：**Implemented**（所有互動均不搶奪 `GlobalActionCoordinator` `.mouse` / `.window` 鎖）。

## 3. Prank Presets

| Preset / 功能 | 狀態 | 說明 |
|---|---|---|
| **Peaceful / Normal / Mischievous / Chaos Mode** | **Implemented / Tested** | `PrankPresetManager.swift`（Chaos 仍保留 Mouse/Window Lock、Emergency Stop 與 `honkCooldown >= 8s` 安全下限） |
| **自訂 Preset（建立、複製、更新、刪除、切換不覆蓋自訂圖庫/文字庫）** | **Implemented / Tested** | 持久化至 `prank_presets.json`，整合於 `PrankPresetsPage` |
