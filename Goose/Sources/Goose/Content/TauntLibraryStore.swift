import Combine
import Foundation

enum TauntLibraryDefaults {
    static let defaultCategories: [String] = [
        "Insults",
        "Sarcasm",
        "Complaints",
        "Gaming",
        "Productivity",
        "Random Thoughts",
        "Compliments",
        "Custom",
    ]
}

struct TauntEntry: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var content: String
    var category: String
    var enabled: Bool
    var weight: Double
    var usageCount: Int
    var lastUsed: Date?

    init(
        id: UUID = UUID(),
        content: String,
        category: String = "Sarcasm",
        enabled: Bool = true,
        weight: Double = 1.0,
        usageCount: Int = 0,
        lastUsed: Date? = nil
    ) {
        self.id = id
        self.content = content
        self.category = category
        self.enabled = enabled
        self.weight = min(5.0, max(0.1, weight))
        self.usageCount = usageCount
        self.lastUsed = lastUsed
    }
}

private struct TauntLibraryDiskModel: Codable {
    var version: Int = 1
    var customCategories: [String] = []
    var disabledCategories: [String] = []
    var entries: [TauntEntry] = []
}

/// Persistent Custom Taunt Library supporting categories, search, weights,
/// category toggles, recency-penalized weighted selection, and migration from
/// legacy `UserContent/NotepadMessages/*.txt`.
@MainActor
final class TauntLibraryStore: ObservableObject {
    static let shared = TauntLibraryStore()

    @Published private(set) var entries: [TauntEntry] = []
    @Published private(set) var customCategories: [String] = []
    @Published private(set) var disabledCategories: Set<String> = []
    @Published var lastError: String?

    private let storageURL: URL

    var allCategories: [String] {
        var result = TauntLibraryDefaults.defaultCategories
        for cat in customCategories where !result.contains(cat) {
            result.append(cat)
        }
        return result
    }

    init(storageURL: URL? = nil, seedIfEmpty: Bool = true) {
        self.storageURL = storageURL ?? UserContentManager.shared.settingsURL.appendingPathComponent("taunt_library.json")
        loadFromDisk()
        if entries.isEmpty && seedIfEmpty {
            seedDefaults()
            saveToDisk()
        }
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            let decoded = try JSONDecoder().decode(TauntLibraryDiskModel.self, from: data)
            customCategories = decoded.customCategories
            disabledCategories = Set(decoded.disabledCategories)
            entries = decoded.entries
        } catch {
            lastError = "Failed to load taunt library: \(error.localizedDescription)"
        }
    }

    private func saveToDisk() {
        let model = TauntLibraryDiskModel(
            version: 1,
            customCategories: customCategories,
            disabledCategories: Array(disabledCategories).sorted(),
            entries: entries
        )
        do {
            try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(model)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            lastError = "Failed to save taunt library: \(error.localizedDescription)"
        }
    }

    private func seedDefaults() {
        let builtIn: [(String, String)] = [
            ("Sarcasm", "Oh, you're STILL staring at that bug? Bold strategy."),
            ("Sarcasm", "你真的覺得重開機就能解決一切嗎？🪿"),
            ("Productivity", "Hydration check. Your posture looks like a shrimp."),
            ("Productivity", "Tab count exceeded 40. Peace was never an option."),
            ("Insults", "Even a breadless pond is more productive than this."),
            ("Complaints", "You haven't petted the goose in 5 minutes. Unacceptable."),
            ("Gaming", "Skill issue. Definitely a skill issue."),
            ("Random Thoughts", "Honk. That is all. Carry on."),
            ("Compliments", "Honestly? You're doing great today. Still gonna steal your cursor though."),
        ]
        entries = builtIn.map { TauntEntry(content: $0.1, category: $0.0) }
    }

    // MARK: - CRUD & Categories

    @discardableResult
    func addTaunt(content: String, category: String = "Sarcasm", weight: Double = 1.0, enabled: Bool = true) -> TauntEntry? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let entry = TauntEntry(content: trimmed, category: category, enabled: enabled, weight: weight)
        entries.insert(entry, at: 0)
        saveToDisk()
        return entry
    }

    func updateTaunt(_ updated: TauntEntry) {
        guard let idx = entries.firstIndex(where: { $0.id == updated.id }) else { return }
        var copy = updated
        copy.weight = min(5.0, max(0.1, copy.weight))
        entries[idx] = copy
        saveToDisk()
    }

    func deleteTaunt(_ entry: TauntEntry) {
        entries.removeAll { $0.id == entry.id }
        saveToDisk()
    }

    @discardableResult
    func duplicateTaunt(_ entry: TauntEntry) -> TauntEntry {
        let copy = TauntEntry(
            content: entry.content,
            category: entry.category,
            enabled: entry.enabled,
            weight: entry.weight
        )
        if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
            entries.insert(copy, at: idx + 1)
        } else {
            entries.append(copy)
        }
        saveToDisk()
        return copy
    }

    func addCategory(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !allCategories.contains(trimmed) else { return }
        customCategories.append(trimmed)
        saveToDisk()
    }

    func toggleCategoryDisabled(_ category: String) {
        if disabledCategories.contains(category) {
            disabledCategories.remove(category)
        } else {
            disabledCategories.insert(category)
        }
        saveToDisk()
    }

    func isCategoryEnabled(_ category: String) -> Bool {
        !disabledCategories.contains(category)
    }

    // MARK: - Search & Smart Selection

    func filteredTaunts(search: String, category: String?) -> [TauntEntry] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return entries.filter { entry in
            let matchesCat = (category == nil || category == "All" || entry.category == category)
            guard matchesCat else { return false }
            if q.isEmpty { return true }
            return entry.content.lowercased().contains(q)
                || entry.category.lowercased().contains(q)
        }
    }

    /// Weighted selection avoiding disabled categories and short-term repeats.
    func pickWeightedTaunt(category: String? = nil) -> TauntEntry? {
        let now = Date()
        let candidates: [(TauntEntry, Double)] = entries.compactMap { entry in
            guard entry.enabled else { return nil }
            if let category, category != "All" {
                guard entry.category == category else { return nil }
            } else if disabledCategories.contains(entry.category) {
                return nil
            }

            var w = max(0.1, entry.weight)
            if let last = entry.lastUsed {
                let elapsed = now.timeIntervalSince(last)
                if elapsed < 120 {
                    w *= 0.15
                } else if elapsed < 360 {
                    w *= 0.50
                }
            }
            return (entry, w)
        }

        guard !candidates.isEmpty else { return nil }
        let total = candidates.reduce(0.0) { $0 + $1.1 }
        var roll = Double.random(in: 0..<max(0.0001, total))
        var chosen = candidates[0].0
        for (entry, w) in candidates {
            if roll < w {
                chosen = entry
                break
            }
            roll -= w
        }

        recordUsage(for: chosen.id)
        return chosen
    }

    func recordUsage(for id: UUID) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[idx].usageCount += 1
        entries[idx].lastUsed = Date()
        saveToDisk()
    }
}
