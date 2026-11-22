import AVFoundation
import Combine
import Foundation

enum AudioPackEvent: String, CaseIterable, Identifiable, Codable, Sendable {
    case gooseHonk
    case gooseLaugh
    case gooseAngry
    case gooseHappy
    case gooseSleep
    case memoDrag
    case memoDrop
    case memeAppearance
    case memeExit
    case interaction

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gooseHonk:      return "Goose Honk"
        case .gooseLaugh:     return "Goose Laugh"
        case .gooseAngry:     return "Goose Angry"
        case .gooseHappy:     return "Goose Happy"
        case .gooseSleep:     return "Goose Sleep"
        case .memoDrag:       return "Memo Drag"
        case .memoDrop:       return "Memo Drop"
        case .memeAppearance: return "Meme Appearance"
        case .memeExit:       return "Meme Exit"
        case .interaction:    return "Interaction"
        }
    }
}

struct AudioPackSound: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var filename: String
    var event: AudioPackEvent
    var volume: Double
    var enabled: Bool

    init(
        id: UUID = UUID(),
        name: String,
        filename: String,
        event: AudioPackEvent,
        volume: Double = 0.85,
        enabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.filename = filename
        self.event = event
        self.volume = min(1.0, max(0.0, volume))
        self.enabled = enabled
    }
}

struct CustomAudioPack: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var isBuiltIn: Bool
    var sounds: [AudioPackSound]

    init(id: UUID = UUID(), name: String, isBuiltIn: Bool = false, sounds: [AudioPackSound] = []) {
        self.id = id
        self.name = name
        self.isBuiltIn = isBuiltIn
        self.sounds = sounds
    }
}

enum QuietHoursMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case fullMute
    case disableHonksOnly
    case keepUISounds

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fullMute:         return "Full Mute"
        case .disableHonksOnly: return "Disable Goose Honks Only"
        case .keepUISounds:     return "Keep Essential UI Sounds"
        }
    }
}

struct QuietHoursConfig: Codable, Equatable, Sendable {
    var enabled: Bool = false
    var startHour: Int = 23
    var startMinute: Int = 0
    var endHour: Int = 7
    var endMinute: Int = 0
    /// Calendar weekday integers (1 = Sunday ... 7 = Saturday).
    var weekdays: Set<Int> = [1, 2, 3, 4, 5, 6, 7]
    var mode: QuietHoursMode = .fullMute

    func isActive(at date: Date = Date()) -> Bool {
        guard enabled else { return false }
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: date)
        guard weekdays.contains(weekday) else { return false }

        let hour = cal.component(.hour, from: date)
        let minute = cal.component(.minute, from: date)
        let nowMinutes = hour * 60 + minute
        let startMinutes = startHour * 60 + startMinute
        let endMinutes = endHour * 60 + endMinute

        if startMinutes == endMinutes { return true }
        if startMinutes < endMinutes {
            return nowMinutes >= startMinutes && nowMinutes < endMinutes
        } else {
            return nowMinutes >= startMinutes || nowMinutes < endMinutes
        }
    }
}

private struct AudioPacksDiskModel: Codable {
    var version: Int = 1
    var activePackID: UUID
    var packs: [CustomAudioPack]
    var quietHours: QuietHoursConfig
}

/// Manages custom user audio packs, event-to-sound mapping, preview playback,
/// and enhanced Quiet Hours configuration.
@MainActor
final class AudioPackManager: ObservableObject {
    static let shared = AudioPackManager()

    @Published private(set) var packs: [CustomAudioPack] = []
    @Published var activePackID: UUID {
        didSet { saveToDisk() }
    }
    @Published var quietHours: QuietHoursConfig {
        didSet {
            // Keep legacy GooseSettings fields synced.
            let s = GooseSettings.shared
            if s.nighttimeQuietHours != quietHours.enabled {
                s.nighttimeQuietHours = quietHours.enabled
            }
            if s.quietStartHour != quietHours.startHour {
                s.quietStartHour = quietHours.startHour
            }
            if s.quietEndHour != quietHours.endHour {
                s.quietEndHour = quietHours.endHour
            }
            saveToDisk()
        }
    }
    @Published var lastError: String?

    private let contentManager: UserContentManager
    private let storageURL: URL
    private var previewPlayer: AVAudioPlayer?
    private var activeEventPlayers: [AVAudioPlayer] = []

    var activePack: CustomAudioPack? {
        packs.first { $0.id == activePackID } ?? packs.first
    }

