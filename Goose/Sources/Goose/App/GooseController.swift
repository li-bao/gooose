import AppKit
import Combine
import Foundation

/// Daily counters + last-prank record for the Control Center, plus the
/// optional interaction memory used by personality evolution.
@MainActor
final class GooseStats: ObservableObject {
    static let shared = GooseStats()

    enum Kind { case note, mouseTheft, window, music, rage }

    @Published private(set) var pranksToday = 0
    @Published private(set) var mouseTheftsToday = 0
    @Published private(set) var notesToday = 0
    @Published private(set) var lastPrank: String?
    @Published private(set) var lastPrankTime: Date?

    // Lifetime interaction memory (only persisted when Interaction Memory is on).
    @Published private(set) var patCount: Int
    @Published private(set) var pokeCount: Int
    @Published private(set) var windowsClosedCount: Int

    private let defaults = UserDefaults.standard
    private let dayKey = "stats.day"

    private init() {
        let d = UserDefaults.standard
        patCount = d.integer(forKey: "memory.pats")
        pokeCount = d.integer(forKey: "memory.pokes")
        windowsClosedCount = d.integer(forKey: "memory.windowsClosed")
        loadToday()
    }

    private static func today() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }

    private func loadToday() {
        if defaults.string(forKey: dayKey) == Self.today() {
            pranksToday = defaults.integer(forKey: "stats.pranks")
            mouseTheftsToday = defaults.integer(forKey: "stats.thefts")
            notesToday = defaults.integer(forKey: "stats.notes")
        } else {
            defaults.set(Self.today(), forKey: dayKey)
            pranksToday = 0; mouseTheftsToday = 0; notesToday = 0
            persistToday()
        }
    }

    private func persistToday() {
        defaults.set(pranksToday, forKey: "stats.pranks")
        defaults.set(mouseTheftsToday, forKey: "stats.thefts")
        defaults.set(notesToday, forKey: "stats.notes")
    }

    func recordPrank(_ description: String, kind: Kind) {
        if defaults.string(forKey: dayKey) != Self.today() { loadToday() }
        pranksToday += 1
        if kind == .note { notesToday += 1 }
        if kind == .mouseTheft { mouseTheftsToday += 1 }
        lastPrank = description
        lastPrankTime = Date()
        persistToday()
        GooseController.shared.noteprankHappened()
        NotificationManager.shared.post(category: .prank, title: "Goose Prank", body: description)
    }

    // MARK: Interaction memory + evolution

    enum Interaction { case pat, poke, windowClosed }

    func record(_ interaction: Interaction) {
        let s = GooseSettings.shared
        if s.interactionMemory {
            switch interaction {
            case .pat: patCount += 1; defaults.set(patCount, forKey: "memory.pats")
            case .poke: pokeCount += 1; defaults.set(pokeCount, forKey: "memory.pokes")
            case .windowClosed: windowsClosedCount += 1; defaults.set(windowsClosedCount, forKey: "memory.windowsClosed")
            }
        }
        switch interaction {
        case .pat: s.nudge(\.affectionate, by: 0.01)
        case .poke: s.nudge(\.aggressive, by: 0.02)
        case .windowClosed: s.nudge(\.naughty, by: 0.02)
        }
    }

    func clearMemory() {
        patCount = 0; pokeCount = 0; windowsClosedCount = 0
        for k in ["memory.pats", "memory.pokes", "memory.windowsClosed"] { defaults.removeObject(forKey: k) }
    }
}

struct GooseStatus: Identifiable, Sendable {
    let id: Int
    let gooseID: UUID
    let name: String
    let activity: String
    let isLead: Bool
    let personalitySummary: String
    let emotion: GooseEmotion
    let energyPercent: Int
    let holdingLock: String?
}

/// Runtime control plane shared by the menu bar, Control Center and scene.
/// Owns the run state (running / paused / hidden / emergency-stopped) and is
/// the one place that answers "may the goose act proactively right now?".
@MainActor
final class GooseController: ObservableObject {
    static let shared = GooseController()

    enum RunState: String, Sendable { case running, paused, hidden, stopped }

    @Published private(set) var state: RunState = .running
    @Published private(set) var geese: [GooseStatus] = []
    @Published private(set) var desktopMessCount = 0
    @Published private(set) var mouseLockHolderName: String?
    @Published private(set) var windowLockHolderName: String?

    weak var scene: GooseScene?
    weak var overlay: OverlayWindow?

    private(set) var lastPrankAt: Date = .distantPast
    @Published var audioAvailable = false

    let settings = GooseSettings.shared
    let stats = GooseStats.shared
    lazy var llm = SettingsAwareLLM()

    private init() {}

    // MARK: Gates

    /// Autonomous behavior (agent loop, honk ticker, chill ticker, reactive chases).
    var allowsProactive: Bool { state == .running }

    /// Simulation frames are frozen while paused or hidden.
    var simulationFrozen: Bool { state == .paused || state == .hidden }

    func prankCooldownElapsed() -> Bool {
        Date().timeIntervalSince(lastPrankAt) >= settings.behaviorCooldown
    }

