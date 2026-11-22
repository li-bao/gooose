import CoreGraphics
import Foundation

enum PermissionState: Equatable, Sendable {
    case authorized
    case notAuthorized
    case requestInitiated
    case restartRequired(reason: String)
    case error(message: String)
    case unableToVerify(reason: String)

    var isAuthorized: Bool {
        if case .authorized = self { return true }
        return false
    }

    var displayTitle: String {
        switch self {
        case .authorized:
            return "Authorized"
        case .notAuthorized:
            return "Not authorized"
        case .requestInitiated:
            return "Request initiated"
        case .restartRequired:
            return "Restart required"
        case .error:
            return "Error"
        case .unableToVerify:
            return "Unable to verify"
        }
    }

    var detailMessage: String? {
        switch self {
        case .restartRequired(let reason):
            return reason
        case .error(let message):
            return message
        case .unableToVerify(let reason):
            return reason
        default:
            return nil
        }
    }
}

enum ScreenCaptureFailure: Error, Equatable, Sendable {
    case permissionNotGranted
    case permissionUnverifiable(String)
    case restartRequired(String)
    case sckInitFailed(String)
    case noDisplayAvailable
    case blackOrBlankImage
    case captureFailed(String)

    var localizedDescription: String {
        switch self {
        case .permissionNotGranted:
            return "Screen Recording permission is not granted."
        case .permissionUnverifiable(let reason):
            return "Screen Recording permission state could not be verified: \(reason)"
        case .restartRequired(let reason):
            return reason
        case .sckInitFailed(let reason):
            return "ScreenCaptureKit initialization failed: \(reason)"
        case .noDisplayAvailable:
            return "No active display is available for capture."
        case .blackOrBlankImage:
            return "Screen capture returned a black or blank frame."
        case .captureFailed(let reason):
            return "Screen capture failed: \(reason)"
        }
    }
}

enum ScreenCaptureResult: Sendable {
    case success(CGImage)
    case failure(ScreenCaptureFailure)

    var image: CGImage? {
        if case .success(let img) = self { return img }
        return nil
    }
}

enum AccessibilityValidationResult: Equatable, Sendable {
    case trustedAndWorking(frontmostApp: String?, windowTitle: String?)
    case trustedNoFocusedWindow(frontmostApp: String?, axError: Int32)
    case notTrusted
    case apiDisabledNeedsRestart(axError: Int32)
    case unableToVerify(String)

    var isFunctional: Bool {
        switch self {
        case .trustedAndWorking, .trustedNoFocusedWindow:
            return true
        case .notTrusted, .apiDisabledNeedsRestart, .unableToVerify:
            return false
        }
    }

    var summaryText: String {
        switch self {
        case .trustedAndWorking(let app, let title):
            let appDesc = app ?? "Unknown App"
            if let title, !title.isEmpty {
                return "Working (\(appDesc) — \(title))"
            }
            return "Working (\(appDesc))"
        case .trustedNoFocusedWindow(let app, let code):
            return "Trusted (\(app ?? "No focused window"), AX code \(code))"
        case .notTrusted:
            return "Not trusted"
        case .apiDisabledNeedsRestart(let code):
            return "AX API disabled for this process (AXError \(code)) — restart required"
        case .unableToVerify(let reason):
            return "Unable to verify (\(reason))"
        }
    }
}

struct PermissionDiagnosticsReport: Sendable {
    let generatedAt: Date
    let bundlePath: String
    let executablePath: String
    let bundleIdentifier: String
    let macOSVersion: String
    let architecture: String
    let signingIdentity: String
    let teamIdentifier: String
    let designatedRequirement: String
    let cdHash: String
    let isRunningFromAppBundle: Bool
    let isInstalledInApplications: Bool
    let isTranslocated: Bool
    let duplicateAppPaths: [String]
    let hasScreenCaptureUsageDescription: Bool
    let screenRecordingPreflight: Bool
    let accessibilityTrusted: Bool
    let accessibilityLiveResult: AccessibilityValidationResult
    let warnings: [String]
    let recoveryCommands: [String]

    func formattedText() -> String {
        var lines: [String] = [
            "Super Goose Desktop — TCC & Code Signing Diagnostics",
            "Generated: \(ISO8601DateFormatter().string(from: generatedAt))",
            "Bundle Path: \(bundlePath)",
            "Executable Path: \(executablePath)",
            "Bundle Identifier: \(bundleIdentifier)",
            "macOS Version: \(macOSVersion)",
            "Architecture: \(architecture)",
            "Signing Identity: \(signingIdentity)",
            "TeamIdentifier: \(teamIdentifier)",
            "CDHash: \(cdHash)",
            "Designated Requirement: \(designatedRequirement)",
            "Running From .app Bundle: \(isRunningFromAppBundle)",
            "Installed In /Applications: \(isInstalledInApplications)",
            "App Translocation Active: \(isTranslocated)",
            "Info.plist NSScreenCaptureUsageDescription: \(hasScreenCaptureUsageDescription)",
            "Screen Recording Preflight (CGPreflightScreenCaptureAccess): \(screenRecordingPreflight)",
            "Accessibility Trusted (AXIsProcessTrusted): \(accessibilityTrusted)",
            "Accessibility Live AXUIElement Check: \(accessibilityLiveResult.summaryText)",
            "Duplicate Installations Found: \(duplicateAppPaths.isEmpty ? "None" : duplicateAppPaths.joined(separator: ", "))",
        ]
        if !warnings.isEmpty {
            lines.append("")
            lines.append("Warnings:")
            for warning in warnings {
                lines.append("  - \(warning)")
            }
        }
        if !recoveryCommands.isEmpty {
            lines.append("")
            lines.append("Optional Manual Recovery Commands (run only when stale TCC entries are suspected):")
            for cmd in recoveryCommands {
                lines.append("  \(cmd)")
            }
        }
        return lines.joined(separator: "\n")
    }
}
