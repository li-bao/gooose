import Combine
import Foundation

enum BuiltInPresetID: String, CaseIterable, Sendable {
    case peaceful
    case normal
    case mischievous
    case chaos
}

struct PrankPreset: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var builtInKey: String?
    var name: String
    var summary: String
    var isBuiltIn: Bool

    var activityFrequency: Double
    var prankFrequency: Double
    var behaviorCooldown: Double
    var mouseTheftProbability: Double
    var randomHonkFrequency: RandomHonkFrequency
    var honkCooldown: Double

    var memesEnabled: Bool
    var notepadDeliveriesEnabled: Bool
    var windowPranksEnabled: Bool
    var mouseTheftEnabled: Bool
    var desktopMessEnabled: Bool
    var fakeErrorsEnabled: Bool
}

private struct PrankPresetsDiskModel: Codable {
    var version: Int = 1
    var activePresetID: UUID?
    var customPresets: [PrankPreset] = []
}

/// Manages 4 built-in Prank Presets (Peaceful, Normal, Mischievous, Chaos)
/// plus user-created Custom Presets. Switching presets updates runtime behavior
/// tunables without ever overwriting custom Meme/Taunt/Audio libraries.
@MainActor
final class PrankPresetManager: ObservableObject {
    static let shared = PrankPresetManager()

    @Published private(set) var builtInPresets: [PrankPreset] = PrankPresetManager.makeBuiltIns()
    @Published private(set) var customPresets: [PrankPreset] = []
    @Published private(set) var activePresetID: UUID?
    @Published var lastError: String?

    private let storageURL: URL

    var allPresets: [PrankPreset] {
        builtInPresets + customPresets
    }

    init(storageURL: URL? = nil) {
        self.storageURL = storageURL ?? UserContentManager.shared.settingsURL.appendingPathComponent("prank_presets.json")
        loadFromDisk()
    }

