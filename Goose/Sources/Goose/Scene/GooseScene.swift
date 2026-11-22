import AppKit
import SpriteKit

@MainActor
final class GooseScene: SKScene, GooseSceneEffects {
    private static let displayScale: CGFloat = 1.0

    let manager = GooseManager()
    let desktopMess = DesktopMessOverlay()

    private let fallbackSimulation = GooseSimulation()
    private let fallbackPersonality = GoosePersonality(isLead: true)
    private let audio = AudioPlayer()
    private let evictBar = EvictProgressBar()
    private let hearts = HeartParticles()
    private let headphones = HeadphonesNode()
    private let musicNotes = MusicNoteParticles()

    /// Lead goose shortcuts preserved so existing tests and single-goose callers work seamlessly.
    var simulation: GooseSimulation { manager.leadGoose?.simulation ?? fallbackSimulation }
    var leadPersonality: GoosePersonality { manager.leadGoose?.personality ?? fallbackPersonality }
    var currentDanceBob: CGPoint { danceBob }

    private var danceBob: CGPoint = .zero
    private var activeFakeErrors: [FakeErrorWindow] = []
    private var stolenIconNode: DesktopMessOverlay.VirtualItemNode?
    private let sleepLabel = SKLabelNode(text: "z Z z")
    private let tauntNode = SKNode()
    private let tauntLabel = SKLabelNode()
    private let tauntBackground = SKShapeNode()
    private var tauntHideWork: DispatchWorkItem?
    private var isSleepingVisual = false
    private var lastTickTime: TimeInterval = 0
    private var controller: GooseController { GooseController.shared }
    private var settings: GooseSettings { GooseSettings.shared }

    private var agent: AgentDirector?
    private var honkTicker: HonkTicker?
    private var chillingTicker: ChillingTicker?
    let perception = PerceptionEngine()
    private var isDancing = false
    private var danceStartTime: TimeInterval = 0

    /// Windows the goose has opened that we're watching for user-initiated
    /// close. When one closes while still in this set, the user did it →
    /// goose rages and chases the cursor.
    private var trackedGooseWindows: Set<NSWindow> = []
    private var closeObserver: NSObjectProtocol?
    private var currentDraggedWindow: FloatingWindow?
    private var droppedWindows: [FloatingWindow] = []

    private var lastLeftMouseDown = false
    private var hoverStartTime: TimeInterval = -1
    private var lastHeartSpawnTime: TimeInterval = -1
    private static let clickRadius: CGFloat = 50
    private static let hoverRadius: CGFloat = 60
    private static let hoverDelay: TimeInterval = 0.5
    private static let heartCooldown: TimeInterval = 0.7
    private static let droppedWindowFadeDuration: TimeInterval = 1.0

