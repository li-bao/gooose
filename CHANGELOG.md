# Changelog — Super Goose Desktop

## [2.2.0] — 2026-11-22

### Phase 1–3 Stability, Edge-Drag Animation, Audio Overhaul & Customization Suite
- **Phase 1 Audit & Stability Fixes**:
  - Eliminated 60fps cross-process Accessibility IPC storm in `FullscreenMonitor` and fixed `ControlCenterView` timer leaks.
  - Added proper async `Task` cancellation cleanup in `AgentDirector`, `HonkTicker`, and `ChillingTicker`.
  - Fixed multi-display coordinate mismatches (`DisplayManager`, `OverlayWindow`, `GooseScene`) and `ClosedRange` crash guards.
- **Smooth Edge-Drag Animation (`NotepadDeliveryTask`, `MemeDeliveryTask`)**:
  - Rewrote delivery flows so the goose physically pulls notes and memes from outside `NSScreen.visibleFrame` along an eased 1.5–3.0s Bezier path with subtle bobbing, rotation, landing settle, and interaction gating until placement completes.
- **Audio Cooldown Overhaul (`GooseManager`, `SoundEffectEngine`, `HonkTicker`)**:
  - Fixed footstep sound playing duck quack on every step (switched to `tinyFootstep` / `runningFootstep`).
  - Added 20s global and 20–40s per-goose vocal cooldowns, `RandomHonkFrequency` (default `.low`), sleep suppression, and instant stop on Mute / Pause / Quit.
- **Phase 2 Customization Suite**:
  - **Personal Meme Library (`MemeLibraryStore`)**: Import PNG, JPG, JPEG, WEBP, and animated GIFs via Finder or drag-and-drop, with categories, weights, usage tracking, tags, and search.
  - **Goose Memo Editor (`GooseMemoEditorWindow`)**: Editable, resizable native note window supporting text and memes with 6 configurable exit animations.
  - **Taunt Library, Animation Studio, Audio Packs, Prank Presets & Persistence**: Added `TauntLibraryStore`, `AnimationStudioConfig`, `AudioPackManager`, `PrankPresetManager`, `GooseStatePersistence`, and `Phase2SettingsViews` (10-tab Settings Center).
- **App Icon & Goose Sprite Rendering (`GooseArt`, `build-app.sh`)**:
  - Added `AppIcon.icns` bundling to `scripts/build-app.sh` and rewrote `GooseArt.swift` to render the goose body, neck, head, beak, eyes, and feet into a crisp 2× Retina `CGContext` → `SKSpriteNode`.

## [2.1.0] — 2026-11-22

### Ultimate Desktop Goose Experience
- **Duck, Goose & Movement Sound Effects (`SoundSynthesis`, `SoundEffectEngine`, `HonkTicker`)**:
  - Added 100% original procedural DSP audio synthesis (no copyrighted *Untitled Goose Game* samples) for Duck (`shortQuack`, `longQuack`, `angryQuack`, `happyQuack`, `surprisedQuack`, `quietMutter`, `repeatedQuacking`), Goose (`classicHonk`, `aggressiveHonk`, `excitedHonk`, `warningHonk`, `sleepingSound`), and Movement (`tinyFootstep`, `runningFootstep`, `wingFlap`, `beakPeck`, `draggingObject`, `paperSlide`, `notepadLand`, `memeDrag`).
  - Added multi-channel `AVAudioEngine` playback with per-sound cooldowns, pitch/volume randomization, category toggles, quiet mode, nighttime quiet hours, and instant Mute All Audio.
- **Persistent User Content & Custom Memes (`UserContentManager`, `MemeWindow`, `MemeDeliveryTask`)**:
  - Created `~/Library/Application Support/Super Goose Desktop/UserContent/` (`Memes/`, `Sounds/`, `NotepadMessages/`, `PhrasePacks/`, `Settings/`) with filesystem watching and non-destructive default seeds (`Example.png`, `example.txt`).
  - Added PNG, JPG, JPEG, and multi-frame animated GIF decoding (`ImageIO`), SHA-256 duplicate detection, drag-and-drop import, rename, and delete.
  - Added `MemeDeliveryTask` dragging `MemeWindow` onto screen from outside display bounds along a quadratic Bezier path.
