# Super Goose Desktop

A native macOS desktop pet written in **Swift 6.2**, **AppKit**, **SwiftUI**, and **SpriteKit** for **Apple Silicon (`arm64`)**. Inspired by Sam Chiet's *Desktop Goose*, Super Goose Desktop features multi-goose simulation, configurable pranks, on-device contextual awareness, and a complete macOS TCC Permission Center.

---

## Features

- **Native macOS Settings Center (`⌘,`) & Control Center**: 9-tab SwiftUI + AppKit interface (`Overview`, `Goose Behavior`, `Audio`, `Memes`, `Notepad Messages`, `Personality Packs`, `Screen Observation`, `Permissions`, `Advanced Settings`) plus live Control Center.
- **Duck, Goose & Movement Sound Effects**: Original procedural DSP `AVAudioEngine` sound synthesis (no copyrighted game audio) with duck quacks, goose honks, footsteps, paper slides, per-sound cooldowns, pitch randomization, quiet hours, custom sound imports, and instant **Mute All Audio**.
- **Custom Memes & Dragged Notepads**: Persistent local `UserContent/` directory (`~/Library/Application Support/Super Goose Desktop/UserContent/`) supporting PNG, JPG, JPEG, animated GIFs (`ImageIO`), UTF-8 multilingual `.txt` notes (Traditional/Simplified Chinese, English, Emoji), `#`-commented `PhrasePacks`, and physical off-screen Bezier-dragged `GooseNotepadWindow` & `MemeWindow` deliveries.
- **Smart Screen Observation Control**: Choose between **Automatic Background Observation**, **System Content Picker (`SCContentSharingPicker`)**, or **Completely Disabled** (zero ScreenCaptureKit / permission requests).
- **Multi-Goose Engine & Resource Arbitration**: Run up to 5 independent geese (`GooseManager`) with individual personalities (`GoosePersonality`), energy, cooldowns, and peer interactions (`GooseInteractionSystem`). `GlobalActionCoordinator` guarantees mutual exclusion for Mouse and Window locks.
- **Prank & Ambient Behaviors**:
  - Mouse Chase & Mouse Theft (`CGWarpMouseCursorPosition` with Emergency Stop release)
  - Sticky Notes & Parody Fake Errors (clearly marked as virtual goose pranks)
  - Window Pranks & Window Peek (via macOS Accessibility when authorized)
  - Virtual Desktop Mess & Goose Theft (100% SpriteKit overlay — never touches real Desktop files)
  - Directional Webbed Footprints, Nap / Deep Sleep, Angry Mode, Spotify Chill (`osascript` URI-validated), and event-tailored honk engine
- **macOS Deep Integration**:
  - Multi-display union overlay and automatic off-screen relocation on monitor changes (`DisplayManager`)
  - Fullscreen Awareness (`FullscreenMonitor`) pausing intrusive pranks during fullscreen games and throttling activity during media/presentations
  - Global Hotkeys (`⌃⌥⌘P/H/S/N/E/C`) via Carbon `RegisterEventHotKey`
  - Launch at Login via `SMAppService.mainApp`
  - User-controlled `UNUserNotificationCenter` alerts
- **Permission Center & TCC Diagnostics**:
  - Dedicated **Permission Center…** window for Screen Recording and Accessibility with explicit states (`Authorized`, `Not authorized`, `Request initiated`, `Restart required`, `Error`, `Unable to verify`), live `AXUIElement` validation, pure-black capture rejection, and `Security.framework` signing diagnostics.

---

## System Requirements & Architecture

- **Hardware**: Apple Silicon (`arm64`: M1, M2, M3, M4, or later)
- **Operating System**: macOS 26.1 or later
- **Toolchain**: Swift 6.2+ / Xcode 26.1+
- **Architecture**: 100% native Swift 6.2 (`@MainActor` simulation + SpriteKit `SKView` overlay + SwiftUI settings/windows). See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

---

## Installation

### Option 1 — DMG Installation (from GitHub Releases / Local Build)
1. Open `Super-Goose-Desktop-Apple-Silicon.dmg` and drag `Super Goose Desktop.app` into `/Applications`.
2. Eject the DMG.
3. Because ad-hoc builds are **not Apple-notarized**, right-click `/Applications/Super Goose Desktop.app` → **Open** (or allow via **System Settings → Privacy & Security → Open Anyway**). See [docs/INSTALLATION.md](docs/INSTALLATION.md).

### Option 2 — Build from Source
```bash
git clone https://github.com/li-bao/goose.git
cd goose
```
Optionally place compatible goose sprites in `Goose/Sources/Goose/Resources/Sprites/Goose/` (see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)), then build & test:
```bash
cd Goose
swift package resolve
swift build -c release --arch arm64
swift test
```
To package a signed `.app` and `.dmg`:
```bash
./scripts/build-app.sh
./scripts/build-dmg.sh
./scripts/verify-release.sh
```
See [docs/BUILDING.md](docs/BUILDING.md) and [docs/RELEASE.md](docs/RELEASE.md).

---

## macOS Permissions Setup

Open **Menu Bar (`🪿`) → Permission Center…** (or **Settings → Privacy**):

1. **Accessibility** (`NSAccessibilityUsageDescription`):
   - **Used for**: Reading focused window bounds/titles and Window Pranks / Window Peek.
   - **Graceful fallback**: If not granted, goose animation, wandering, notes, and `NSWorkspace.frontmostApplication` detection continue working normally.
2. **Screen Recording** (`NSScreenCaptureUsageDescription`):
   - **Used for**: Local `ScreenCaptureKit` screen capture and on-device Vision OCR (`VNRecognizeTextRequest`).
   - **Restart note**: After granting Screen Recording for the first time, macOS ScreenCaptureKit typically requires quitting and reopening the app (**Quit & Reopen** button in Permission Center).

Full details and recovery commands (`tccutil reset` when ad-hoc `CDHash` changes across rebuilds) are documented in [docs/PERMISSIONS.md](docs/PERMISSIONS.md) and [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

---

## Privacy

- **On-device by default**: Screen Capture, Vision OCR, Accessibility checks, and Apple Foundation Models run strictly on your Mac. Screen images and OCR text stay in memory and are **never** written to disk or uploaded.
- **OpenAI (Explicit Opt-In, Off by Default)**: Only enabled if you toggle **Allow external AI** in **Settings → Privacy** and provide an API key (`OPENAI_API_KEY` or `~/.config/goose/openai-key`). Even when enabled, OCR text and screenshots are never sent—only optional frontmost app name and timing metadata.
- **No background telemetry**: Update checks to GitHub run only when you click **Check for Updates**. See [docs/SECURITY.md](docs/SECURITY.md).

---

## Attribution & Licensing

- **License**: MIT License ([LICENSE](LICENSE)) — `Copyright (c) 2026 li-bao`, `Copyright (c) 2026 PKrutaa`.
- **Original Upstream**: Based on [PKrutaa/super-goose-desktop](https://github.com/PKrutaa/super-goose-desktop), inspired by Sam Chiet's [Desktop Goose](https://samperson.itch.io/desktop-goose).
- **Third-Party Notices**: See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for sprite and audio asset exclusions.