    override func didMove(to view: SKView) {
        scaleMode = .resizeFill
        anchorPoint = CGPoint(x: 0, y: 0)

        desktopMess.zPosition = 5
        addChild(desktopMess)

        sleepLabel.fontName = "HelveticaNeue-Bold"
        sleepLabel.fontSize = 14
        sleepLabel.fontColor = NSColor(calibratedRed: 0.35, green: 0.55, blue: 0.95, alpha: 0.95)
        sleepLabel.zPosition = 72
        sleepLabel.isHidden = true
        addChild(sleepLabel)

        tauntBackground.fillColor = NSColor(calibratedWhite: 0.1, alpha: 0.88)
        tauntBackground.strokeColor = NSColor(calibratedWhite: 1, alpha: 0.25)
        tauntBackground.lineWidth = 1
        tauntLabel.fontName = "HelveticaNeue-Medium"
        tauntLabel.fontSize = 12
        tauntLabel.fontColor = .white
        tauntLabel.verticalAlignmentMode = .center
        tauntNode.addChild(tauntBackground)
        tauntNode.addChild(tauntLabel)
        tauntNode.zPosition = 80
        tauntNode.isHidden = true
        addChild(tauntNode)

        evictBar.position = CGPoint(x: 16, y: size.height - 28)
        evictBar.zPosition = 100
        addChild(evictBar)

        hearts.zPosition = 70
        addChild(hearts)

        musicNotes.zPosition = 70
        addChild(musicNotes)

        controller.scene = self
        controller.audioAvailable = audio.didLoadAnything

        if let lead = manager.spawnGoose(in: self, screenSize: size / Self.displayScale) {
            attachHeadphones(to: lead)
            startAgents(for: lead)
        }

        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let win = note.object as? NSWindow else { return }
            MainActor.assumeIsolated {
                self?.handleWindowWillClose(win)
            }
        }
    }

    private func attachHeadphones(to lead: GooseInstance) {
        headphones.removeFromParent()
        lead.container.addChild(headphones)
    }

    private func handleWindowWillClose(_ window: NSWindow) {
        guard trackedGooseWindows.remove(window) != nil else { return }
        triggerRage()
    }

    private func triggerRage() {
        GooseStats.shared.record(.windowClosed)
        guard let lead = manager.leadGoose else { return }
        lead.personality.recordInterrupted()
        guard controller.allowsProactive, settings.allows(.angryMode) else { return }
        playSoundEvent(.rage)
        if GooseReactions.rage(on: lead.simulation, gooseID: lead.id, effects: self, personality: lead.personality) {
            FileHandle.standardError.write(Data("[Goose] rage: user closed a goose-opened window\n".utf8))
        }
    }

    // MARK: - Agents (AI loop, honk ticker, chill ticker)

    private func startAgents(for lead: GooseInstance) {
        guard agent == nil else { return }
        let personality = Personality.default
        let llm = controller.llm
        let brain = GooseBrain(personality: personality, llm: llm)
        let agent = AgentDirector(
            gooseID: lead.id,
            simulation: lead.simulation,
            effects: self,
            perception: perception,
            brain: brain,
            personality: lead.personality
        )
        self.agent = agent
        agent.start()

        let ticker = HonkTicker(simulation: lead.simulation, perception: perception)
        ticker.start()
        self.honkTicker = ticker

        let chillTicker = ChillingTicker(
            simulation: lead.simulation,
            perception: perception,
            effects: self,
            personality: personality,
            llm: llm
        )
        chillTicker.start()
        self.chillingTicker = chillTicker
    }

    private func stopAgents() {
        agent?.stop(); agent = nil
        honkTicker?.stop(); honkTicker = nil
        chillingTicker?.stop(); chillingTicker = nil
    }

    func restartAgentsIfNeeded() {
        if let lead = manager.leadGoose {
            startAgents(for: lead)
        }
    }

    // MARK: - Control plane (used by GooseController)

    var gooseCount: Int { manager.count }

    func gooseStatuses() -> [GooseStatus] {
        let coord = GlobalActionCoordinator.shared
        return manager.geese.map { g in
            let lockLabel: String?
            if coord.mouseHolderID == g.id {
                lockLabel = "Mouse Lock"
            } else if coord.windowHolderID == g.id {
                lockLabel = "Window Lock"
            } else {
                lockLabel = nil
            }
            return GooseStatus(
                id: g.numericID,
                gooseID: g.id,
                name: "Goose \(g.numericID)",
                activity: Self.describe(g.simulation.currentTask),
                isLead: g.isLead,
                personalitySummary: g.personality.summaryText,
                emotion: g.personality.emotion,
                energyPercent: g.energyPercent,
                holdingLock: lockLabel
            )
        }
    }

    private static func describe(_ task: GooseTask?) -> String {
        switch task {
        case let t as NabMouseTask: return t.isCapturing ? "Dragging your cursor" : "Chasing the mouse"
        case let t as MouseChaseTask: return t.isFleeing ? "Fleeing from cursor" : "Circling near cursor"
        case let s as GooseInteractionTask: return s.kind.displayName
        case is WindowPrankTask: return "Pushing a window"
        case is FakeErrorTask: return "Showing a fake error"
        case is DesktopMessTask: return "Making desktop mess"
        case is GooseTheftTask: return "Stealing a virtual icon"
        case is WindowPeekTask: return "Peeking from behind a window"
        case is WanderTask: return "Wandering"
        case is NapTask: return "Napping"
        case is DeepSleepTask: return "Deep sleep"
        case is DragWindowTask: return "Delivering a window"
        case is NotepadDeliveryTask: return "Delivering a notepad"
        case is MemeDeliveryTask: return "Delivering a meme"
        case is BrowseTask: return "Browsing the web"
        case is ChillingTask: return "Headbanging with headphones"
        case .none: return "Idle"
        default: return "Busy"
        }
    }

    @discardableResult
    func spawnGoose() -> Bool {
        guard let spawned = manager.spawnGoose(in: self, screenSize: size / Self.displayScale) else {
            return false
        }
        if spawned.isLead {
            attachHeadphones(to: spawned)
            startAgents(for: spawned)
        }
        return true
    }

    @discardableResult
    func removeGoose(id: UUID? = nil) -> Bool {
        let hadLead = manager.leadGoose != nil
        let targetIsLead = (id != nil && id == manager.leadGoose?.id) || (id == nil && manager.count == 1 && hadLead)
        let ok = manager.removeGoose(id: id)
        if ok && targetIsLead {
            stopAgents()
            closeGooseWindows()
            setHeadphones(visible: false)
            setMusicNotes(active: false)
            setDancing(active: false)
            setSleeping(active: false)
        }
        return ok
    }

    func removeAllGeese() {
        stopAgents()
        manager.removeAllGeese()
        closeGooseWindows()
        closeFakeErrorWindows()
        detachStolenVirtualIcon()
        setHeadphones(visible: false)
        setMusicNotes(active: false)
        setDancing(active: false)
        setSleeping(active: false)
    }

    /// Stops every active prank and hands back the cursor and windows.
    /// Does NOT quit the app.
    func releaseAllControl(closeWindows: Bool = false) {
        let wasChilling = manager.leadGoose?.simulation.currentTask is ChillingTask
        BehaviorScheduler.shared.emergencyStop(on: manager.allSimulations())
        if wasChilling { Task { await SpotifyController.pause() } }

        setHeadphones(visible: false)
        setMusicNotes(active: false)
        setDancing(active: false)
        setSleeping(active: false)
        detachStolenVirtualIcon()
        tauntNode.isHidden = true

        if closeWindows {
            closeGooseWindows()
            closeFakeErrorWindows()
        } else {
            detachDraggedWindow()
        }
    }

    func releaseMouseHolders() {
        NabMouseTask.releaseHolder()
    }

    func clearDesktopMess() {
        desktopMess.clearAll()
        for g in manager.geese { g.simulation.clearFootMarks() }
        detachStolenVirtualIcon()
        closeFakeErrorWindows()
    }

    private func closeFakeErrorWindows() {
        let copy = activeFakeErrors
        activeFakeErrors.removeAll()
        for err in copy {
            err.closeNow()
        }
    }

    private func closeGooseWindows() {
        if let w = currentDraggedWindow {
            trackedGooseWindows.remove(w.window)
            currentDraggedWindow = nil
            w.closeWithFade(duration: 0.2)
        }
        for w in droppedWindows {
            trackedGooseWindows.remove(w.window)
            w.closeWithFade(duration: 0.2)
        }
        droppedWindows.removeAll()
    }

    func handleScreenParametersChanged() {
        let unionSize = size / Self.displayScale
        manager.relocateOffscreenGeese(using: DisplayManager.shared, newUnionSize: unionSize)
        evictBar.position = CGPoint(x: 16, y: max(20, size.height - 28))
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        evictBar.position = CGPoint(x: 16, y: max(20, size.height - 28))
    }

    // MARK: - Frame loop

    override func update(_ currentTime: TimeInterval) {
        guard !controller.simulationFrozen else {
            GameTime.setPaused(true)
            lastTickTime = currentTime
            return
        }
        GameTime.setPaused(false)

        let dt = lastTickTime > 0 ? min(0.1, max(0, currentTime - lastTickTime)) : (1.0 / 60.0)
        lastTickTime = currentTime

        controller.overlay?.setPreferredFPS(FullscreenMonitor.shared.recommendedFPS)
        pollMouseInteraction()
        updateDanceBob(currentTime: currentTime)
        manager.tickAll(dt: dt, currentTime: currentTime, scene: self)

        if let lead = manager.leadGoose {
            if !headphones.isHidden || isSleepingVisual {
                var rig = GooseRig()
                rig.update(
                    position: lead.simulation.position,
                    directionDegrees: lead.simulation.direction,
                    neckLerp: lead.simulation.neckLerpPercent
                )
                if !headphones.isHidden {
                    headphones.update(headPoint: rig.neckHeadPoint, perpendicular: rig.perpendicular)
                }
                if isSleepingVisual {
                    let k = CGFloat(settings.gooseSize)
                    let pos = lead.simulation.position
                    sleepLabel.position = CGPoint(
                        x: pos.x + (rig.neckHeadPoint.x - pos.x) * k + 14,
                        y: pos.y + (rig.neckHeadPoint.y - pos.y) * k + 24 * k + CGFloat(sin(currentTime * 2.2) * 3)
                    )
                }
            }
        }
    }

    private func updateDanceBob(currentTime: TimeInterval) {
        guard isDancing else {
            danceBob = .zero
            return
        }
        let t = currentTime - danceStartTime
        let bobY = sin(t * .pi * 2 * 2.5) * 5
        let swayX = sin(t * .pi * 2 * 1.25) * 2
        danceBob = CGPoint(x: swayX, y: bobY)
    }

    override func willMove(from view: SKView) {
        stopAgents()
        musicNotes.stop()
        tauntHideWork?.cancel()
        tauntHideWork = nil
        headphones.removeAllActions()
        closeGooseWindows()
        closeFakeErrorWindows()
        detachStolenVirtualIcon()
        audio.stopAll()
        manager.removeAllGeese()
        trackedGooseWindows.removeAll()
        if let observer = closeObserver {
            NotificationCenter.default.removeObserver(observer)
            closeObserver = nil
        }
    }

    private func pollMouseInteraction() {
        let mouse = DisplayManager.shared.globalToScene(NSEvent.mouseLocation)
        let now = Double(GameTime.time)

        let leftPressed = NSEvent.pressedMouseButtons & 1 != 0
        let risingEdge = leftPressed && !lastLeftMouseDown
        lastLeftMouseDown = leftPressed

        let sizeScale = CGFloat(settings.gooseSize)
        if risingEdge {
            for goose in manager.geese where goose.isAlive && !(goose.simulation.currentTask is NabMouseTask) {
                if CGPoint.distance(mouse, goose.simulation.position) < Self.clickRadius * sizeScale {
                    GooseStats.shared.record(.poke)
                    goose.personality.recordClick()
                    if GooseReactions.startMouseChase(on: goose.simulation, gooseID: goose.id, priority: .userDirectControl, effects: self, personality: goose.personality) {
                        return
                    }
                }
            }
        }

        if let hoveredGoose = manager.geese.first(where: { $0.isAlive && CGPoint.distance(mouse, $0.simulation.position) < Self.hoverRadius * sizeScale }) {
            if hoverStartTime < 0 {
                hoverStartTime = now
                lastHeartSpawnTime = -1
            }
            let hovered = now - hoverStartTime
            let cooldownElapsed = now - lastHeartSpawnTime
            let heartCooldown = Self.heartCooldown / GooseSettings.traitFactor(hoveredGoose.personality.affectionate)
            if hovered > Self.hoverDelay, cooldownElapsed > heartCooldown {
                GooseStats.shared.record(.pat)
                hoveredGoose.personality.recordPat()
                hearts.spawn(at: CGPoint(x: hoveredGoose.simulation.position.x, y: hoveredGoose.simulation.position.y + 40 * sizeScale))
                audio.playEvent(.pat)
                lastHeartSpawnTime = now
            }
        } else {
            hoverStartTime = -1
        }
    }

    func setEvictProgress(_ progress: CGFloat) {
        evictBar.setProgress(progress)
    }

    // MARK: - GooseSceneEffects

    func attachDraggedWindow(_ window: FloatingWindow, at point: CGPoint, direction: CGFloat) {
        if let prev = currentDraggedWindow {
            trackedGooseWindows.remove(prev.window)
            prev.closeWithFade(duration: 0.3)
        }
        currentDraggedWindow = window
        window.window.alphaValue = 0
        let globalCenter = DisplayManager.shared.sceneToGlobal(windowCenter(beak: point, direction: direction, windowSize: window.size))
        window.setCenter(globalCenter)
        window.show()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            window.window.animator().alphaValue = 1
        }
        trackedGooseWindows.insert(window.window)
    }

    func updateDraggedWindowPosition(_ point: CGPoint, direction: CGFloat) {
        guard let window = currentDraggedWindow else { return }
        let globalCenter = DisplayManager.shared.sceneToGlobal(windowCenter(beak: point, direction: direction, windowSize: window.size))
        window.setCenter(globalCenter)
    }

    func setHeadphones(visible: Bool) {
        if visible { headphones.show() } else { headphones.hide() }
    }

    func setMusicNotes(active: Bool) {
        if active {
            musicNotes.start { [weak self] in
                guard let self, let lead = self.manager.leadGoose else { return .zero }
                var rig = GooseRig()
                rig.update(
                    position: lead.simulation.position,
                    directionDegrees: lead.simulation.direction,
                    neckLerp: lead.simulation.neckLerpPercent
                )
                let k = CGFloat(self.settings.gooseSize)
                let pos = lead.simulation.position
                let bob = self.danceBob
                return CGPoint(x: pos.x + (rig.neckHeadPoint.x - pos.x) * k + bob.x,
                               y: pos.y + (rig.neckHeadPoint.y - pos.y) * k + bob.y)
            }
        } else {
            musicNotes.stop()
        }
    }

    func setDancing(active: Bool) {
        isDancing = active
        if active {
            danceStartTime = CACurrentMediaTime()
        } else {
            danceBob = .zero
        }
    }

    func setSleeping(active: Bool) {
        isSleepingVisual = active
        sleepLabel.isHidden = !active
    }

    func showTaunt(_ text: String, at point: CGPoint) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        tauntHideWork?.cancel()
        tauntNode.removeAllActions()
        tauntLabel.text = trimmed
        let width = max(90, CGFloat(trimmed.count) * 7.2 + 20)
        tauntBackground.path = CGPath(roundedRect: CGRect(x: -width / 2, y: -13, width: width, height: 26), cornerWidth: 8, cornerHeight: 8, transform: nil)
        tauntNode.position = CGPoint(
            x: min(max(width * 0.5 + 16, point.x), max(width * 0.5 + 17, size.width - width * 0.5 - 16)),
            y: min(max(40, point.y + 38), max(41, size.height - 40))
        )
        tauntNode.alpha = 1
        tauntNode.isHidden = false

        let work = DispatchWorkItem { [weak self] in
            self?.tauntNode.run(.fadeOut(withDuration: 0.35)) {
                self?.tauntNode.isHidden = true
            }
        }
        tauntHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2, execute: work)
    }

    func showFakeError(style: FakeErrorWindow.Style, customText: String?) {
        let win = FakeErrorWindow(style: style, customMessage: customText) { [weak self] in
            self?.activeFakeErrors.removeAll { !$0.window.isVisible }
        }
        activeFakeErrors.append(win)
        win.show(autoDismissAfter: 15)
    }

    func spawnDesktopMess(at point: CGPoint, count: Int) {
        desktopMess.spawnMessBurst(near: point, count: count, within: size)
    }

    func takeVirtualIconForTheft() -> (label: String, position: CGPoint)? {
        guard let item = desktopMess.pickVirtualIcon() else { return nil }
        let label = item.label
        let pos = item.position
        desktopMess.removeItem(item)
        return (label, pos)
    }

    func attachStolenVirtualIcon(label: String, at point: CGPoint) {
        stolenIconNode?.removeFromParent()
        let node = DesktopMessOverlay.makeTransientIcon(label: label)
        node.zPosition = 25
        node.position = point
        addChild(node)
        stolenIconNode = node
    }

    func updateStolenVirtualIcon(at point: CGPoint) {
        stolenIconNode?.position = point
    }

    func detachStolenVirtualIcon() {
        stolenIconNode?.removeFromParent()
        stolenIconNode = nil
    }

    func playSoundEvent(_ event: HonkEvent, gooseID: UUID?, isSleeping: Bool) {
        audio.playEvent(event, gooseID: gooseID, isSleeping: isSleeping)
    }

    func stopAudio() {
        audio.stopAll()
    }

    func spawnHearts(at point: CGPoint, count: Int) {
        hearts.spawn(at: point, count: count)
    }

    func detachDraggedWindow() {
        guard let window = currentDraggedWindow else { return }
        currentDraggedWindow = nil
        droppedWindows.append(window)
        let toRemove = window
        let lifetime = max(5.0, settings.stickyNoteLifetime)
        DispatchQueue.main.asyncAfter(deadline: .now() + lifetime) { [weak self] in
            self?.fadeOutDroppedWindow(toRemove)
        }
    }

    private func fadeOutDroppedWindow(_ window: FloatingWindow) {
        droppedWindows.removeAll { $0 === window }
        trackedGooseWindows.remove(window.window)
        window.closeWithFade(duration: Self.droppedWindowFadeDuration)
    }

    // MARK: - Helpers

    private func windowCenter(beak: CGPoint, direction: CGFloat, windowSize: CGSize) -> CGPoint {
        let forward = CGPoint.fromAngleDegrees(direction)
        let offset = max(windowSize.width, windowSize.height) / 2 + 20
        return CGPoint(
            x: beak.x + forward.x * offset,
            y: beak.y + forward.y * offset + 10
        )
    }
}