    func noteprankHappened() { lastPrankAt = Date() }

    // MARK: Commands

    func pauseAll() {
        guard state != .paused else { return }
        let wasHidden = (state == .hidden)
        GameTime.setPaused(true)
        SoundEffectEngine.shared.stopAll()
        scene?.stopAudio()
        scene?.releaseAllControl()
        if !wasHidden {
            overlay?.orderFrontRegardless()
        }
        overlay?.setRenderingPaused(true)
        state = .paused
        refresh()
    }

    func resumeAll() {
        GameTime.setPaused(false)
        overlay?.orderFrontRegardless()
        overlay?.setRenderingPaused(false)
        state = .running
        scene?.restartAgentsIfNeeded()
        refresh()
    }

    func togglePause() {
        state == .running ? pauseAll() : resumeAll()
    }

    func hideAll() {
        GameTime.setPaused(true)
        SoundEffectEngine.shared.stopAll()
        scene?.stopAudio()
        scene?.releaseAllControl()
        overlay?.setRenderingPaused(true)
        overlay?.orderOut(nil)
        state = .hidden
        refresh()
    }

    func toggleHidden() {
        state == .hidden ? resumeAll() : hideAll()
    }

    func emergencyStop() {
        SoundEffectEngine.shared.stopAll()
        scene?.stopAudio()
        MemeWindowRegistry.shared.closeAll()
        NotepadWindowRegistry.shared.closeAll()
        scene?.releaseAllControl(closeWindows: true)
        state = .stopped
        refresh()
        FileHandle.standardError.write(Data("[Goose] EMERGENCY STOP: all proactive behavior halted, cursor and windows released\n".utf8))
    }

    func deliverMemeNow() {
        guard let picked = MemeLibraryStore.shared.pickWeightedMeme(includeManualOnly: true) else {
            if let fallback = UserContentManager.shared.pickNextMeme() {
                deliverMeme(fallback)
            }
            return
        }
        deliverMeme(picked.0)
    }

    func deliverMeme(_ item: MemeItem, caption: String = "") {
        guard let scene, let lead = scene.manager.leadGoose else { return }
        if state != .running { resumeAll() }
        let resolvedCaption = caption.isEmpty ? (TauntLibraryStore.shared.pickWeightedTaunt()?.content ?? "") : caption
        GooseStats.shared.recordPrank("Delivered meme: \(item.filename)", kind: .window)
        _ = BehaviorScheduler.shared.request(
            priority: .reactive,
            task: MemeDeliveryTask(gooseID: lead.id, item: item, caption: resolvedCaption, effects: scene),
            timeout: 26,
            on: lead.simulation
        )
    }

    func deliverNotepadNow() {
        if let taunt = TauntLibraryStore.shared.pickWeightedTaunt() {
            deliverTaunt(taunt.content, title: "\(taunt.category).txt")
            return
        }
        let pick = UserContentManager.shared.pickNextNotepadMessage()
        deliverTaunt(pick.body, title: pick.title)
    }

    func deliverTaunt(_ text: String, title: String = "goose-memo.txt") {
        guard let scene, let lead = scene.manager.leadGoose else { return }
        if state != .running { resumeAll() }
        GooseStats.shared.recordPrank("Dragged memo: \(title)", kind: .note)
        _ = BehaviorScheduler.shared.request(
            priority: .reactive,
            task: NotepadDeliveryTask(gooseID: lead.id, title: title, body: text, effects: scene),
            timeout: 26,
            on: lead.simulation
        )
    }

    func spawnGoose() {
        guard let scene else { return }
        if state == .hidden { resumeAll() }
        _ = scene.spawnGoose()
        refresh()
    }

    func removeGoose() {
        _ = scene?.removeGoose()
        refresh()
    }

    func removeAllGeese() {
        scene?.removeAllGeese()
        refresh()
    }

    func toggleMouseTheft() {
        settings.setEnabled(.mouseTheft, !settings.isEnabled(.mouseTheft))
        if !settings.effectiveMouseTheft { scene?.releaseMouseHolders() }
    }

    func toggleAllPranks() {
        settings.allPranksDisabled.toggle()
        if settings.allPranksDisabled {
            MemeWindowRegistry.shared.closeAll()
            NotepadWindowRegistry.shared.closeAll()
            scene?.releaseAllControl(closeWindows: true)
        }
    }

    func clearDesktopMess() {
        scene?.clearDesktopMess()
        refresh()
    }

    // MARK: Snapshot for UI

    func refresh() {
        let statuses = scene?.gooseStatuses() ?? []
        geese = statuses
        desktopMessCount = scene?.desktopMess.itemCount ?? 0
        let coord = GlobalActionCoordinator.shared
        mouseLockHolderName = coord.mouseHolderID.flatMap { id in statuses.first { $0.gooseID == id }?.name }
        windowLockHolderName = coord.windowHolderID.flatMap { id in statuses.first { $0.gooseID == id }?.name }
    }

    var gooseCount: Int { geese.count }
}
