# macOS Permissions Guide

Open **Menu Bar (`🪿`) → Permission Center…** to inspect and authorize permissions.

## 1. Screen Recording (`NSScreenCaptureUsageDescription`)
- **API**: `CGPreflightScreenCaptureAccess()`, `CGRequestScreenCaptureAccess()`, `ScreenCaptureKit` (`SCShareableContent`, `SCScreenshotManager`), Vision OCR (`VNRecognizeTextRequest`).
- **Behavior**:
  - Re-checked before every screen capture (never cached permanently in `UserDefaults`).
  - Pure black/blank frames are automatically rejected (`ScreenCapturer.isBlackOrBlankImage`).
  - Granting Screen Recording mid-session enters **Restart required**; click **Quit & Reopen** so ScreenCaptureKit receives the new TCC token and resumes pending OCR.
- **When denied**: OCR is skipped cleanly; goose animation and app-level context continue working.

## 2. Accessibility (`NSAccessibilityUsageDescription`)
- **API**: `AXIsProcessTrusted()`, `AXIsProcessTrustedWithOptions` (`kAXTrustedCheckOptionPrompt`), `AXUIElement`.
- **Live validation**: Distinguishes `.apiDisabled` (requires process restart) from normal per-window attribute absences (`.noValue`, `.attributeUnsupported`, `.cannotComplete`).
- **When denied**: Window Pranks and Window Peek pause; `NSWorkspace.shared.frontmostApplication` still identifies the active app.

## 3. Notifications (Optional)
- Managed via `UNUserNotificationCenter` only when running from a `.app` bundle, with 5 per-category toggles in **Settings → General**.
