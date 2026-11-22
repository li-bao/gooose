import Foundation

enum ScreenObservationMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case automaticBackground
    case systemContentPicker
    case disabled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automaticBackground: return "Automatic Background Observation"
        case .systemContentPicker: return "System Content Picker"
        case .disabled:            return "Completely Disabled"
        }
    }
}

enum ScreenObservationStatus: Equatable, Sendable {
    case enabled
    case disabled
    case waitingForAuthorization
    case userSelectedScreen(String)
    case stopped
    case restartRequired(String)

    var displayTitle: String {
        switch self {
        case .enabled:                       return "Enabled"
        case .disabled:                      return "Disabled"
        case .waitingForAuthorization:       return "Waiting for authorization"
        case .userSelectedScreen(let label): return "User-selected screen (\(label))"
        case .stopped:                       return "Stopped"
        case .restartRequired:               return "Restart required"
        }
    }
}
