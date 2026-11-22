import AppKit
import Combine
import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum GoosePersonalityCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case sarcastic
    case aggressive
    case annoying
    case passiveAggressive
    case funny
    case friendly
    case chaotic
    case completelyRandom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sarcastic:         return "Sarcastic"
        case .aggressive:        return "Aggressive"
        case .annoying:          return "Annoying"
        case .passiveAggressive: return "Passive-aggressive"
        case .funny:             return "Funny"
        case .friendly:          return "Friendly"
        case .chaotic:           return "Chaotic"
        case .completelyRandom:  return "Completely random"
        }
    }
}

struct MemeItem: Identifiable, Equatable, Sendable {
    let id: String
    let url: URL
    let filename: String
    let fileSize: Int64
    let sha256: String
    let isAnimatedGIF: Bool
    let frameCount: Int
    let pixelSize: CGSize
}

struct CustomSoundItem: Identifiable, Equatable, Sendable {
    let id: String
    let url: URL
    let filename: String
    let fileSize: Int64
}

struct NotepadMessageItem: Identifiable, Equatable, Sendable {
    let id: String
    let url: URL
    let filename: String
    let content: String
}

struct PhrasePack: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let url: URL
    let phrases: [String]
}

enum UserContentError: LocalizedError, Sendable {
    case unsupportedFileType(String)
    case fileTooLarge(String)
    case corruptedOrUnreadable(String)
    case duplicateContent(String)
    case invalidFilename

    var errorDescription: String? {
        switch self {
        case .unsupportedFileType(let ext):
            return "Unsupported file type: .\(ext)"
        case .fileTooLarge(let name):
            return "\(name) exceeds the maximum allowed size (25 MB)."
        case .corruptedOrUnreadable(let name):
            return "\(name) is corrupted or cannot be decoded."
        case .duplicateContent(let name):
            return "\(name) is identical to an already imported file."
        case .invalidFilename:
            return "Filename cannot be empty or contain path separators."
        }
    }
}

/// Manages persistent user-imported Memes, Sounds, NotepadMessages, and PhrasePacks
/// under `~/Library/Application Support/Super Goose Desktop/UserContent/`.
@MainActor
final class UserContentManager: ObservableObject {
    static let shared = UserContentManager()

    static let maxImageBytes: Int64 = 25 * 1024 * 1024
    static let maxAudioBytes: Int64 = 25 * 1024 * 1024
    static let maxTextBytes: Int64 = 1 * 1024 * 1024

    static let supportedImageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp"]
    static let supportedAudioExtensions: Set<String> = ["wav", "mp3", "m4a", "aiff", "caf"]

    let rootURL: URL
    var memesURL: URL { rootURL.appendingPathComponent("Memes", isDirectory: true) }
    var soundsURL: URL { rootURL.appendingPathComponent("Sounds", isDirectory: true) }
    var notepadMessagesURL: URL { rootURL.appendingPathComponent("NotepadMessages", isDirectory: true) }
    var phrasePacksURL: URL { rootURL.appendingPathComponent("PhrasePacks", isDirectory: true) }
    var settingsURL: URL { rootURL.appendingPathComponent("Settings", isDirectory: true) }

    @Published private(set) var memes: [MemeItem] = []
    @Published private(set) var sounds: [CustomSoundItem] = []
    @Published private(set) var notepadMessages: [NotepadMessageItem] = []
    @Published private(set) var phrasePacks: [PhrasePack] = []
    @Published var lastErrorMessage: String?

    private var recentMemeIDs: [String] = []
    private var recentMessageHashes: [Int] = []
    private var watchers: [DispatchSourceFileSystemObject] = []
    private var reloadWorkItem: DispatchWorkItem?

