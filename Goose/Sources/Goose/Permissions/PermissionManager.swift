import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import Foundation

@MainActor
final class PermissionManager: ObservableObject {
    static let shared = PermissionManager()

    private static let pendingOCRResumeKey = "supergoose.pendingOCRResumeAfterRestart"

    @Published private(set) var screenRecordingState: PermissionState
    @Published private(set) var accessibilityState: PermissionState
    @Published private(set) var screenObservationStatus: ScreenObservationStatus = .disabled
    @Published private(set) var lastScreenCaptureError: ScreenCaptureFailure?
    @Published private(set) var lastAccessibilityValidation: AccessibilityValidationResult = .notTrusted
    @Published private(set) var diagnostics: PermissionDiagnosticsReport?

    /// Screen Recording authorization captured at process startup.
    /// When a user grants Screen Recording while the app is running, macOS
    /// ScreenCaptureKit frequently requires a full process restart before streams succeed.
    private let screenPreflightAtLaunch: Bool
    private var liveCaptureVerifiedThisSession = false
    private var screenRequestInitiated = false
    private var axRequestInitiated = false
    private var didStartMonitoring = false
    private var activeObserver: NSObjectProtocol?

    private init() {
        let screenNow = CGPreflightScreenCaptureAccess()
        self.screenPreflightAtLaunch = screenNow
        self.screenRecordingState = screenNow ? .authorized : .notAuthorized

        let axNow = AXIsProcessTrusted()
        self.accessibilityState = axNow ? .authorized : .notAuthorized
        if axNow {
            let live = AccessibilityProbe.validateLiveAccessibility()
            self.lastAccessibilityValidation = live
            self.accessibilityState = Self.mapAXValidation(live)
        }
    }