- **Iconic Dragged Notepads & Phrase Packs (`GooseNotepadWindow`, `NotepadDeliveryTask`)**:
  - Added interactive borderless `GooseNotepadWindow` (paper theme in Light/Dark mode, Copy button, Close button, scrollable UTF-8 multiline text including Traditional/Simplified Chinese and Emoji).
  - Added `NotepadDeliveryTask` physically pulling the notepad onto the desktop from off-screen bounds with configurable intervals, lifetime, and anti-repetition.
  - Added `PhrasePacks` `.txt` parser (`#` comment & blank-line filtering, deduplication) and 8 `GoosePersonalityCategory` styles.
- **Smart Screen Observation Modes (`ScreenObservationMode`, `ContentSharingPickerController`)**:
  - Added 3 modes: Automatic Background Observation, Official `SCContentSharingPicker` System Content Picker, and Completely Disabled (zero `ScreenCaptureKit` / `CGRequestScreenCaptureAccess` calls).
  - Added **Don't ask automatically again** preference and honest macOS security reminder disclosure.
- **9-Tab Native Settings UI & Menu Bar**:
  - Reorganized Settings into: `Overview`, `Goose Behavior`, `Audio`, `Memes`, `Notepad Messages`, `Personality Packs`, `Screen Observation`, `Permissions`, and `Advanced Settings`.
  - Added **Mute All Audio**, **Deliver Meme Now**, and **Deliver Notepad Now** to the menu bar.

## [2.0.1] — 2026-11-22

### macOS TCC Permission Repair & Authorization System
- **Permission Center (`PermissionManager`, `PermissionCenterView`, `PermissionDiagnostics`)**:
  - Added dedicated native SwiftUI **Permission Center…** accessible from Menu Bar (`🪿`), Main Menu, and **Settings → Privacy**.
  - Added 6 explicit states (`Authorized`, `Not authorized`, `Request initiated`, `Restart required`, `Error`, `Unable to verify`) and overall `"All permissions ready"` check gated on active features.
  - Added **TCC & Signing Diagnostics** (`SecCodeCopySelf` / `SecCodeCopySigningInformation`) inspecting bundle path, executable path, `com.pkrutaa.supergoosedesktop`, macOS version, `arm64`, signing identity, `TeamIdentifier`, `CDHash`, Designated Requirement, App Translocation, duplicate `.app` copies, and `NSScreenCaptureUsageDescription`, plus `--diagnose-permissions` CLI flag.
- **Screen Recording Repair (`ScreenCapturer`, `PerceptionEngine`, `OCRRecognizer`)**:
  - Enforced live `CGPreflightScreenCaptureAccess()` check before every capture attempt (never cached in `UserDefaults`).
  - Added explicit `Restart required` detection when authorization changes mid-session, **Quit & Reopen** action, and automatic pending OCR resume after relaunch.
  - Added `ScreenCapturer.isBlackOrBlankImage(_:)` to reject pure black/blank frames and typed `ScreenCaptureFailure` cases.
  - Fixed `OCRRecognizer.swift` compiler warning.
- **Accessibility Repair (`AccessibilityProbe`)**:
  - Switched detection to `AXIsProcessTrusted()` and native prompting to `kAXTrustedCheckOptionPrompt`.
  - Added `classifyAXError` + `validateLiveAccessibility()` to separate `.apiDisabled` (restart needed) from benign per-window attribute failures (`.noValue`, `.attributeUnsupported`, `.cannotComplete`), while keeping `NSWorkspace.frontmostApplication` fallback active.
- **Packaging (`v2.0.1`, Build `3`)**:
  - Updated `Info.plist` with bilingual English + Traditional Chinese `NSScreenCaptureUsageDescription` and `NSAccessibilityUsageDescription`, rebuilt ARM64 Release `.app` and `Super-Goose-Desktop-Apple-Silicon.dmg`, and added `--selftest-permissions`.

## [2.0.0] — 2026-11-22

