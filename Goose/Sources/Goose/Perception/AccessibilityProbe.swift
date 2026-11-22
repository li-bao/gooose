import AppKit
@preconcurrency import ApplicationServices
import Foundation

/// Probes the system for the foreground app (via `NSWorkspace`) and that app's
/// focused window title/bounds (via macOS Accessibility APIs).
/// If Accessibility permission is missing, AX calls are skipped and `NSWorkspace`
/// continues providing `frontmostAppName` cleanly without crashing or looping prompts.
@MainActor
final class AccessibilityProbe {
    struct WindowInfo {
        let element: AXUIElement
        let pid: pid_t
        /// Frame in Quartz (top-left origin) global display coordinates, matching `kAXPositionAttribute`.
        let frame: CGRect
        let title: String?

        /// Converts the Quartz top-left frame into SpriteKit / Cocoa y-up scene coordinates.
        func sceneFrame(screenHeight: CGFloat) -> CGRect {
            CGRect(
                x: frame.origin.x,
                y: screenHeight - frame.origin.y - frame.size.height,
                width: frame.size.width,
                height: frame.size.height
            )
        }
    }

    /// Whether this process currently has Accessibility permission. Does not prompt.
    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Triggers the native Accessibility prompt if permission is not yet granted.
    /// Note: may return `false` immediately because prompting is asynchronous.
    @discardableResult
    static func promptForAccessibility() -> Bool {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Distinguishes an actual Accessibility authorization failure (`.apiDisabled`)
    /// from benign per-window / per-app attribute failures (e.g. `.noValue`,
    /// `.attributeUnsupported`, `.cannotComplete`).
    static func classifyAXError(
        _ error: AXError,
        frontmostApp: String?,
        windowTitle: String? = nil
    ) -> AccessibilityValidationResult {
        switch error {
        case .success:
            return .trustedAndWorking(frontmostApp: frontmostApp, windowTitle: windowTitle)
        case .apiDisabled:
            return .apiDisabledNeedsRestart(axError: error.rawValue)
        case .noValue, .attributeUnsupported, .cannotComplete, .invalidUIElement, .notImplemented, .actionUnsupported:
            // Trusted, but this specific window/app simply has no focused window or title.
            return .trustedNoFocusedWindow(frontmostApp: frontmostApp, axError: error.rawValue)
        default:
            return .unableToVerify("AXError \(error.rawValue)")
        }
    }

    /// Exercises real `AXUIElement` calls to confirm Accessibility is both trusted
    /// and operationally active for this process.
    static func validateLiveAccessibility() -> AccessibilityValidationResult {
        guard AXIsProcessTrusted() else {
            return .notTrusted
        }

        if let app = NSWorkspace.shared.frontmostApplication {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            var windowRef: CFTypeRef?
            let winErr = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef)
            if winErr == .success, let windowValue = windowRef {
                let windowElement = windowValue as! AXUIElement
                var titleRef: CFTypeRef?
                let titleErr = AXUIElementCopyAttributeValue(windowElement, kAXTitleAttribute as CFString, &titleRef)
                if titleErr == .success {
                    return .trustedAndWorking(frontmostApp: app.localizedName, windowTitle: titleRef as? String)
                }
                return classifyAXError(titleErr, frontmostApp: app.localizedName)
            }
            return classifyAXError(winErr, frontmostApp: app.localizedName)
        }

        let sysWide = AXUIElementCreateSystemWide()
        var focusedApp: CFTypeRef?
        let sysErr = AXUIElementCopyAttributeValue(sysWide, kAXFocusedApplicationAttribute as CFString, &focusedApp)
        return classifyAXError(sysErr, frontmostApp: nil)
    }

    /// Returns the foreground app name, its focused window title, and pid.
    /// `appName` uses `NSWorkspace` and continues working even without Accessibility.
    func currentContext() -> (appName: String?, windowTitle: String?, processIdentifier: pid_t?) {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return (nil, nil, nil)
        }
        let pid = app.processIdentifier
        let title = AXIsProcessTrusted() ? focusedWindowTitle(for: pid) : nil
        return (app.localizedName, title, pid)
    }

    private func focusedWindowTitle(for pid: pid_t) -> String? {
        let appElement = AXUIElementCreateApplication(pid)

        var windowRef: CFTypeRef?
        let windowResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef)
        if windowResult == .apiDisabled {
            PermissionManager.shared.markAccessibilityAPIDisabled(axError: windowResult.rawValue)
            return nil
        }
        guard windowResult == .success, let windowValue = windowRef else { return nil }
        let windowElement = windowValue as! AXUIElement

        var titleRef: CFTypeRef?
        let titleResult = AXUIElementCopyAttributeValue(windowElement, kAXTitleAttribute as CFString, &titleRef)
        if titleResult == .apiDisabled {
            PermissionManager.shared.markAccessibilityAPIDisabled(axError: titleResult.rawValue)
            return nil
        }
        guard titleResult == .success, let title = titleRef as? String, !title.isEmpty else { return nil }
        return title
    }

    /// Returns the frontmost external application's focused window, ignoring our own PID.
    /// Returns `nil` when Accessibility permission is not granted or no window is available.
    static func frontmostExternalWindow() -> WindowInfo? {
        guard hasAccessibilityPermission,
              let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return nil
        }
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)

        var windowRef: CFTypeRef?
        let winErr = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef)
        if winErr == .apiDisabled {
            PermissionManager.shared.markAccessibilityAPIDisabled(axError: winErr.rawValue)
            return nil
        }
        guard winErr == .success, let windowValue = windowRef else {
            return nil
        }
        let windowElement = windowValue as! AXUIElement

        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(windowElement, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(windowElement, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posVal = posRef, let sizeVal = sizeRef else {
            return nil
        }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posVal as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeVal as! AXValue, .cgSize, &size),
              size.width > 40, size.height > 40 else {
            return nil
        }

        var titleRef: CFTypeRef?
        let title: String?
        if AXUIElementCopyAttributeValue(windowElement, kAXTitleAttribute as CFString, &titleRef) == .success,
           let s = titleRef as? String, !s.isEmpty {
            title = s
        } else {
            title = app.localizedName
        }

        return WindowInfo(
            element: windowElement,
            pid: pid,
            frame: CGRect(origin: origin, size: size),
            title: title
        )
    }

    /// Moves a window via Accessibility (`kAXPositionAttribute`) using Quartz top-left coordinates.
    @discardableResult
    static func setWindowOrigin(_ element: AXUIElement, to cgPoint: CGPoint) -> Bool {
        var point = cgPoint
        guard let value = AXValueCreate(.cgPoint, &point) else { return false }
        let err = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
        if err == .apiDisabled {
            PermissionManager.shared.markAccessibilityAPIDisabled(axError: err.rawValue)
        }
        return err == .success
    }
}
