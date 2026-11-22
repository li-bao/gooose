import Combine
import CoreGraphics
import Foundation

enum MemoEntryStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case dragFromLeft
    case dragFromRight
    case dragFromTop
    case dragFromBottom
    case randomEdge
    case gooseCarry

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dragFromLeft:   return "Drag From Left"
        case .dragFromRight:  return "Drag From Right"
        case .dragFromTop:    return "Drag From Top"
        case .dragFromBottom: return "Drag From Bottom"
        case .randomEdge:     return "Random Edge"
        case .gooseCarry:     return "Goose Carry"
        }
    }
}

enum MemoExitStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case dragAwayLeft
    case dragAwayRight
    case slideDown
    case fadeOut
    case gooseTakesItAway
    case randomExit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dragAwayLeft:     return "Drag Away Left"
        case .dragAwayRight:    return "Drag Away Right"
        case .slideDown:        return "Slide Down"
        case .fadeOut:          return "Fade Out"
        case .gooseTakesItAway: return "Goose Takes It Away"
        case .randomExit:       return "Random Exit"
        }
    }
}

enum MemoEaseCurve: String, CaseIterable, Identifiable, Codable, Sendable {
    case easeInOut
    case easeOut
    case springSoft
    case linear

    var id: String { rawValue }

    var title: String {
        switch self {
        case .easeInOut:  return "Ease In-Out"
        case .easeOut:    return "Ease Out"
        case .springSoft: return "Soft Spring"
        case .linear:     return "Linear"
        }
    }

    func evaluate(_ u: CGFloat) -> CGFloat {
        let t = max(0, min(1, u))
        switch self {
        case .easeInOut:
            return Easings.cubicEaseInOut(t)
        case .easeOut:
            return Easings.exponentialEaseOut(t)
        case .springSoft:
            let inv = 1 - t
            return 1 - inv * inv * cos(t * .pi * 1.5)
        case .linear:
            return t
        }
    }
}

struct AnimationStudioSettings: Codable, Equatable, Sendable {
    var version: Int = 1
    var entryStyle: MemoEntryStyle = .randomEdge
    var entryDuration: Double = 2.0
    var movementSpeed: Double = 1.0
    var rotationDegrees: Double = 2.5
    var bounceIntensity: Double = 0.5
    var dragOffset: Double = 16.0
    var easeCurve: MemoEaseCurve = .easeInOut

    var exitStyle: MemoExitStyle = .fadeOut
    var exitDuration: Double = 0.65
    var fadeSpeed: Double = 1.0
    var exitRotationDegrees: Double = 2.0
    var randomizeExit: Bool = false

    func resolvedEntryStyle() -> MemoEntryStyle {
        if entryStyle == .randomEdge {
            return [.dragFromLeft, .dragFromRight, .dragFromTop, .dragFromBottom].randomElement() ?? .dragFromLeft
        }
        return entryStyle
    }

    func resolvedExitStyle() -> MemoExitStyle {
        if exitStyle == .randomExit || randomizeExit {
            return [.dragAwayLeft, .dragAwayRight, .slideDown, .fadeOut, .gooseTakesItAway].randomElement() ?? .fadeOut
        }
        return exitStyle
    }
}

@MainActor
final class AnimationStudioStore: ObservableObject {
    static let shared = AnimationStudioStore()

    @Published var settings: AnimationStudioSettings {
        didSet { saveToDisk() }
    }

    private let storageURL: URL

    init(storageURL: URL? = nil) {
        self.storageURL = storageURL ?? UserContentManager.shared.settingsURL.appendingPathComponent("animation_studio.json")
        if let loaded = Self.load(from: self.storageURL) {
            self.settings = loaded
        } else {
            self.settings = AnimationStudioSettings()
        }
    }

    func resetDefaults() {
        settings = AnimationStudioSettings()
    }

    private static func load(from url: URL) -> AnimationStudioSettings? {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(AnimationStudioSettings.self, from: data) else {
            return nil
        }
        return decoded
    }

    private func saveToDisk() {
        do {
            try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(settings)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            FileHandle.standardError.write(Data("[Goose] AnimationStudioStore save error: \(error)\n".utf8))
        }
    }
}
