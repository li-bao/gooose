import AppKit
import Combine
import Foundation

enum MemeLibraryDefaults {
    static let defaultCategories: [String] = [
        "Random Memes",
        "Sarcastic",
        "Angry",
        "Funny",
        "Reaction",
        "Gaming",
        "Work",
        "Custom",
    ]
}

struct MemeMetadata: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var filename: String
    var displayName: String
    var category: String
    var enabled: Bool
    var manualOnly: Bool
    var weight: Double
    var usageCount: Int
    var lastUsed: Date?
    var tags: [String]
    var sortOrder: Int
    var bookmarkData: Data?

    init(
        id: UUID = UUID(),
        filename: String,
        displayName: String? = nil,
        category: String = "Random Memes",
        enabled: Bool = true,
        manualOnly: Bool = false,
        weight: Double = 1.0,
        usageCount: Int = 0,
        lastUsed: Date? = nil,
        tags: [String] = [],
        sortOrder: Int = 0,
        bookmarkData: Data? = nil
    ) {
        self.id = id
        self.filename = filename
        self.displayName = displayName ?? (filename as NSString).deletingPathExtension
        self.category = category
        self.enabled = enabled
        self.manualOnly = manualOnly
        self.weight = min(5.0, max(0.1, weight))
        self.usageCount = usageCount
        self.lastUsed = lastUsed
        self.tags = tags
        self.sortOrder = sortOrder
        self.bookmarkData = bookmarkData
    }
}

private struct MemeLibraryDiskModel: Codable {
    var version: Int = 1
    var customCategories: [String] = []
    var items: [MemeMetadata] = []
}

/// Manages rich metadata, categories, ordering, weighted non-repeating selection,
/// and local JSON persistence for `UserContentManager` memes.
@MainActor
final class MemeLibraryStore: ObservableObject {
    static let shared = MemeLibraryStore()

    @Published private(set) var items: [MemeMetadata] = []
    @Published private(set) var customCategories: [String] = []
    @Published var lastError: String?

    private let contentManager: UserContentManager
    private let storageURL: URL
    private var cancellable: AnyCancellable?

    var allCategories: [String] {
        var result = MemeLibraryDefaults.defaultCategories
        for cat in customCategories where !result.contains(cat) {
            result.append(cat)
        }
        return result
    }

