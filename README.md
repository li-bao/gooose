# Super Goose Desktop

A native macOS desktop pet and prank engine written in **Swift 6.2**, **AppKit**, **SwiftUI**, and **SpriteKit** for **Apple Silicon (`arm64`)**. Inspired by Sam Chiet's *Desktop Goose*, Super Goose Desktop combines multi-goose simulation, smooth edge-dragged notes and memes, procedural sound synthesis, a full customization studio, and a macOS TCC Permission Center.

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Highlights](#2-highlights)
3. [Feature List](#3-feature-list)
4. [Mouse Chase & Bite/Grab Interaction](#4-mouse-chase--bitegrab-interaction)
5. [Multi-Goose Interaction](#5-multi-goose-interaction)
6. [Dynamic Windows](#6-dynamic-windows)
7. [Custom Memes & Sarcastic Taunts](#7-custom-memes--sarcastic-taunts)
8. [Audio System](#8-audio-system)
9. [Settings Features](#9-settings-features)
10. [Multi-Screen Support](#10-multi-screen-support)
11. [macOS Permissions](#11-macos-permissions)
12. [System Requirements](#12-system-requirements)
13. [Apple Silicon Compatibility](#13-apple-silicon-compatibility)
14. [Installation](#14-installation)
15. [Development & Build Instructions](#15-development--build-instructions)
16. [Known Limitations](#16-known-limitations)
17. [Version Information](#17-version-information)
18. [繁體中文使用說明 (Traditional Chinese Guide)](#繁體中文使用說明-traditional-chinese-guide)

---

## 1. Project Overview

Super Goose Desktop runs as a lightweight macOS menu bar accessory (`🪿`) with a transparent, click-through `SpriteKit` overlay spanning your connected displays. Geese wander across your screen, leave directional webbed footprints, chase or grab your cursor, drag editable sarcastic notes and custom memes onto the desktop from off-screen edges, and react to your active workspace with configurable pranks and personalities.

## 2. Highlights

- **100% Native macOS Architecture**: Built with Swift 6.2, AppKit, SwiftUI, and SpriteKit with zero third-party Swift package dependencies.
- **2× Retina Procedural Goose Rendering**: `GooseArt` renders the goose body, neck, head, beak, eyes, and feet into a crisp Retina `SKSpriteNode` texture—always visible even without external sprite packs.
- **Smooth Off-Screen Edge-Drag Deliveries**: Notes and memes are physically pulled onto the visible desktop from outside `NSScreen.visibleFrame` along an eased Bezier trajectory (1.5–3.0 seconds) with subtle weight bobbing, rotation, and landing settle.
- **Original Procedural DSP Audio**: Built-in `AVAudioEngine` sound synthesis (`SoundSynthesis`) with global and per-goose vocal cooldowns, quiet hours, and instant Mute All Audio.
- **Privacy-First by Design**: Screen observation, Vision OCR, and Apple Foundation Models run on-device by default; external AI (OpenAI) is off by default and requires explicit opt-in.

## 3. Feature List

- **Multi-Goose Engine**: Spawn and manage up to **5** independent geese with distinct personalities, energy, and mood states.
- **Personal Meme Library**: Import PNG, JPG, JPEG, WEBP, and animated GIF files via Finder or drag-and-drop with categories, weights, tags, and search.
- **Goose Memo Editor**: Editable, resizable native note windows supporting UTF-8 multilingual text, embedded memes, and 6 exit animations.
- **Taunt Library & Phrase Packs**: Manage custom sarcastic lines, categories, and `.txt` phrase packs.
- **Animation Studio & Prank Presets**: Tune drag durations, easing, wobbles, and save/switch full prank preset profiles.
- **Audio Packs & Cooldown Engine**: Switch sound packs, import custom audio, and enforce anti-spam vocal cooldowns.
- **Fullscreen Awareness**: Pauses intrusive cursor/window pranks during fullscreen games and throttles activity during media playback or presentations.
- **Global Hotkeys**: System-wide Carbon shortcuts (`⌃⌥⌘P/H/S/N/E/C`) for Pause/Resume, Hide/Show Geese, Spawn Goose, Emergency Stop, and Control Center.
- **Permission Center & TCC Diagnostics**: Live status and signing diagnostics for Accessibility, Screen Recording, and Notifications.

## 4. Mouse Chase & Bite/Grab Interaction

- **`MouseChaseTask` & `NabMouseTask`**: Geese can stalk your cursor across screens, lunge forward to bite/grab it, and temporarily pull the pointer using `CGWarpMouseCursorPosition`.
- **Safety & Mutual Exclusion**: `GlobalActionCoordinator` enforces single-holder `ResourceLease` mutual exclusion on `.mouse` and `.window` resources so multiple geese never fight over your cursor at the same time.
- **Emergency Stop**: Hold `ESC` (monitored by `EscQuitMonitor`) or press `⌃⌥⌘E` at any time to immediately release the cursor and abort active pranks.

## 5. Multi-Goose Interaction

- **`GooseManager` & `GooseInstance`**: Supports up to **5** concurrent geese, each with its own `UUID`, `GoosePersonality`, energy, boredom, cooldowns, and state persistence (`GooseStatePersistence`).
- **`GooseInteractionSystem`**: Enables peer social behaviors (such as approaching, following, or reacting to other geese) while coordinating shared resources cleanly.

## 6. Dynamic Windows

- **Goose Memo Editor (`GooseMemoEditorWindow` in `GooseNotepadWindow.swift`)**: Borderless yet interactive and resizable floating notes supporting Light/Dark paper themes, editable UTF-8 text (English, Traditional/Simplified Chinese, Emoji), Copy/Close controls, and 6 configurable exit animations.
- **Meme Window (`MemeWindow`)**: Displays static images and multi-frame animated GIFs (`ImageIO`), dragged onto screen by `MemeDeliveryTask`.
- **Parody Fake Errors (`FakeErrorWindow`)**: Clearly labeled virtual goose prank dialogs.
- **Sandboxed Mini Browser (`RealBrowserWindow`)**: HTTPS-only `WKWebView` using `WKWebsiteDataStore.nonPersistent()`.

## 7. Custom Memes & Sarcastic Taunts

- **`MemeLibraryStore`**:
  - Supports **PNG, JPG, JPEG, WEBP**, and animated **GIF**.
  - Import multiple files via `NSOpenPanel` or drag-and-drop into the library, with SHA-256 duplicate detection, Grid/List views, search, category filtering (`Random Memes`, `Sarcastic`, `Angry`, `Funny`, `Reaction`, `Gaming`, `Work`, `Custom`), appearance weight, usage tracking, and manual-only lock.
  - Files are stored safely under `~/Library/Application Support/Super Goose Desktop/UserContent/` rather than bloated inside `UserDefaults`.
- **`TauntLibraryStore`**:
  - Create, edit, categorize, weight, and toggle custom sarcastic taunts or import `.txt` phrase packs.

## 8. Audio System

- **`SoundSynthesis` & `SoundEffectEngine`**: Multi-channel `AVAudioEngine` synthesis producing duck quacks, goose honks, footsteps (`tinyFootstep`, `runningFootstep`), wing flaps, beak pecks, and paper/meme drag sounds.
- **Anti-Spam Cooldowns**: Global vocal cooldown (`20s`) and per-goose cooldowns (`20–40s`), `RandomHonkFrequency` (default `.low`), automatic suppression while sleeping, and instant audio stop on Mute, Pause, or Quit.
- **`AudioPackManager`**: Supports customizable audio packs and user sound imports (`Sounds/`).

## 9. Settings Features

Open **Settings (`⌘,`)** from the Menu Bar (`🪿`) to access **10 native SwiftUI tabs**:

1. **Overview**: Status overview, quick actions, and live counts.
2. **Meme Library**: Import, preview (including animated GIFs), categorize, weight, search, and trigger memes.
3. **Taunt Library**: Manage sarcastic notes, categories, and `.txt` phrase packs.
4. **Animation Studio**: Configure edge-drag animation curves, durations, wobble/rotation, and exit animations.
5. **Audio Packs**: Volume, category toggles, quiet hours, cooldown settings, and custom sound packs.
6. **Emotion & Behavior**: Goose count (1–5), personality traits, energy, chaos level, and individual behavior toggles.
7. **Prank Presets**: Save, apply, and switch preset configurations.
8. **Screen Observation**: Choose **Automatic Background Observation**, **System Content Picker (`SCContentSharingPicker`)**, or **Completely Disabled**.
9. **Permissions**: Launch **Permission Center…** and review Accessibility, Screen Recording, and Notification readiness.
10. **Advanced Settings**: Global hotkeys, fullscreen exception apps, diagnostics, and optional external AI settings.

A live **Control Center** (`⌃⌥⌘C`) is also available for quick runtime adjustments.

## 10. Multi-Screen Support

- **`DisplayManager` & `OverlayWindow`**: Computes the union frame across all connected `NSScreen` displays and translates scene, AppKit, and Quartz coordinates accurately.
- **Dynamic Display Changes**: Listens to `NSApplication.didChangeScreenParametersNotification` to clamp and relocate geese cleanly when external monitors are connected, disconnected, or rearranged.
- **Visible-Frame Delivery**: `NotepadDeliveryTask` and `MemeDeliveryTask` compute entry points from each target screen's `NSScreen.visibleFrame`.

## 11. macOS Permissions

Manage permissions in **Menu Bar (`🪿`) → Permission Center…** or **Settings → Permissions**:

1. **Accessibility (`NSAccessibilityUsageDescription`)**:
   - Used for reading focused window bounds/titles and Window Pranks / Window Peek.
   - Graceful fallback: If denied, goose animation, wandering, memes, notes, and `NSWorkspace.frontmostApplication` detection still work.
2. **Screen Recording (`NSScreenCaptureUsageDescription`)**:
   - Used only when Screen Observation is enabled for `ScreenCaptureKit` capture and on-device Vision OCR.
   - Can be set to **Completely Disabled** with zero `ScreenCaptureKit` calls.
   - Note: Granting Screen Recording for the first time typically requires **Quit & Reopen** (button provided in Permission Center).
3. **Notifications (`UNUserNotificationCenter`)**:
   - Optional and individually toggleable in Settings when running from a valid `.app` bundle.

## 12. System Requirements

- **Hardware**: Apple Silicon (`arm64`: M1 / M2 / M3 / M4 or later)
- **Operating System**: macOS 26.0 or later (declared in `Goose/Package.swift`)
- **Build Toolchain** (for building from source): Xcode 26+ with Swift 6.2+

## 13. Apple Silicon Compatibility

Super Goose Desktop is compiled natively for **`arm64` (Apple Silicon)** using `swift build -c release --arch arm64`. The overlay automatically pauses `SKView` when paused or hidden and scales `preferredFramesPerSecond` dynamically during fullscreen media/presentations to keep CPU/GPU usage low.

## 14. Installation

### Option 1 — Prebuilt DMG (GitHub Releases)

1. Download `Super-Goose-Desktop-Apple-Silicon.dmg` from [GitHub Releases](https://github.com/li-bao/goose/releases).
2. Open the DMG and drag `Super Goose Desktop.app` into `/Applications`.
3. **Important Code-Signing Notice**: The released `.app` and `.dmg` are **ad-hoc signed (`-`) and are NOT Apple-notarized**. On first launch, macOS Gatekeeper will warn about an unidentified developer:
   - Right-click `/Applications/Super Goose Desktop.app` → **Open** → click **Open**, **or**
   - Go to **System Settings → Privacy & Security → Open Anyway**, **or**
   - Run in Terminal:
     ```bash
     xattr -dr com.apple.quarantine "/Applications/Super Goose Desktop.app"
     ```

### Option 2 — Build from Source

See [Development & Build Instructions](#15-development--build-instructions) below.

## 15. Development & Build Instructions

> **Note**: If `xcode-select -p` points to `/Library/Developer/CommandLineTools`, prefix `swift` and `./scripts/build-app.sh` commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` so SwiftUI macros (`SwiftUIMacros`) resolve properly.

```bash
git clone https://github.com/li-bao/goose.git
cd goose

# Run unit tests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Goose

# Build Release .app bundle (arm64)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/build-app.sh

# Package compressed DMG & generate SHA256.txt
./scripts/build-dmg.sh

# Verify bundle signature, Info.plist, icon, resources, and DMG integrity
./scripts/verify-release.sh
```

Output artifacts are written to `dist/Super Goose Desktop.app`, `dist/Super-Goose-Desktop-Apple-Silicon.dmg`, and `dist/SHA256.txt`.

## 16. Known Limitations

- **Ad-hoc Signed / Not Notarized**: Distributed builds use ad-hoc signing (`-`) rather than a Developer ID certificate + Apple notarization; Gatekeeper bypass is required on first launch, and rebuilding locally changes the `CDHash` (which may require resetting TCC entries via `tccutil reset`).
- **Third-Party Sprite Assets Excluded**: Per [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), third-party sprite PNGs are excluded from the repository; the app renders its built-in 2× Retina procedural goose sprite by default.
- **External AI Opt-In**: OpenAI integration is disabled by default and requires explicit user opt-in plus your own API key (`OPENAI_API_KEY` or `~/.config/goose/openai-key`).
- **Apple Silicon Only**: Release build scripts target `arm64` (`--arch arm64`).

## 17. Version Information

- **Current Version**: `v2.2.0` (Build `5`)
- **License**: MIT License ([LICENSE](LICENSE)) — `Copyright (c) 2026 li-bao`, `Copyright (c) 2026 PKrutaa`
- **Changelog**: See [CHANGELOG.md](CHANGELOG.md)

---

## 繁體中文使用說明 (Traditional Chinese Guide)

### 簡介
**Super Goose Desktop** 是一款專為 **Apple Silicon (`arm64`) macOS** 打造的原生桌面寵物與惡作劇系統（Swift 6.2 / AppKit / SwiftUI / SpriteKit）。你可以讓最多 5 隻鵝在多螢幕桌面上散步、留下腳印、追逐與咬住游標，或從螢幕邊緣平滑拖入你自訂的迷因圖片與嘲諷便條。

### 主要功能一覽
- **滑鼠追逐與咬擊互動**：鵝會追逐你的游標並短暫搶走控制權；透過 `GlobalActionCoordinator` 互斥鎖確保多鵝不會同時搶奪滑鼠。隨時按住 **`ESC`** 或使用全域快捷鍵 **`⌃⌥⌘E`** 即可緊急停止並釋放滑鼠。
- **多鵝互動與個性系統**：支援 1–5 隻鵝同時運作，各自擁有個性、精力、無聊度與同儕社交互動。
- **動態視窗與平滑邊緣拖曳**：便條（`GooseMemoEditorWindow`）與迷因（`MemeWindow`）會由鵝從 `NSScreen.visibleFrame` 螢幕邊緣以 1.5–3.0 秒貝茲曲線平滑拖入畫面，並支援可編輯文字、調整視窗大小與 6 種退場動畫。
- **個人迷因庫與嘲諷語錄庫**：支援匯入 **PNG / JPG / JPEG / WEBP / 動態 GIF**，提供分類、出現權重、搜尋、拖曳匯入與僅手動觸發模式；所有檔案安全儲存於 `~/Library/Application Support/Super Goose Desktop/UserContent/`。
- **音效系統與冷卻控制**：內建 100% 原創程序化合成音效（鴨叫、鵝叫、腳步聲、拖紙聲），具備全域（20 秒）與單鵝（20–40 秒）發聲冷卻、睡眠靜音、夜間勿擾時段與一鍵 **Mute All Audio**。
- **10 分頁原生設定中心 (`⌘,`)**：涵蓋 `Overview`、`Meme Library`、`Taunt Library`、`Animation Studio`、`Audio Packs`、`Emotion & Behavior`、`Prank Presets`、`Screen Observation`、`Permissions`、`Advanced Settings`，並附帶即時 **Control Center (`⌃⌥⌘C`)**。
- **多螢幕與全螢幕偵測**：自動跨螢幕座標轉換並在螢幕變更時重新定位鵝群；偵測到全螢幕遊戲時自動暫停干擾性惡作劇。

### 安裝與執行須知
1. 前往 [GitHub Releases](https://github.com/li-bao/goose/releases) 下載 `Super-Goose-Desktop-Apple-Silicon.dmg`。
2. 打開 DMG 並將 `Super Goose Desktop.app` 拖曳至 `/Applications`。
3. **簽章與公證說明**：本專案釋出版本採用 **Ad-hoc 本機簽章（尚未經 Apple 公證 / Notarization）**。首次開啟若遇到 macOS Gatekeeper 阻擋，請對應用程式點擊右鍵 → **打開**，或於終端機執行：
   ```bash
   xattr -dr com.apple.quarantine "/Applications/Super Goose Desktop.app"
   ```

### macOS 權限說明
可從選單列 `🪿` → **Permission Center…** 管理權限：
- **輔助使用 (Accessibility)**：用於讀取前景視窗位置與執行視窗惡作劇；未授權時，散步、便條、迷因與基本互動仍可正常運作。
- **螢幕錄製 (Screen Recording)**：僅在啟用螢幕觀察模式時用於本機畫面擷取與 Vision OCR，亦可於設定中設為 **Completely Disabled（完全停用）**。首次授權後需透過「Quit & Reopen」重啟應用程式生效。

### 開發與建置
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Goose
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/build-app.sh
./scripts/build-dmg.sh
./scripts/verify-release.sh
```