### Phase 4 — macOS Integration, Security, Performance & Release
- **Multi-Display Support (`DisplayManager`, `OverlayWindow`, `GooseManager`)**:
  - Overlay now spans the union frame across all connected `NSScreen` displays.
  - Added scene/global/Quartz coordinate transforms so `WanderTask` and `NabMouseTask` operate cleanly across displays.
  - Connected `NSApplication.didChangeScreenParametersNotification` to automatically clamp and relocate geese when monitors are disconnected or rearranged.
- **Fullscreen Awareness (`FullscreenMonitor`, `BehaviorScheduler`, `GooseManager`)**:
  - Detects fullscreen games (`mouseTheft`, `mouseDragging`, `windowPranks`, `fakeErrors` automatically paused) and media/presentation apps (throttles activity multiplier to `0.35×` and FPS to `30`).
  - Added configurable `fullscreenExceptionApps` list in **Settings → General**.
- **Global Hotkeys (`GlobalHotkeyManager`)**:
  - Registered Carbon `RegisterEventHotKey` global shortcuts for 6 actions: Pause/Resume (`⌃⌥⌘P`), Hide All Geese (`⌃⌥⌘H`), Show All Geese (`⌃⌥⌘S`), Spawn Goose (`⌃⌥⌘N`), Emergency Stop (`⌃⌥⌘E`), and Open Control Center (`⌃⌥⌘C`).
  - Added enable toggle, key combo display, and Reset Hotkeys controls under **Settings → General**.
- **Notifications (`NotificationManager`)**:
  - Added `UNUserNotificationCenter` support gated safely on valid `.app` bundles (`Notifications` toggle + 5 category switches: prank, new goose, AI message, personality changed, goose sleeping) and live status in **Settings → Privacy**.
- **Security Hardening**:
  - Added HTTPS-only URL validation + `WKWebsiteDataStore.nonPersistent()` in `RealBrowserWindow`.
  - Added strict regex `^spotify:(track|album|playlist|artist):[A-Za-z0-9]+$` in `SpotifyController` before invoking `/usr/bin/osascript`.
  - Added automated security assertions in `--selftest-phase4` ensuring zero network leakage when `externalAIOptIn` is false.
- **Apple Silicon Performance & Packaging**:
  - `OverlayWindow` automatically sets `SKView.isPaused = true` when paused or hidden, and scales `preferredFramesPerSecond` dynamically.
  - Added `--selftest-phase4` and `--selftest-perf` suites.
  - Built and packaged v2.0.0 (`CFBundleVersion=2`) ARM64 Release `.app` and compressed `Super-Goose-Desktop-Apple-Silicon.dmg` (ad-hoc signed; not Apple-notarized).

### Phase 3 — Multi-Goose Architecture & Conflict Prevention
- Added `GooseManager` + `GooseInstance` (`UUID`, individual `GoosePersonality`, AI state, cooldowns, energy, interaction history) with a hard limit of 5 geese.
- Added `GlobalActionCoordinator` enforcing single-holder mutual exclusion for `.mouse` and `.window` `ResourceLease` locks, guarded `CGWarpMouseCursorPosition`, timeouts, and Emergency Stop preemption.
- Added `GooseInteractionSystem` for peer social behaviors and coalesced perception (`PerceptionEngine` 5s rate limit).

### Phase 2 — Advanced Pranks, Personality & AI
- Added/upgraded `MouseChaseTask`, `NabMouseTask` parameters, bounded `FootMark` ring buffer, `WindowPrankTask`, `FakeErrorTask`/`FakeErrorWindow`, virtual-only `DesktopMessOverlay` & `GooseTheftTask`, `WindowPeekTask`, `NapTask`, `DeepSleepTask`, event-based `HonkEvent` sound hooks, stateful `GoosePersonality`, and `BehaviorScheduler`.

### Phase 1 — Native Settings Center & Control Center
- Created native SwiftUI + AppKit 9-tab **Settings Center** (`General`, `Goose`, `Chaos`, `Behaviors`, `Sounds`, `Personality`, `AI`, `Privacy`, `About`), live **Control Center**, `GooseSettings` (`UserDefaults`), bilingual English / Traditional Chinese (`zh-Hant`) localization (`L10n`), and expanded status bar menu (`⌘,`).