    init(contentManager: UserContentManager = .shared, storageURL: URL? = nil) {
        self.contentManager = contentManager
        self.storageURL = storageURL ?? contentManager.settingsURL.appendingPathComponent("meme_library.json")
        loadFromDisk()
        syncWithContentManager()

        cancellable = contentManager.$memes
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncWithContentManager()
            }
    }

    // MARK: - Sync & Persistence

    func syncWithContentManager() {
        let diskFiles = contentManager.memes
        let diskByFilename = Dictionary(uniqueKeysWithValues: diskFiles.map { ($0.filename, $0) })
        let existingFilenames = Set(items.map(\.filename))

        // Remove entries whose backing file was deleted or moved outside UserContent/Memes.
        items.removeAll { diskByFilename[$0.filename] == nil }

        // Append metadata for newly discovered files.
        var nextOrder = (items.map(\.sortOrder).max() ?? -1) + 1
        for file in diskFiles where !existingFilenames.contains(file.filename) {
            items.append(MemeMetadata(filename: file.filename, sortOrder: nextOrder))
            nextOrder += 1
        }

        items.sort { $0.sortOrder < $1.sortOrder }
        saveToDisk()
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            let decoded = try JSONDecoder().decode(MemeLibraryDiskModel.self, from: data)
            customCategories = decoded.customCategories
            items = decoded.items
        } catch {
            lastError = "Failed to load meme library metadata: \(error.localizedDescription)"
        }
    }

    private func saveToDisk() {
        let model = MemeLibraryDiskModel(version: 1, customCategories: customCategories, items: items)
        do {
            let dir = storageURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(model)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            lastError = "Failed to save meme library metadata: \(error.localizedDescription)"
        }
    }

    // MARK: - Import, Edit, Reorder, Delete

    @discardableResult
    func importMemes(from urls: [URL], category: String = "Random Memes") -> (imported: Int, errors: [String]) {
        let beforeFilenames = Set(contentManager.memes.map(\.filename))
        let result = contentManager.importMemes(from: urls)

        // Attach security-scoped bookmark (best effort) & chosen category to newly imported files.
        let bookmarkByName: [String: Data] = Dictionary(
            urls.compactMap { url -> (String, Data)? in
                guard let bm = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) else {
                    return nil
                }
                return (url.lastPathComponent, bm)
            },
            uniquingKeysWith: { first, _ in first }
        )

        syncWithContentManager()
        let resolvedCategory = allCategories.contains(category) ? category : "Random Memes"
        for idx in items.indices where !beforeFilenames.contains(items[idx].filename) {
            items[idx].category = resolvedCategory
            if let bm = bookmarkByName[items[idx].filename] {
                items[idx].bookmarkData = bm
            }
        }
        saveToDisk()
        lastError = result.errors.isEmpty ? nil : result.errors.joined(separator: "\n")
        return result
    }

    func updateMetadata(_ updated: MemeMetadata) {
        guard let idx = items.firstIndex(where: { $0.id == updated.id }) else { return }
        var copy = updated
        copy.weight = min(5.0, max(0.1, copy.weight))
        items[idx] = copy
        saveToDisk()
    }

    func renameMeme(_ metadata: MemeMetadata, to newName: String) {
        guard let memeItem = memeItem(for: metadata) else { return }
        do {
            let oldName = memeItem.filename
            try contentManager.renameMeme(memeItem, to: newName)
            syncWithContentManager()
            if let newFile = contentManager.memes.first(where: { $0.filename != oldName && !items.contains(where: { $0.filename == $0.filename && $0.id != metadata.id }) }) {
                _ = newFile
            }
            if let idx = items.firstIndex(where: { $0.id == metadata.id }) {
                items[idx].displayName = newName
                saveToDisk()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func deleteMeme(_ metadata: MemeMetadata) {
        if let memeItem = memeItem(for: metadata) {
            contentManager.deleteMeme(memeItem)
        }
        items.removeAll { $0.id == metadata.id }
        saveToDisk()
    }

    func reorder(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        items.move(fromOffsets: offsets, toOffset: destination)
        for idx in items.indices {
            items[idx].sortOrder = idx
        }
        saveToDisk()
    }

    func addCustomCategory(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !allCategories.contains(trimmed) else { return }
        customCategories.append(trimmed)
        saveToDisk()
    }

    func deleteCustomCategory(_ name: String) {
        customCategories.removeAll { $0 == name }
        for idx in items.indices where items[idx].category == name {
            items[idx].category = "Random Memes"
        }
        saveToDisk()
    }

    // MARK: - Query & Weighted Selection

    func memeItem(for metadata: MemeMetadata) -> MemeItem? {
        contentManager.memes.first { $0.filename == metadata.filename }
    }

    func filteredMemes(search: String, category: String?) -> [MemeMetadata] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return items.filter { item in
            let matchesCat = (category == nil || category == "All" || item.category == category)
            guard matchesCat else { return false }
            if q.isEmpty { return true }
            return item.displayName.lowercased().contains(q)
                || item.filename.lowercased().contains(q)
                || item.category.lowercased().contains(q)
                || item.tags.contains { $0.lowercased().contains(q) }
        }
    }

    /// Weighted random meme selection that respects `enabled`, `manualOnly`,
    /// optional `category`, and penalizes recently used items.
    func pickWeightedMeme(category: String? = nil, includeManualOnly: Bool = false) -> (MemeItem, MemeMetadata)? {
        let now = Date()
        let candidates: [(MemeItem, MemeMetadata, Double)] = items.compactMap { meta in
            guard meta.enabled, (includeManualOnly || !meta.manualOnly) else { return nil }
            if let category, category != "All", meta.category != category { return nil }
            guard let file = memeItem(for: meta) else { return nil }
            var effectiveWeight = max(0.1, meta.weight)
            if let last = meta.lastUsed {
                let elapsed = now.timeIntervalSince(last)
                if elapsed < 120 {
                    effectiveWeight *= 0.20
                } else if elapsed < 360 {
                    effectiveWeight *= 0.55
                }
            }
            return (file, meta, effectiveWeight)
        }

        guard !candidates.isEmpty else { return nil }
        let total = candidates.reduce(0.0) { $0 + $1.2 }
        var roll = Double.random(in: 0..<max(0.0001, total))
        var picked = candidates[0]
        for cand in candidates {
            if roll < cand.2 {
                picked = cand
                break
            }
            roll -= cand.2
        }

        recordUsage(for: picked.1.id)
        return (picked.0, picked.1)
    }

    func recordUsage(for id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].usageCount += 1
        items[idx].lastUsed = Date()
        saveToDisk()
    }
}
