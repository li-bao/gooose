# Super Goose Desktop 2.0 — Security & Privacy Audit Report

> Audit Scope: Full static inspection across all 69 Swift source files in `Goose/Sources/Goose/` + automated security assertions in `--selftest-phase4`.

---

## 1. Audited Surface Summary

| Attack / Privacy Surface | Observed Call Sites | Protection & Verification | Risk Verdict |
|---|---|---|---|
| **Network (`URLSession` / `URLRequest`)** | 1) `AI/OpenAIClient.swift:88-96`<br>2) `UI/SettingsView.swift:561-564` | 1) `OpenAIClient` is **hard-blocked** unless `GooseSettings.shared.externalAIOptIn == true` (off by default, requires explicit confirmation dialog). Zero OCR text or screen images are ever included in payloads.<br>2) `SettingsView` GitHub update check (`api.github.com/repos/PKrutaa/super-goose-desktop/releases/latest`) runs **only when the user clicks "Check for Updates"**. Zero background telemetry or analytics. | **Low / Controlled** |
| **Embedded Browser (`WKWebView`)** | `Windows/RealBrowserWindow.swift:13-30` | Strict `isAllowedURL` validation permits **only `https://` URLs with a non-empty host** (blocks `http://`, `file://`, `javascript://`, custom schemes). Uses `WKWebsiteDataStore.nonPersistent()` so cookies, storage, and history are never written to disk. | **Low / Hardened** |
| **External Processes & AppleScript (`Process` / `osascript`)** | `Audio/SpotifyController.swift:38-84` | Invokes `/usr/bin/osascript` **only** to tell local Spotify.app to play a validated URI. Enforces strict regex `^spotify:(track\|album\|playlist\|artist):[A-Za-z0-9]+$` (`isValidSpotifyURI`) before process execution, neutralizing AppleScript injection. Zero other shell or `Process` invocations exist in the codebase. | **Low / Hardened** |
| **Keychain (`SecItem*`)** | None (`0` occurrences) | Application does not store or query macOS Keychain credentials. Optional OpenAI key is read read-only from `OPENAI_API_KEY` or `~/.config/goose/openai-key`. | **None** |
| **Preferences (`UserDefaults`)** | `Settings/GooseSettings.swift`, `App/GooseController.swift` | Stores only local user settings (`schemaVersion = 3`), hotkey metadata, and aggregate interaction counters (`pats`, `pokes`, `windowsClosed`). Never stores passwords, tokens, or captured user content. | **Low** |
| **File System (`FileManager`)** | 1) `Audio/AudioPlayer.swift:89`<br>2) `AI/OpenAIClient.swift:124`<br>3) `Photos/PhotoLibrary.swift:43` | 1) Read-only load of user sound assets.<br>2) Read-only check for user-placed `openai-key`.<br>3) Read-only image enumeration from `~/Pictures` when Window Pranks drag a photo.<br>`Scene/DesktopMessOverlay.swift` performs **zero** `FileManager` I/O — Desktop Mess and Goose Theft are 100% virtual SpriteKit overlays and never create, move, or delete real Desktop files. | **Low** |
| **Screen Capture & Vision OCR** | `Perception/ScreenCapturer.swift`, `Perception/OCRRecognizer.swift` | Uses `ScreenCaptureKit` (`SCStreamConfiguration`) + on-device `VNRecognizeTextRequest`. Gated behind macOS Screen Recording TCC permission + user toggle (`screenRecognition`). Captured frames and recognized text stay strictly in RAM; never saved to disk or transmitted externally. When permission is absent, OCR gracefully degrades without bypassing TCC or nagging in a loop. | **Low / Privacy-Preserving** |
| **Cursor & Accessibility Control** | `AI/GlobalActionCoordinator.swift`, `Perception/AccessibilityProbe.swift` | `CGWarpMouseCursorPosition` is centralized exclusively inside `GlobalActionCoordinator.warpMouseGuarded` behind an exclusive, time-bounded `ResourceLease`. Emergency Stop (`EscQuitMonitor`, menu, or `⌃⌥⌘E`) immediately cancels leases and restores cursor control. AX probing never bypasses TCC. | **Low / Controlled** |
| **Fake Errors & User Trust** | `Windows/FakeErrorWindow.swift`, `Tasks/FakeErrorTask.swift` | Explicitly styled as parody goose dialogs (clear playful context). Never requests credentials, never imitates FileVault/Keychain/admin authentication prompts. | **Low** |
| **Login Persistence (`SMAppService`)** | `Settings/GooseSettings.swift:217,459-474` | Uses Apple's official `SMAppService.mainApp.register()` / `.unregister()`. No hidden LaunchAgents, cron jobs, or background daemons are created. | **Low** |
| **Notifications (`UNUserNotificationCenter`)** | `App/NotificationManager.swift` | Checks `Bundle.main.bundleIdentifier != nil && bundleURL.pathExtension == "app"` so CLI/test executions never trigger notification assertions, and respects user category permissions. | **Low** |

---

## 2. Automated Security Verification (`--selftest-phase4`)

Verified on packaged Release binary `Super Goose Desktop.app/Contents/MacOS/Goose`:
- `PASS  SpotifyController accepts valid track URI`
- `PASS  SpotifyController rejects AppleScript injection`
- `PASS  RealBrowserWindow allows valid https URL`
- `PASS  RealBrowserWindow rejects file:// URL`
- `PASS  RealBrowserWindow rejects http:// URL`
- `PASS  RealBrowserWindow rejects javascript: URL`
- `PASS  External AI requests remain 0 without opt-in`

---

## 3. Distribution & Code Signing Disclosure

- **Signing**: Ad-hoc signed (`codesign --force --sign - --timestamp=none --deep`) using no Team Developer ID certificate (`TeamIdentifier=not set`, `Signature=adhoc`).
- **Notarization**: This build is **NOT Apple-notarized**. Users must authorize first launch via Finder right-click → Open, System Settings → Privacy & Security → Open Anyway, or `xattr -cr` (documented transparently in `dist/INSTALL.txt`).
