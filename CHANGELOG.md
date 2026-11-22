# Changelog — Super Goose Desktop

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
