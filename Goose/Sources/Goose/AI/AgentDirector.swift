import AppKit
import Foundation

/// Closes the loop between perception and brain: every N seconds, snapshots
/// the user's screen, asks the brain what the goose should do next, and
/// drives the corresponding task on the simulation.
@MainActor
final class AgentDirector {
    private static let firstTickDelay: Duration = .seconds(5)
    private static let recentActionsCap = 4

    private let gooseID: UUID
    private let perception: PerceptionEngine
    private let brain: GooseBrain
    private let goosePersonality: GoosePersonality?
    private weak var simulation: GooseSimulation?
    private weak var effects: GooseSceneEffects?
    private let scheduler = BehaviorScheduler.shared

    private var recentActions: [String] = []
    private var loopTask: Task<Void, Never>?

    init(
        gooseID: UUID = UUID(),
        simulation: GooseSimulation,
        effects: GooseSceneEffects,
        perception: PerceptionEngine,
        brain: GooseBrain,
        personality: GoosePersonality? = nil
    ) {
        self.gooseID = gooseID
        self.perception = perception
        self.brain = brain
        self.goosePersonality = personality
        self.simulation = simulation
        self.effects = effects
    }

    func start() {
        FileHandle.standardError.write(Data("AgentDirector: brain ready, starting loop\n".utf8))
        loopTask?.cancel()
        loopTask = Task { [weak self] in
            try? await Task.sleep(for: Self.firstTickDelay)
            await self?.loop()
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
    }

    private func loop() async {
        while !Task.isCancelled {
            await tick()
            let scale = max(0.2, FullscreenMonitor.shared.activityMultiplier)
            let seconds = Double.random(in: Tuning.agentLoopRange) / max(0.1, GooseSettings.shared.activityFrequency * scale)
            try? await Task.sleep(for: .seconds(seconds))
        }
    }

    private func tick() async {
        let settings = GooseSettings.shared
        guard GooseController.shared.allowsProactive, settings.randomBehavior else { return }
        if FullscreenMonitor.shared.activityMultiplier <= 0 {
            return
        }
        if let sim = simulation, (sim.currentTask is NapTask || sim.currentTask is DeepSleepTask) {
            // Do not interrupt a sleeping goose with autonomous pranks.
            return
        }
        let snapshot = await perception.captureSnapshot() ?? ContextSnapshot.empty()
        guard let decision = await brain.decide(snapshot: snapshot, recentActions: recentActions, personality: goosePersonality) else { return }
        execute(decision: decision)
        recentActions.append(decision.action.rawValue)
        if recentActions.count > Self.recentActionsCap {
            recentActions.removeFirst()
        }
    }

    private func execute(decision: GooseDecision) {
        guard let simulation, let effects else { return }
        let settings = GooseSettings.shared
        // State may have changed while the brain was thinking.
        guard GooseController.shared.allowsProactive else { return }

        switch decision.action {
        case .wander:
            return
        case .nap:
            scheduler.request(priority: .ambient, task: NapTask(effects: effects, personality: goosePersonality), behavior: .sleepMode, timeout: 12, on: simulation)
        case .deepSleep:
            scheduler.request(priority: .ambient, task: DeepSleepTask(effects: effects, personality: goosePersonality), behavior: .sleepMode, timeout: 95, on: simulation)
        case .note:
            guard scheduler.allowsTaskStart(priority: .prank, behavior: .stickyNotes, on: simulation) else { return }
            let title = decision.noteTitle.isEmpty ? "untitled.txt" : decision.noteTitle
            let body = decision.noteBody.isEmpty ? "honk" : decision.noteBody
            if settings.aiEnabled {
                NotificationManager.shared.post(
                    category: .aiMessage,
                    title: "Goose wrote \(title)",
                    body: body.replacingOccurrences(of: "\n", with: " ")
                )
            }
            GooseStats.shared.recordPrank("Sticky note: \(title)", kind: .note)
            scheduler.request(
                priority: .prank,
                task: DragWindowTask(gooseID: gooseID, effects: effects) {
                    FloatingWindow.note(title: title, body: body)
                },
                behavior: .stickyNotes,
                timeout: 30,
                on: simulation
            )
        case .photo:
            guard scheduler.allowsTaskStart(priority: .prank, behavior: .windowPranks, on: simulation) else { return }
            GooseStats.shared.recordPrank("Dragged a photo onto your screen", kind: .window)
            scheduler.request(
                priority: .prank,
                task: DragWindowTask(gooseID: gooseID, effects: effects) {
                    guard let pick = PhotoLibrary.randomImage() else {
                        FileHandle.standardError.write(Data("AgentDirector: no photos found in \(PhotoLibrary.directory().path) — skipping\n".utf8))
                        return nil
                    }
                    return FloatingWindow.photo(image: pick.image, title: pick.name)
                },
                behavior: .windowPranks,
                timeout: 30,
                on: simulation
            )
        case .browse:
            guard settings.allowWebBrowsing,
                  let url = decision.browseURL,
                  scheduler.allowsTaskStart(priority: .prank, behavior: .windowPranks, on: simulation) else { return }
            GooseStats.shared.recordPrank("Opened a web page: \(url.host ?? url.absoluteString)", kind: .window)
            scheduler.request(
                priority: .prank,
                task: BrowseTask(url: url, effects: effects),
                behavior: .windowPranks,
                timeout: Tuning.browseDwellSeconds + 5,
                on: simulation
            )
        case .chill:
            scheduler.request(priority: .ambient, task: ChillingTask(spotifyURI: decision.spotifyURI, effects: effects), behavior: .spotifyChill, timeout: 320, on: simulation)
        case .fakeError:
            scheduler.request(priority: .prank, task: FakeErrorTask(effects: effects, personality: goosePersonality), behavior: .fakeErrors, timeout: 10, on: simulation)
        case .desktopMess:
            scheduler.request(priority: .prank, task: DesktopMessTask(effects: effects), behavior: .desktopMess, timeout: 20, on: simulation)
        case .gooseTheft:
            scheduler.request(priority: .prank, task: GooseTheftTask(effects: effects), behavior: .gooseTheft, timeout: 16, on: simulation)
        case .windowPeek:
            scheduler.request(priority: .prank, task: WindowPeekTask(effects: effects), behavior: .windowPeek, timeout: 14, on: simulation)
        case .windowPrank:
            scheduler.request(priority: .prank, task: WindowPrankTask(gooseID: gooseID, effects: effects, personality: goosePersonality), behavior: .windowPranks, timeout: 14, on: simulation)
        case .mouseChase:
            scheduler.request(priority: .prank, task: MouseChaseTask(effects: effects, personality: goosePersonality), behavior: .mouseChase, timeout: settings.mouseChaseDuration + 2, on: simulation)
        case .mouseTheft:
            guard settings.effectiveMouseTheft else { return }
            scheduler.request(priority: .prank, task: NabMouseTask(gooseID: gooseID, priority: .normalPrank, effects: effects, personality: goosePersonality), behavior: .mouseTheft, timeout: settings.mouseChaseDuration + settings.mouseDragDuration + 4, on: simulation)
        }
    }
}
