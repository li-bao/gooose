import Foundation

enum GooseEmotion: String, CaseIterable, Identifiable, Codable, Sendable {
    case happy
    case angry
    case bored
    case excited
    case sleepy
    case curious
    case mischievous

    var id: String { rawValue }

    var title: String {
        switch self {
        case .happy:       return "Happy"
        case .angry:       return "Angry"
        case .bored:       return "Bored"
        case .excited:     return "Excited"
        case .sleepy:      return "Sleepy"
        case .curious:     return "Curious"
        case .mischievous: return "Mischievous"
        }
    }

    var badgeSymbol: String {
        switch self {
        case .happy:       return "face.smiling"
        case .angry:       return "flame.fill"
        case .bored:       return "cloud"
        case .excited:     return "sparkles"
        case .sleepy:      return "moon.zzz.fill"
        case .curious:     return "magnifyingglass"
        case .mischievous: return "theatermasks.fill"
        }
    }
}

struct PersistedGooseState: Codable, Equatable, Sendable {
    var numericID: Int
    var emotion: GooseEmotion
    var energy: Double
    var naughty: Double
    var aggressive: Double
    var laziness: Double
    var curious: Double
    var affectionate: Double
    var savedAt: Date
}

private struct GooseStatesDiskModel: Codable {
    var version: Int = 1
    var states: [Int: PersistedGooseState] = [:]
}

/// Persists per-goose Emotion, Energy (0...100), and evolved traits cleanly
/// across app launches without clamping bugs or unbounded accumulation.
@MainActor
final class GooseStatePersistence {
    static let shared = GooseStatePersistence()

    private var states: [Int: PersistedGooseState] = [:]
    private let storageURL: URL

    init(storageURL: URL? = nil) {
        self.storageURL = storageURL ?? UserContentManager.shared.settingsURL.appendingPathComponent("goose_states.json")
        loadFromDisk()
    }

    func state(for numericID: Int) -> PersistedGooseState? {
        states[numericID]
    }

    func saveState(
        numericID: Int,
        emotion: GooseEmotion,
        energy: Double,
        naughty: Double,
        aggressive: Double,
        laziness: Double,
        curious: Double,
        affectionate: Double
    ) {
        let clampedEnergy = min(100.0, max(0.0, energy))
        let clamp01: (Double) -> Double = { min(1.0, max(0.0, $0)) }
        states[numericID] = PersistedGooseState(
            numericID: numericID,
            emotion: emotion,
            energy: clampedEnergy,
            naughty: clamp01(naughty),
            aggressive: clamp01(aggressive),
            laziness: clamp01(laziness),
            curious: clamp01(curious),
            affectionate: clamp01(affectionate),
            savedAt: Date()
        )
        persistToDisk()
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: storageURL.path),
              let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode(GooseStatesDiskModel.self, from: data) else {
            return
        }
        states = decoded.states
    }

    private func persistToDisk() {
        let model = GooseStatesDiskModel(version: 1, states: states)
        do {
            try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(model)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            FileHandle.standardError.write(Data("[Goose] GooseStatePersistence save error: \(error)\n".utf8))
        }
    }
}
