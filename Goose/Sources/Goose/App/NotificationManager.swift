import Combine
import Foundation
import UserNotifications

/// User-controlled notification service. Safely checks `Bundle.main.bundleIdentifier`
/// so unbundled CLI / self-test runs never throw `UNUserNotificationCenter` bundle assertions.
@MainActor
final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    enum Category: String, Sendable {
        case prank
        case newGoose
        case aiMessage
        case personalityChanged
        case gooseSleeping
    }

    @Published private(set) var isAuthorized = false
    @Published private(set) var authorizationStatusText = "Not requested"
    private(set) var deliveredCount = 0

    private var hasValidAppBundle: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    }

    private init() {
        refreshStatus()
    }

    func refreshStatus() {
        guard hasValidAppBundle else {
            isAuthorized = false
            authorizationStatusText = "Unavailable (unbundled CLI)"
            return
        }
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let auth = settings.authorizationStatus
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch auth {
                case .authorized, .provisional, .ephemeral:
                    self.isAuthorized = true
                    self.authorizationStatusText = "Granted"
                case .denied:
                    self.isAuthorized = false
                    self.authorizationStatusText = "Denied"
                case .notDetermined:
                    self.isAuthorized = false
                    self.authorizationStatusText = "Not granted"
                @unknown default:
                    self.isAuthorized = false
                    self.authorizationStatusText = "Unknown"
                }
            }
        }
    }

    func requestAuthorization() {
        guard hasValidAppBundle else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.refreshStatus()
            }
        }
    }

    /// Evaluates whether user settings allow notifications for `category`.
    func isCategoryAllowed(_ category: Category) -> Bool {
        let s = GooseSettings.shared
        guard s.notificationsEnabled else { return false }
        switch category {
        case .prank:              return s.notifyPrank
        case .newGoose:           return s.notifyNewGoose
        case .aiMessage:          return s.notifyAIMessage
        case .personalityChanged: return s.notifyPersonalityChange
        case .gooseSleeping:      return s.notifyGooseSleeping
        }
    }

    func post(category: Category, title: String, body: String) {
        guard isCategoryAllowed(category) else { return }
        deliveredCount += 1

        guard hasValidAppBundle else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(
            identifier: "supergoose.\(category.rawValue).\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