    static func makeBuiltIns() -> [PrankPreset] {
        [
            PrankPreset(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                builtInKey: BuiltInPresetID.peaceful.rawValue,
                name: "Peaceful Mode",
                summary: "Low activity, minimal pranks, rare honks, cozy companion vibes.",
                isBuiltIn: true,
                activityFrequency: 0.45,
                prankFrequency: 0.25,
                behaviorCooldown: 60.0,
                mouseTheftProbability: 0.0,
                randomHonkFrequency: .low,
                honkCooldown: 40.0,
                memesEnabled: true,
                notepadDeliveriesEnabled: true,
                windowPranksEnabled: false,
                mouseTheftEnabled: false,
                desktopMessEnabled: false,
                fakeErrorsEnabled: false
            ),
            PrankPreset(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                builtInKey: BuiltInPresetID.normal.rawValue,
                name: "Normal Mode",
                summary: "Balanced activity, occasional Memo Editor notes, memes, and moderate sound.",
                isBuiltIn: true,
                activityFrequency: 1.0,
                prankFrequency: 1.0,
                behaviorCooldown: 20.0,
                mouseTheftProbability: 0.75,
                randomHonkFrequency: .low,
                honkCooldown: 20.0,
                memesEnabled: true,
                notepadDeliveriesEnabled: true,
                windowPranksEnabled: true,
                mouseTheftEnabled: true,
                desktopMessEnabled: true,
                fakeErrorsEnabled: true
            ),
            PrankPreset(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
                builtInKey: BuiltInPresetID.mischievous.rawValue,
                name: "Mischievous Mode",
                summary: "More taunts, more memes, frequent window peeks & playful pranks.",
                isBuiltIn: true,
                activityFrequency: 1.6,
                prankFrequency: 1.9,
                behaviorCooldown: 10.0,
                mouseTheftProbability: 0.9,
                randomHonkFrequency: .medium,
                honkCooldown: 15.0,
                memesEnabled: true,
                notepadDeliveriesEnabled: true,
                windowPranksEnabled: true,
                mouseTheftEnabled: true,
                desktopMessEnabled: true,
                fakeErrorsEnabled: true
            ),
            PrankPreset(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
                builtInKey: BuiltInPresetID.chaos.rawValue,
                name: "Chaos Mode",
                summary: "High activity, maximum memes & pranks while keeping Mouse/Window Lock & Honk Cooldown safe.",
                isBuiltIn: true,
                activityFrequency: 2.5,
                prankFrequency: 2.8,
                behaviorCooldown: 4.0,
                mouseTheftProbability: 1.0,
                randomHonkFrequency: .high,
                honkCooldown: 10.0,
                memesEnabled: true,
                notepadDeliveriesEnabled: true,
                windowPranksEnabled: true,
                mouseTheftEnabled: true,
                desktopMessEnabled: true,
                fakeErrorsEnabled: true
            ),
        ]
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            let decoded = try JSONDecoder().decode(PrankPresetsDiskModel.self, from: data)
            customPresets = decoded.customPresets
            activePresetID = decoded.activePresetID
        } catch {
            lastError = "Failed to load prank presets: \(error.localizedDescription)"
        }
    }

    private func saveToDisk() {
        let model = PrankPresetsDiskModel(version: 1, activePresetID: activePresetID, customPresets: customPresets)
        do {
            try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(model)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            lastError = "Failed to save prank presets: \(error.localizedDescription)"
        }
    }

    func applyPreset(_ preset: PrankPreset) {
        let s = GooseSettings.shared
        s.activityFrequency = min(4.0, max(0.25, preset.activityFrequency))
        s.prankFrequency = min(4.0, max(0.1, preset.prankFrequency))
        s.behaviorCooldown = min(120.0, max(0.0, preset.behaviorCooldown))
        s.mouseTheftProbability = min(1.0, max(0.0, preset.mouseTheftProbability))
        s.randomHonkFrequency = preset.randomHonkFrequency
        // Always preserve a safe honk cooldown floor (>= 8s) even in Chaos Mode.
        s.honkCooldown = min(90.0, max(8.0, preset.honkCooldown))

        s.memesEnabled = preset.memesEnabled
        s.notepadDeliveriesEnabled = preset.notepadDeliveriesEnabled
        s.setEnabled(.windowPranks, preset.windowPranksEnabled)
        s.setEnabled(.mouseTheft, preset.mouseTheftEnabled)
        s.setEnabled(.desktopMess, preset.desktopMessEnabled)
        s.setEnabled(.fakeErrors, preset.fakeErrorsEnabled)

        activePresetID = preset.id
        saveToDisk()
    }

    @discardableResult
    func createCustomPreset(name: String, summary: String = "Custom user preset") -> PrankPreset {
        let s = GooseSettings.shared
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let preset = PrankPreset(
            id: UUID(),
            builtInKey: nil,
            name: trimmed.isEmpty ? "Custom Preset \(customPresets.count + 1)" : trimmed,
            summary: summary,
            isBuiltIn: false,
            activityFrequency: s.activityFrequency,
            prankFrequency: s.prankFrequency,
            behaviorCooldown: s.behaviorCooldown,
            mouseTheftProbability: s.mouseTheftProbability,
            randomHonkFrequency: s.randomHonkFrequency,
            honkCooldown: s.honkCooldown,
            memesEnabled: s.memesEnabled,
            notepadDeliveriesEnabled: s.notepadDeliveriesEnabled,
            windowPranksEnabled: s.isEnabled(.windowPranks),
            mouseTheftEnabled: s.isEnabled(.mouseTheft),
            desktopMessEnabled: s.isEnabled(.desktopMess),
            fakeErrorsEnabled: s.isEnabled(.fakeErrors)
        )
        customPresets.append(preset)
        activePresetID = preset.id
        saveToDisk()
        return preset
    }

    @discardableResult
    func duplicatePreset(_ source: PrankPreset) -> PrankPreset {
        var copy = source
        copy.id = UUID()
        copy.builtInKey = nil
        copy.isBuiltIn = false
        copy.name = "\(source.name) Copy"
        customPresets.append(copy)
        saveToDisk()
        return copy
    }

    func updateCustomPreset(_ updated: PrankPreset) {
        guard !updated.isBuiltIn,
              let idx = customPresets.firstIndex(where: { $0.id == updated.id }) else { return }
        customPresets[idx] = updated
        if activePresetID == updated.id {
            applyPreset(updated)
        } else {
            saveToDisk()
        }
    }

    func deleteCustomPreset(_ preset: PrankPreset) {
        guard !preset.isBuiltIn else { return }
        customPresets.removeAll { $0.id == preset.id }
        if activePresetID == preset.id {
            activePresetID = nil
        }
        saveToDisk()
    }
}