    static func defaultRootURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport
            .appendingPathComponent("Super Goose Desktop", isDirectory: true)
            .appendingPathComponent("UserContent", isDirectory: true)
    }

    init(rootURL: URL? = nil, watchFilesystem: Bool = true) {
        self.rootURL = rootURL ?? Self.defaultRootURL()
        ensureDirectoryStructureAndSeeds()
        reloadAll()
        if watchFilesystem {
            startWatchingDirectories()
        }
    }

    // MARK: - Directory Setup & Non-Destructive Seeding

    func ensureDirectoryStructureAndSeeds() {
        let fm = FileManager.default
        let dirs = [rootURL, memesURL, soundsURL, notepadMessagesURL, phrasePacksURL, settingsURL]
        for dir in dirs {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        writeIfMissing(
            at: memesURL.appendingPathComponent("README.txt"),
            text: """
            Super Goose Desktop — Custom Memes
            Supported formats: PNG, JPG, JPEG, animated GIF (up to 25 MB).
            Drop images here or import them from Settings → Memes.
            Your files stay strictly local on this Mac.
            """
        )
        writeIfMissing(
            at: soundsURL.appendingPathComponent("README.txt"),
            text: """
            Super Goose Desktop — Custom Sounds
            Supported formats: WAV, MP3, M4A, AIFF, CAF (up to 25 MB).
            Drop sound effects here or import them from Settings → Audio.
            """
        )
        writeIfMissing(
            at: notepadMessagesURL.appendingPathComponent("README.txt"),
            text: """
            Super Goose Desktop — Notepad Messages
            Each .txt file (UTF-8) represents one complete multi-line notepad message.
            Supports Traditional Chinese, Simplified Chinese, English, and Emoji.
            """
        )
        writeIfMissing(
            at: phrasePacksURL.appendingPathComponent("README.txt"),
            text: """
            Super Goose Desktop — Phrase Packs
            Each .txt file is one pack (filename = pack name).
            Lines starting with # are treated as comments. Empty lines are ignored.
            """
        )

        writeIfMissing(
            at: notepadMessagesURL.appendingPathComponent("example.txt"),
            text: """
            我把你的備忘錄拖出來了 🪿
            (I dragged your notepad out here.)

            記得喝水，不要一直盯著螢幕看。
            """
        )

        writeIfMissing(
            at: phrasePacksURL.appendingPathComponent("example.txt"),
            text: Self.defaultExamplePhrasePackText
        )

        // Seed Example.png only if no image files exist yet in Memes/.
        let existingImages = (try? fm.contentsOfDirectory(at: memesURL, includingPropertiesForKeys: nil))?
            .filter { Self.supportedImageExtensions.contains($0.pathExtension.lowercased()) } ?? []
        if existingImages.isEmpty {
            seedExampleMemePNG(at: memesURL.appendingPathComponent("Example.png"))
        }
    }

    func restoreDefaultPhrases() {
        let packURL = phrasePacksURL.appendingPathComponent("example.txt")
        try? Self.defaultExamplePhrasePackText.write(to: packURL, atomically: true, encoding: .utf8)
        let msgURL = notepadMessagesURL.appendingPathComponent("example.txt")
        let msg = """
        我把你的備忘錄拖出來了 🪿
        (I dragged your notepad out here.)

        記得喝水，不要一直盯著螢幕看。
        """
        try? msg.write(to: msgURL, atomically: true, encoding: .utf8)
        reloadAll()
    }

    private func writeIfMissing(at url: URL, text: String) {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func seedExampleMemePNG(at url: URL) {
        let w = 360, h = 240
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }

        ctx.setFillColor(NSColor(calibratedRed: 0.98, green: 0.95, blue: 0.85, alpha: 1).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(NSColor(calibratedRed: 0.95, green: 0.55, blue: 0.12, alpha: 1).cgColor)
        ctx.fill(CGRect(x: 20, y: 20, width: w - 40, height: 14))

        guard let cgImage = ctx.makeImage() else { return }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        rep.size = NSSize(width: w, height: h)
        NSGraphicsContext.saveGraphicsState()
        if let gCtx = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.current = gCtx
            let title = "HONK. 🪿\nPeace was never an option."
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 22),
                .foregroundColor: NSColor(calibratedWhite: 0.15, alpha: 1)
            ]
            title.draw(in: NSRect(x: 28, y: 55, width: w - 56, height: 140), withAttributes: attrs)
        }
        NSGraphicsContext.restoreGraphicsState()

        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - Reloading

    func reloadAll() {
        loadMemes()
        loadSounds()
        loadNotepadMessages()
        loadPhrasePacks()
    }

    private func loadMemes() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: memesURL,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            memes = []
            return
        }

        var loaded: [MemeItem] = []
        for url in entries.sorted(by: { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }) {
            let ext = url.pathExtension.lowercased()
            guard Self.supportedImageExtensions.contains(ext) else { continue }
            if let item = Self.inspectMemeFile(at: url) {
                loaded.append(item)
            }
        }
        memes = loaded
    }

    private func loadSounds() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: soundsURL,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            sounds = []
            return
        }
        sounds = entries
            .filter { Self.supportedAudioExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            .map { url in
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
                return CustomSoundItem(id: url.lastPathComponent, url: url, filename: url.lastPathComponent, fileSize: size)
            }
    }

    private func loadNotepadMessages() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: notepadMessagesURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            notepadMessages = []
            return
        }
        var items: [NotepadMessageItem] = []
        for url in entries.sorted(by: { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }) {
            guard url.pathExtension.lowercased() == "txt",
                  url.lastPathComponent.caseInsensitiveCompare("README.txt") != .orderedSame else { continue }
            guard let text = Self.readValidatedUTF8(at: url) else { continue }
            items.append(NotepadMessageItem(id: url.lastPathComponent, url: url, filename: url.lastPathComponent, content: text))
        }
        notepadMessages = items
    }

    private func loadPhrasePacks() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: phrasePacksURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            phrasePacks = []
            return
        }
        var packs: [PhrasePack] = []
        for url in entries.sorted(by: { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }) {
            guard url.pathExtension.lowercased() == "txt",
                  url.lastPathComponent.caseInsensitiveCompare("README.txt") != .orderedSame else { continue }
            guard let text = Self.readValidatedUTF8(at: url) else { continue }
            let phrases = Self.parsePhrasePackLines(text)
            let name = url.deletingPathExtension().lastPathComponent
            packs.append(PhrasePack(id: url.lastPathComponent, name: name, url: url, phrases: phrases))
        }
        phrasePacks = packs
    }

    // MARK: - Parsing & Inspection Helpers

    static func parsePhrasePackLines(_ text: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            if seen.insert(trimmed).inserted {
                result.append(trimmed)
            }
        }
        return result
    }

    static func inspectMemeFile(at url: URL) -> MemeItem? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64,
              size > 0, size <= maxImageBytes else {
            return nil
        }
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        let count = CGImageSourceGetCount(source)
        guard count > 0, let firstFrame = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let isGIF = url.pathExtension.lowercased() == "gif" && count > 1
        return MemeItem(
            id: url.lastPathComponent,
            url: url,
            filename: url.lastPathComponent,
            fileSize: size,
            sha256: digest,
            isAnimatedGIF: isGIF,
            frameCount: count,
            pixelSize: CGSize(width: firstFrame.width, height: firstFrame.height)
        )
    }

    private static func readValidatedUTF8(at url: URL) -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64,
              size > 0, size <= maxTextBytes,
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Importing, Deleting & Renaming

    @discardableResult
    func importMemes(from urls: [URL]) -> (imported: Int, errors: [String]) {
        var count = 0
        var errors: [String] = []
        let existingHashes = Set(memes.map(\.sha256))
        var batchHashes = existingHashes

        for src in urls {
            let scoped = src.startAccessingSecurityScopedResource()
            defer { if scoped { src.stopAccessingSecurityScopedResource() } }

            let ext = src.pathExtension.lowercased()
            guard Self.supportedImageExtensions.contains(ext) else {
                errors.append(UserContentError.unsupportedFileType(ext).localizedDescription)
                continue
            }
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: src.path),
                  let size = attrs[.size] as? Int64,
                  size <= Self.maxImageBytes else {
                errors.append(UserContentError.fileTooLarge(src.lastPathComponent).localizedDescription)
                continue
            }
            guard let inspected = Self.inspectMemeFile(at: src) else {
                errors.append(UserContentError.corruptedOrUnreadable(src.lastPathComponent).localizedDescription)
                continue
            }
            guard !batchHashes.contains(inspected.sha256) else {
                errors.append(UserContentError.duplicateContent(src.lastPathComponent).localizedDescription)
                continue
            }

            let dest = uniqueDestinationURL(in: memesURL, preferredFilename: src.lastPathComponent)
            do {
                try FileManager.default.copyItem(at: src, to: dest)
                batchHashes.insert(inspected.sha256)
                count += 1
            } catch {
                errors.append(error.localizedDescription)
            }
        }

        lastErrorMessage = errors.first
        reloadAll()
        return (count, errors)
    }

    func deleteMeme(_ item: MemeItem) {
        try? FileManager.default.removeItem(at: item.url)
        recentMemeIDs.removeAll { $0 == item.id }
        reloadAll()
    }

    func renameMeme(_ item: MemeItem, to newName: String) throws {
        let clean = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !clean.contains("/"), !clean.contains("\\") else {
            throw UserContentError.invalidFilename
        }
        let ext = item.url.pathExtension
        let finalName = clean.lowercased().hasSuffix(".\(ext.lowercased())") ? clean : "\(clean).\(ext)"
        let dest = memesURL.appendingPathComponent(finalName)
        guard dest != item.url else { return }
        try FileManager.default.moveItem(at: item.url, to: dest)
        recentMemeIDs.removeAll { $0 == item.id }
        reloadAll()
    }

    @discardableResult
    func importSounds(from urls: [URL]) -> (imported: Int, errors: [String]) {
        var count = 0
        var errors: [String] = []
        for src in urls {
            let scoped = src.startAccessingSecurityScopedResource()
            defer { if scoped { src.stopAccessingSecurityScopedResource() } }

            let ext = src.pathExtension.lowercased()
            guard Self.supportedAudioExtensions.contains(ext) else {
                errors.append(UserContentError.unsupportedFileType(ext).localizedDescription)
                continue
            }
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: src.path),
                  let size = attrs[.size] as? Int64,
                  size > 0, size <= Self.maxAudioBytes else {
                errors.append(UserContentError.fileTooLarge(src.lastPathComponent).localizedDescription)
                continue
            }
            let dest = uniqueDestinationURL(in: soundsURL, preferredFilename: src.lastPathComponent)
            do {
                try FileManager.default.copyItem(at: src, to: dest)
                count += 1
            } catch {
                errors.append(error.localizedDescription)
            }
        }
        lastErrorMessage = errors.first
        reloadAll()
        return (count, errors)
    }

    func deleteSound(_ item: CustomSoundItem) {
        try? FileManager.default.removeItem(at: item.url)
        reloadAll()
    }

    @discardableResult
    func importNotepadMessages(from urls: [URL]) -> (imported: Int, errors: [String]) {
        importTextFiles(from: urls, into: notepadMessagesURL)
    }

    func saveNotepadMessage(filename: String, content: String) {
        let clean = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !clean.contains("/") else { return }
        let name = clean.lowercased().hasSuffix(".txt") ? clean : "\(clean).txt"
        let dest = notepadMessagesURL.appendingPathComponent(name)
        try? content.write(to: dest, atomically: true, encoding: .utf8)
        reloadAll()
    }

    func deleteNotepadMessage(_ item: NotepadMessageItem) {
        try? FileManager.default.removeItem(at: item.url)
        reloadAll()
    }

    @discardableResult
    func importPhrasePacks(from urls: [URL]) -> (imported: Int, errors: [String]) {
        importTextFiles(from: urls, into: phrasePacksURL)
    }

    func deletePhrasePack(_ pack: PhrasePack) {
        try? FileManager.default.removeItem(at: pack.url)
        reloadAll()
    }

    private func importTextFiles(from urls: [URL], into directory: URL) -> (imported: Int, errors: [String]) {
        var count = 0
        var errors: [String] = []
        for src in urls {
            let scoped = src.startAccessingSecurityScopedResource()
            defer { if scoped { src.stopAccessingSecurityScopedResource() } }

            guard src.pathExtension.lowercased() == "txt" else {
                errors.append(UserContentError.unsupportedFileType(src.pathExtension).localizedDescription)
                continue
            }
            guard Self.readValidatedUTF8(at: src) != nil else {
                errors.append(UserContentError.corruptedOrUnreadable(src.lastPathComponent).localizedDescription)
                continue
            }
            let dest = uniqueDestinationURL(in: directory, preferredFilename: src.lastPathComponent)
            do {
                try FileManager.default.copyItem(at: src, to: dest)
                count += 1
            } catch {
                errors.append(error.localizedDescription)
            }
        }
        lastErrorMessage = errors.first
        reloadAll()
        return (count, errors)
    }

    private func uniqueDestinationURL(in dir: URL, preferredFilename: String) -> URL {
        let fm = FileManager.default
        let candidate = dir.appendingPathComponent(preferredFilename)
        if !fm.fileExists(atPath: candidate.path) { return candidate }
        let base = (preferredFilename as NSString).deletingPathExtension
        let ext = (preferredFilename as NSString).pathExtension
        var idx = 2
        while true {
            let next = ext.isEmpty ? "\(base)-\(idx)" : "\(base)-\(idx).\(ext)"
            let url = dir.appendingPathComponent(next)
            if !fm.fileExists(atPath: url.path) { return url }
            idx += 1
        }
    }

    // MARK: - Selection

    func pickNextMeme() -> MemeItem? {
        guard !memes.isEmpty else { return nil }
        let nonRecent = memes.filter { !recentMemeIDs.contains($0.id) }
        let pool = nonRecent.isEmpty ? memes : nonRecent
        guard let picked = pool.randomElement() else { return nil }
        recentMemeIDs.append(picked.id)
        let cap = max(1, memes.count - 1)
        if recentMemeIDs.count > cap {
            recentMemeIDs.removeFirst(recentMemeIDs.count - cap)
        }
        return picked
    }

    func pickNextNotepadMessage(
        category: GoosePersonalityCategory = GooseSettings.shared.personalityCategory,
        preventRepeat: Bool = GooseSettings.shared.preventRepeatedMessages
    ) -> (title: String, body: String) {
        let disabled = Set(GooseSettings.shared.disabledPhrasePacks)
        var candidates: [(title: String, body: String)] = []

        for msg in notepadMessages {
            candidates.append((msg.filename, msg.content))
        }
        for pack in phrasePacks where !disabled.contains(pack.id) {
            for phrase in pack.phrases {
                candidates.append(("\(pack.name).txt", phrase))
            }
        }
        candidates.append(contentsOf: Self.builtInMessages(for: category))

        let filtered: [(title: String, body: String)]
        if preventRepeat {
            let unrepeated = candidates.filter { !recentMessageHashes.contains($0.body.hashValue) }
            filtered = unrepeated.isEmpty ? candidates : unrepeated
        } else {
            filtered = candidates
        }

        let pick = filtered.randomElement() ?? ("goose.txt", "HONK.")
        recentMessageHashes.append(pick.body.hashValue)
        if recentMessageHashes.count > 12 {
            recentMessageHashes.removeFirst(recentMessageHashes.count - 12)
        }
        return pick
    }

    func isPackEnabled(_ pack: PhrasePack) -> Bool {
        !GooseSettings.shared.disabledPhrasePacks.contains(pack.id)
    }

    func setPack(_ pack: PhrasePack, enabled: Bool) {
        var list = GooseSettings.shared.disabledPhrasePacks
        if enabled {
            list.removeAll { $0 == pack.id }
        } else if !list.contains(pack.id) {
            list.append(pack.id)
        }
        GooseSettings.shared.disabledPhrasePacks = list
    }

    func openUserContentInFinder() {
        ensureDirectoryStructureAndSeeds()
        NSWorkspace.shared.activateFileViewerSelecting([rootURL])
    }

    // MARK: - Filesystem Watching

    private func startWatchingDirectories() {
        for dir in [memesURL, soundsURL, notepadMessagesURL, phrasePacksURL] {
            let fd = open(dir.path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .delete, .rename, .extend],
                queue: .main
            )
            source.setEventHandler { [weak self] in
                Task { @MainActor [weak self] in
                    self?.scheduleReload()
                }
            }
            source.setCancelHandler { close(fd) }
            source.resume()
            watchers.append(source)
        }
    }

    private func scheduleReload() {
        reloadWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.reloadAll()
            }
        }
        reloadWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: item)
    }

    // MARK: - Default Content Pools

    private static let defaultExamplePhrasePackText = """
    # My sarcastic goose pack

    你真的覺得這樣能成功嗎？

    這就是你今天的工作效率？

    我看不懂，但我大受震撼。

    Peace was never an option.

    又在浪費時間了？
    """

    private static func builtInMessages(for category: GoosePersonalityCategory) -> [(title: String, body: String)] {
        switch category {
        case .sarcastic:
            return [
                ("review.txt", "你真的覺得這樣能成功嗎？"),
                ("tabs.txt", "Another tab won't solve the problem."),
                ("status.txt", "我看不懂，但我大受震撼。")
            ]
        case .aggressive:
            return [
                ("warning.txt", "Peace was never an option. 🪿"),
                ("mouse.txt", "That cursor belongs to me now."),
                ("honk.txt", "HONK. Do not resist.")
            ]
        case .annoying:
            return [
                ("hey.txt", "hey\nhey\nhey\nhonk"),
                ("reminder.txt", "又在浪費時間了？"),
                ("poke.txt", "I am walking across your screen again.")
            ]
        case .passiveAggressive:
            return [
                ("efficiency.txt", "這就是你今天的工作效率？"),
                ("fine.txt", "Oh sure, ignore the goose. That's fine."),
                ("draft.txt", "Interesting choice. Truly.")
            ]
        case .funny:
            return [
                ("todo.txt", "1. Steal cursor\n2. Honk\n3. Refuse to elaborate"),
                ("bio.txt", "Professional desktop menace since 2019."),
                ("snack.txt", "Have you considered bread?")
            ]
        case .friendly:
            return [
                ("hydrate.txt", "記得喝水休息一下！💧"),
                ("cheer.txt", "You're doing great — even a goose approves."),
                ("hi.txt", "Quack! Just checking on you 🦆")
            ]
        case .chaotic:
            return [
                ("chaos.txt", "HONK QUACK HONK 🌀"),
                ("math.txt", "42 tabs + 1 goose = productivity"),
                ("lore.txt", "The duck and the goose have formed a union.")
            ]
        case .completelyRandom:
            return GoosePersonalityCategory.allCases
                .filter { $0 != .completelyRandom }
                .flatMap { builtInMessages(for: $0) }
        }
    }
}
