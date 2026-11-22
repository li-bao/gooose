# Super Goose Desktop 2.0.1 — TCC Permission Troubleshooting & Dependency Map

## 1. Root Causes Found During Audit

1. **Accessibility prompt key & preflight API (`AccessibilityProbe.swift`)**:
   - Previously checked `AXIsProcessTrustedWithOptions(nil)` and passed raw string `"AXTrustedCheckOptionPrompt"` instead of `AXIsProcessTrusted()` and `kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String`.
   - Did not distinguish `AXError.apiDisabled` (process-level TCC/restart issue) from benign per-window failures (`.noValue`, `.attributeUnsupported`, `.cannotComplete`), nor validate live `AXUIElement` calls.
2. **Screen Recording restart & black-frame handling (`ScreenCapturer.swift`, `PerceptionEngine.swift`, `SettingsView.swift`)**:
   - Previously `SettingsView` polled `CGPreflightScreenCaptureAccess()` every 2 seconds via `Timer.publish`, had no explicit `Restart required` state when Screen Recording was granted mid-session, did not re-check `CGPreflightScreenCaptureAccess()` right before every `SCShareableContent` / `SCScreenshotManager` call, and did not reject pure black frames (`isBlackOrBlankImage`).
   - `PerceptionEngine.requestPermissions()` previously fired Accessibility + ScreenCaptureKit prompts automatically if called, instead of letting the user initiate authorization deliberately.
3. **Code Signing / TCC Identity (`codesign` / `security find-identity`)**:
   - This workstation has `0 valid identities found` (`TeamIdentifier=not set`), so builds are **ad-hoc signed** (`Signature=adhoc`, Designated Requirement `cdhash H"..."`). Every rebuild changes the `CDHash`, which can cause macOS TCC to treat a rebuilt binary as an untrusted/different binary or retain stale entries.
   - Running via `swift run` or from `/Users/.../Downloads/goose/dist/` alongside an older `/Applications/Super Goose Desktop.app` copy causes TCC attribution confusion.

---

## 2. Permission Dependency Map

| Feature | Screen Recording | Accessibility | Independent (No TCC Needed) |
|---|---|---|---|
| **Goose SpriteKit Animation, Wander, Nap, DeepSleep** | No | No | Yes |
| **Menu Bar, Control Center, Settings Center, Permission Center** | No | No | Yes |
| **Sticky Notes, Fake Errors, Desktop Mess, Goose Theft, Footprints, Mouse Chase, Mouse Theft** | No | No | Yes (`CGWarpMouseCursorPosition` works without AX) |
| **Basic Frontmost App Name (`NSWorkspace.shared.frontmostApplication`)** | No | No | Yes |
| **Focused Window Title & Bounds (`AXUIElement`)** | No | **Yes** | Degrades cleanly to `NSWorkspace` app name |
| **Window Pranks & Window Peek (`DragWindowTask`, `WindowPrankTask`, `WindowPeekTask`)** | No | **Yes** | Paused safely when AX unavailable |
| **Fullscreen Media / Game Window Geometry Detection** | No | **Yes** (exact window frame) | Falls back to app-level detection |
| **On-Device Screen Capture & Vision OCR (`SCShareableContent`, `SCScreenshotManager`, `VNRecognizeTextRequest`)** | **Yes** | No | Skipped cleanly; AI uses app name + idle time |

---

## 3. Built-in Diagnostics (`Permission Center` & `--diagnose-permissions`)

Run from Terminal against the installed app:
```bash
"/Applications/Super Goose Desktop.app/Contents/MacOS/Goose" --diagnose-permissions
```
Or open **Menu Bar (🪿) → Permission Center… → TCC & Signing Diagnostics**.

The report inspects (without touching the private TCC database, SIP, or Gatekeeper):
- Bundle Path, Executable Path, Bundle Identifier (`com.pkrutaa.supergoosedesktop`), macOS version, Architecture (`arm64`)
- Signing Identity, TeamIdentifier, CDHash, Designated Requirement (via `Security.framework` `SecCodeCopySelf`)
- `.app` bundle attribution, `/Applications` install check, App Translocation (`/AppTranslocation/`), duplicate `.app` copies, and `NSScreenCaptureUsageDescription` presence
- Live `CGPreflightScreenCaptureAccess()`, `AXIsProcessTrusted()`, and `AccessibilityProbe.validateLiveAccessibility()`

---

## 4. Official Recovery Procedures (Manual Only)

If macOS holds a stale TCC entry after upgrading or replacing an ad-hoc build:

1. Quit **Super Goose Desktop** completely (`Menu Bar → Quit` or hold `ESC`).
2. Ensure only **one** copy exists at `/Applications/Super Goose Desktop.app` (delete old copies in `Downloads` or Trash; ensure App Translocation is cleared).
3. Run the official Apple `tccutil` reset commands for this bundle ID (never executed automatically by the app):
   ```bash
   tccutil reset ScreenCapture com.pkrutaa.supergoosedesktop
   tccutil reset Accessibility com.pkrutaa.supergoosedesktop
   ```
4. Reopen `/Applications/Super Goose Desktop.app` from Finder or Applications.
5. Open **Menu Bar (🪿) → Permission Center…**, grant **Screen Recording** and **Accessibility**, and click **Quit & Reopen** if `Restart required` appears.