private func / (size: CGSize, scale: CGFloat) -> CGSize {
    CGSize(width: size.width / scale, height: size.height / scale)
}

@MainActor
private final class EvictProgressBar: SKNode {
    private static let width: CGFloat = 320
    private static let height: CGFloat = 24

    private let background = SKShapeNode(rectOf: CGSize(width: width, height: height), cornerRadius: 4)
    private let fill = SKShapeNode()
    private let label = SKLabelNode(text: "Continue holding ESC to evict goose")

    override init() {
        super.init()
        background.fillColor = NSColor(calibratedRed: 0.72, green: 0.86, blue: 0.95, alpha: 1)
        background.strokeColor = .clear
        background.position = CGPoint(x: Self.width / 2, y: Self.height / 2)

        fill.fillColor = NSColor(calibratedRed: 1, green: 0.72, blue: 0.78, alpha: 1)
        fill.strokeColor = .clear

        label.fontName = "HelveticaNeue-Bold"
        label.fontSize = 13
        label.fontColor = NSColor(white: 0.15, alpha: 1)
        label.horizontalAlignmentMode = .left
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: 8, y: Self.height / 2)

        addChild(background)
        addChild(fill)
        addChild(label)
        alpha = 0
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("not used")
    }

    func setProgress(_ progress: CGFloat) {
        let clamped = max(0, min(1, progress))
        alpha = clamped > 0.05 ? min(1, (clamped - 0.05) / 0.15) : 0

        let path = CGMutablePath()
        path.addRect(CGRect(x: 0, y: 0, width: Self.width * clamped, height: Self.height))
        fill.path = path
    }
}
