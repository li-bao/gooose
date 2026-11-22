import AppKit
import Foundation

/// Monitors the frontmost application and window geometry to pause intrusive
/// pranks during fullscreen games and throttle activity during media or
/// presentations. Never reads private window content.
@MainActor
final class FullscreenMonitor {
    static let shared = FullscreenMonitor()

    enum Mode: String, Sendable {
        case normal
        case fullscreenGame
        case mediaOrPresentation
    }

    private static let knownMediaApps: Set<String> = [
        "keynote", "microsoft powerpoint", "quicktime player", "vlc", "iina",
        "tv", "apple tv", "netflix", "zoom.us", "obs", "twitch"
    ]

    private static let knownGameKeywords: [String] = [
        "steam", "minecraft", "baldurs", "cyberpunk", "hades", "factorio", "dota", "league of legends", "game"
    ]

    private var overrideModeForTesting: Mode?

    private init() {}

    func setModeForTesting(_ mode: Mode?) {
        overrideModeForTesting = mode
    }

    var currentMode: Mode {
        if let override = overrideModeForTesting {
            return override
        }
        guard GooseSettings.shared.fullscreenAwareness else {
            return .normal
        }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return .normal
        }
        return evaluate(appName: app.localizedName ?? "", bundleID: app.bundleIdentifier ?? "", windowFrame: AccessibilityProbe.frontmostExternalWindow()?.frame)
    }

    /// Pure evaluation helper (also exercised directly by tests).
    func evaluate(appName: String, bundleID: String, windowFrame: CGRect?) -> Mode {
        guard GooseSettings.shared.fullscreenAwareness else {
            return .normal
        }

        let exceptions = GooseSettings.shared.fullscreenExceptionApps
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        let lowerName = appName.lowercased()
        let lowerBundle = bundleID.lowercased()
        if exceptions.contains(where: { lowerName.contains($0) || lowerBundle.contains($0) }) {
            return .normal
        }

        let isMediaApp = Self.knownMediaApps.contains(lowerName)
            || Self.knownMediaApps.contains(where: { lowerBundle.contains($0.replacingOccurrences(of: " ", with: "")) })
        let isGameApp = Self.knownGameKeywords.contains(where: { lowerName.contains($0) || lowerBundle.contains($0) })

        let coversScreen: Bool = {
            guard let wf = windowFrame else { return false }
            return NSScreen.screens.contains { screen in
                let sf = screen.frame
                return abs(wf.width - sf.width) <= 2 && abs(wf.height - sf.height) <= 2
            }
        }()

        if coversScreen && isGameApp {
            return .fullscreenGame
        }
        if coversScreen && isMediaApp {
            return .mediaOrPresentation
        }
        if coversScreen {
            // Unrecognized fullscreen app (likely game or fullscreen media):
            // treat conservatively as media/presentation unless game keyword matched.
            return .mediaOrPresentation
        }
        if isMediaApp {
            return .mediaOrPresentation
        }
        return .normal
    }

    var suppressesHighDisruptionPranks: Bool {
        currentMode == .fullscreenGame
    }

    var activityMultiplier: Double {
        switch currentMode {
        case .normal:              return 1.0
        case .mediaOrPresentation: return 0.25
        case .fullscreenGame:      return 0.0
        }
    }

    var recommendedFPS: Int {
        currentMode == .normal ? 60 : 30
    }
}