    init(contentManager: UserContentManager = .shared, storageURL: URL? = nil) {
        self.contentManager = contentManager
        self.storageURL = storageURL ?? contentManager.settingsURL.appendingPathComponent("audio_packs.json")

        let defaultPack = CustomAudioPack(name: "Default Goose Pack", isBuiltIn: true, sounds: [])
        self.packs = [defaultPack]
        self.activePackID = defaultPack.id
        self.quietHours = QuietHoursConfig(
            enabled: GooseSettings.shared.nighttimeQuietHours,
            startHour: GooseSettings.shared.quietStartHour,
            startMinute: 0,
            endHour: GooseSettings.shared.quietEndHour,
            endMinute: 0
        )

        loadFromDisk()
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            let decoded = try JSONDecoder().decode(AudioPacksDiskModel.self, from: data)
            if !decoded.packs.isEmpty {
                packs = decoded.packs
                activePackID = decoded.packs.contains(where: { $0.id == decoded.activePackID })
                    ? decoded.activePackID
                    : decoded.packs[0].id
            }
            quietHours = decoded.quietHours
        } catch {
            lastError = "Failed to load audio packs: \(error.localizedDescription)"
        }
    }

    private func saveToDisk() {
        let model = AudioPacksDiskModel(
            version: 1,
            activePackID: activePackID,
            packs: packs,
            quietHours: quietHours
        )
        do {
            try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(model)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            lastError = "Failed to save audio packs: \(error.localizedDescription)"
        }
    }

    // MARK: - Pack Management

    @discardableResult
    func createPack(name: String) -> CustomAudioPack {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let pack = CustomAudioPack(name: trimmed.isEmpty ? "Custom Pack \(packs.count)" : trimmed, isBuiltIn: false)
        packs.append(pack)
        activePackID = pack.id
        saveToDisk()
        return pack
    }

    func renamePack(_ id: UUID, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let idx = packs.firstIndex(where: { $0.id == id }) else { return }
        packs[idx].name = trimmed
        saveToDisk()
    }

    func deletePack(_ id: UUID) {
        guard let idx = packs.firstIndex(where: { $0.id == id }), !packs[idx].isBuiltIn else { return }
        packs.remove(at: idx)
        if activePackID == id, let first = packs.first {
            activePackID = first.id
        }
        saveToDisk()
    }

    // MARK: - Sound Management & Import

    @discardableResult
    func importSounds(from urls: [URL], for event: AudioPackEvent, intoPackID packID: UUID? = nil) -> (imported: Int, errors: [String]) {
        let targetPackID = packID ?? activePackID
        guard let packIdx = packs.firstIndex(where: { $0.id == targetPackID }) else {
            return (0, ["Target audio pack not found."])
        }

        let beforeFiles = Set(contentManager.sounds.map(\.filename))
        let result = contentManager.importSounds(from: urls)
        let newFiles = contentManager.sounds.filter { !beforeFiles.contains($0.filename) }

        for file in newFiles {
            let entry = AudioPackSound(
                name: (file.filename as NSString).deletingPathExtension,
                filename: file.filename,
                event: event
            )
            packs[packIdx].sounds.append(entry)
        }
        saveToDisk()
        lastError = result.errors.isEmpty ? nil : result.errors.joined(separator: "\n")
        return result
    }

    func updateSound(_ sound: AudioPackSound, inPackID packID: UUID) {
        guard let pIdx = packs.firstIndex(where: { $0.id == packID }),
              let sIdx = packs[pIdx].sounds.firstIndex(where: { $0.id == sound.id }) else { return }
        packs[pIdx].sounds[sIdx] = sound
        saveToDisk()
    }

    func deleteSound(_ sound: AudioPackSound, fromPackID packID: UUID) {
        guard let pIdx = packs.firstIndex(where: { $0.id == packID }) else { return }
        packs[pIdx].sounds.removeAll { $0.id == sound.id }
        let stillReferenced = packs.contains { $0.sounds.contains { $0.filename == sound.filename } }
        if !stillReferenced, let item = contentManager.sounds.first(where: { $0.filename == sound.filename }) {
            contentManager.deleteSound(item)
        }
        saveToDisk()
    }

    // MARK: - Playback

    func stopAll() {
        previewPlayer?.stop()
        previewPlayer = nil
        for p in activeEventPlayers { p.stop() }
        activeEventPlayers.removeAll()
    }

    @discardableResult
    func previewSound(_ sound: AudioPackSound) -> Bool {
        let url = contentManager.soundsURL.appendingPathComponent(sound.filename)
        guard FileManager.default.fileExists(atPath: url.path),
              let player = try? AVAudioPlayer(contentsOf: url) else {
            return false
        }
        previewPlayer?.stop()
        let s = GooseSettings.shared
        player.volume = Float(min(1.0, max(0.0, sound.volume * s.masterVolume)))
        player.prepareToPlay()
        player.play()
        previewPlayer = player
        return true
    }

    /// Plays a custom sound mapped to `event` from the active pack if available and enabled.
    /// Returns `true` if a custom sound played; `false` lets callers fall back to procedural DSP.
    @discardableResult
    func playEventSound(_ event: AudioPackEvent) -> Bool {
        let s = GooseSettings.shared
        guard s.masterSoundEnabled, !s.muteGoose else { return false }
        if quietHours.isActive() {
            switch quietHours.mode {
            case .fullMute:
                return false
            case .disableHonksOnly:
                if [.gooseHonk, .gooseLaugh, .gooseAngry, .gooseHappy].contains(event) { return false }
            case .keepUISounds:
                if [.gooseHonk, .gooseLaugh, .gooseAngry, .gooseHappy, .gooseSleep].contains(event) { return false }
            }
        }

        guard let pack = activePack else { return false }
        let matching = pack.sounds.filter { $0.event == event && $0.enabled }
        guard let pick = matching.randomElement() else { return false }

        let url = contentManager.soundsURL.appendingPathComponent(pick.filename)
        guard FileManager.default.fileExists(atPath: url.path),
              let player = try? AVAudioPlayer(contentsOf: url) else {
            return false
        }

        let isHonkEvent = [.gooseHonk, .gooseLaugh, .gooseAngry, .gooseHappy].contains(event)
        let level = Float(pick.volume * s.masterVolume * (isHonkEvent ? s.honkVolume : 1.0))
        player.volume = min(1.0, max(0.0, level))
        player.enableRate = true
        if s.randomPitchVariation {
            player.rate = Float.random(in: 0.93...1.07)
        }
        player.prepareToPlay()
        player.play()

        activeEventPlayers.removeAll { !$0.isPlaying }
        activeEventPlayers.append(player)
        return true
    }
}