    func startMonitoring() {
        guard !didStartMonitoring else { return }
        didStartMonitoring = true
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshAll(validateLiveAX: true)
            }
        }
        refreshAll(validateLiveAX: true)
    }

    func refreshAll(validateLiveAX: Bool = true) {
        refreshScreenRecording()
        refreshScreenObservationStatus()
        refreshAccessibility(validateLive: validateLiveAX)
        refreshDiagnostics()
    }

    func refreshScreenObservationStatus() {
        let s = GooseSettings.shared
        switch s.screenObservationMode {
        case .disabled:
            screenObservationStatus = .disabled
        case .systemContentPicker:
            let picker = ContentSharingPickerController.shared
            if picker.isSharingActive {
                screenObservationStatus = .userSelectedScreen(picker.selectedSourceLabel)
            } else {
                screenObservationStatus = .stopped
            }
        case .automaticBackground:
            switch screenRecordingState {
            case .authorized:
                screenObservationStatus = s.screenRecognition ? .enabled : .disabled
            case .restartRequired(let reason):
                screenObservationStatus = .restartRequired(reason)
            case .requestInitiated, .notAuthorized, .error, .unableToVerify:
                screenObservationStatus = .waitingForAuthorization
            }
        }
    }

    func setScreenObservationMode(_ mode: ScreenObservationMode) {
        GooseSettings.shared.screenObservationMode = mode
        switch mode {
        case .disabled:
            GooseSettings.shared.screenRecognition = false
            ContentSharingPickerController.shared.stopSharing()
        case .systemContentPicker:
            GooseSettings.shared.screenRecognition = true
        case .automaticBackground:
            GooseSettings.shared.screenRecognition = true
            ContentSharingPickerController.shared.stopSharing()
        }
        refreshScreenObservationStatus()
    }

    // MARK: - Screen Recording

    func refreshScreenRecording() {
        let preflight = CGPreflightScreenCaptureAccess()
        if preflight {
            if liveCaptureVerifiedThisSession {
                screenRecordingState = .authorized
            } else if !screenPreflightAtLaunch {
                screenRecordingState = .restartRequired(
                    reason: "Screen Recording was granted during this session. Quit and reopen Super Goose Desktop so ScreenCaptureKit receives the new authorization."
                )
            } else if case .restartRequired = screenRecordingState {
                // Keep explicit restart-required state until the process restarts.
            } else if case .error = screenRecordingState {
                // Preserve real capture error until user clicks Recheck or a capture succeeds.
            } else {
                screenRecordingState = .authorized
            }
        } else {
            screenRecordingState = screenRequestInitiated ? .requestInitiated : .notAuthorized
        }
        refreshScreenObservationStatus()
    }

    func requestScreenRecordingAccess() {
        guard GooseSettings.shared.screenObservationMode != .disabled else {
            return
        }
        screenRequestInitiated = true
        let immediate = CGRequestScreenCaptureAccess()
        if immediate {
            if !screenPreflightAtLaunch {
                screenRecordingState = .restartRequired(
                    reason: "Screen Recording was granted. Quit and reopen Super Goose Desktop so ScreenCaptureKit can capture the display."
                )
            } else {
                screenRecordingState = .authorized
            }
        } else {
            // Prompt is asynchronous; never pretend access was granted.
            screenRecordingState = .requestInitiated
        }
        refreshDiagnostics()
    }

    func openScreenRecordingSettings() {
        Self.openSettingsURLs([
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension",
        ])
    }

    func recordScreenCaptureOutcome(_ result: ScreenCaptureResult) {
        switch result {
        case .success:
            lastScreenCaptureError = nil
            screenRequestInitiated = false
            if GooseSettings.shared.screenObservationMode == .automaticBackground {
                liveCaptureVerifiedThisSession = true
                screenRecordingState = .authorized
            }
        case .failure(let failure):
            lastScreenCaptureError = failure
            switch failure {
            case .permissionNotGranted:
                screenRecordingState = screenRequestInitiated ? .requestInitiated : .notAuthorized
            case .permissionUnverifiable(let reason):
                screenRecordingState = .unableToVerify(reason: reason)
            case .restartRequired(let reason):
                screenRecordingState = .restartRequired(reason: reason)
            case .sckInitFailed, .noDisplayAvailable, .blackOrBlankImage, .captureFailed:
                screenRecordingState = .error(message: failure.localizedDescription)
            }
        }
        refreshScreenObservationStatus()
    }

    func recheckScreenRecordingWithLiveCapture(capturer: ScreenCapturer) async {
        capturer.resetDisplayCache()
        let preflight = CGPreflightScreenCaptureAccess()
        guard preflight else {
            lastScreenCaptureError = .permissionNotGranted
            screenRecordingState = screenRequestInitiated ? .requestInitiated : .notAuthorized
            refreshDiagnostics()
            return
        }

        let result = await capturer.captureMainDisplayResult(bypassRestartGuard: true)
        recordScreenCaptureOutcome(result)
        refreshDiagnostics()
    }

    func markPendingOCRResumeAfterRestart() {
        UserDefaults.standard.set(true, forKey: Self.pendingOCRResumeKey)
    }

    func consumePendingOCRResumeIfAuthorized() -> Bool {
        let pending = UserDefaults.standard.bool(forKey: Self.pendingOCRResumeKey)
        guard pending else { return false }
        guard CGPreflightScreenCaptureAccess() else { return false }
        UserDefaults.standard.removeObject(forKey: Self.pendingOCRResumeKey)
        return true
    }

    func relaunchApplication() {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            return
        }
        markPendingOCRResumeAfterRestart()
        let appURL = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, error in
            guard error == nil else { return }
            Task { @MainActor in
                NSApp.terminate(nil)
            }
        }
    }

    // MARK: - Accessibility

    func refreshAccessibility(validateLive: Bool = true) {
        let trusted = AXIsProcessTrusted()
        guard trusted else {
            lastAccessibilityValidation = .notTrusted
            accessibilityState = axRequestInitiated ? .requestInitiated : .notAuthorized
            return
        }
        axRequestInitiated = false
        if validateLive {
            let live = AccessibilityProbe.validateLiveAccessibility()
            lastAccessibilityValidation = live
            accessibilityState = Self.mapAXValidation(live)
        } else {
            accessibilityState = .authorized
        }
    }

    func requestAccessibilityAccess() {
        axRequestInitiated = true
        let immediate = AccessibilityProbe.promptForAccessibility()
        if immediate {
            refreshAccessibility(validateLive: true)
        } else {
            // AXIsProcessTrustedWithOptions returns false immediately while prompt is shown.
            accessibilityState = .requestInitiated
        }
        refreshDiagnostics()
    }

    func openAccessibilitySettings() {
        Self.openSettingsURLs([
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension",
        ])
    }

    func markAccessibilityAPIDisabled(axError: Int32) {
        let result = AccessibilityValidationResult.apiDisabledNeedsRestart(axError: axError)
        lastAccessibilityValidation = result
        accessibilityState = Self.mapAXValidation(result)
    }

    // MARK: - Overall Status & Helpers

    var allActivePermissionsReady: Bool {
        let settings = GooseSettings.shared
        if settings.screenRecognition &&
           settings.screenObservationMode == .automaticBackground &&
           !screenRecordingState.isAuthorized {
            return false
        }
        let needsAX = settings.isEnabled(.windowPranks) || settings.isEnabled(.windowPeek)
        if needsAX && !accessibilityState.isAuthorized {
            return false
        }
        return true
    }

    func refreshDiagnostics() {
        diagnostics = PermissionDiagnostics.collect(liveAX: lastAccessibilityValidation)
    }

    /// Test-only helper to exercise UI/state transitions deterministically.
    func setStateForTesting(screen: PermissionState? = nil, accessibility: PermissionState? = nil) {
        if let screen { screenRecordingState = screen }
        if let accessibility { accessibilityState = accessibility }
    }

    private static func mapAXValidation(_ result: AccessibilityValidationResult) -> PermissionState {
        switch result {
        case .trustedAndWorking, .trustedNoFocusedWindow:
            return .authorized
        case .notTrusted:
            return .notAuthorized
        case .apiDisabledNeedsRestart(let code):
            return .restartRequired(reason: "Accessibility is enabled in System Settings, but macOS returned AXError \(code) (API disabled) for this process. Quit and reopen the app.")
        case .unableToVerify(let reason):
            return .unableToVerify(reason: reason)
        }
    }

    private static func openSettingsURLs(_ candidates: [String]) {
        for raw in candidates {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}
