import Combine
import CoreGraphics
import Foundation
import SpriteKit

/// Unified lifecycle & tick manager for all active geese.
/// Hard-caps total population at `hardMaxGeese` (5) and coordinates all
/// tasks through `BehaviorScheduler` and `GlobalActionCoordinator` without
/// spawning per-goose timers.
@MainActor
final class GooseManager: ObservableObject {
    static let hardMaxGeese = 5

    @Published private(set) var geese: [GooseInstance] = []
    private var nextNumericID = 1

    var effectiveMaxCount: Int {
        min(Self.hardMaxGeese, max(1, GooseSettings.shared.maxGooseCount))
    }

    var count: Int { geese.count }

    var leadGoose: GooseInstance? {
        geese.first(where: \.isLead) ?? geese.first
    }

    func goose(withID id: UUID) -> GooseInstance? {
        geese.first { $0.id == id }
    }

    /// Spawns a new `GooseInstance` in `scene` if under the effective/hard cap.
    /// The first active goose is marked `isLead` so AI notes/Spotify/headphone
    /// features always have an owner.
    @discardableResult
    func spawnGoose(in scene: GooseScene, screenSize: CGSize) -> GooseInstance? {
        guard geese.count < effectiveMaxCount else { return nil }

        let assignLead = !geese.contains(where: \.isLead)
        let numID = geese.isEmpty ? 1 : max(nextNumericID, (geese.map(\.numericID).max() ?? 0) + 1)
        nextNumericID = max(nextNumericID, numID + 1)

        let instance = GooseInstance(numericID: numID, isLead: assignLead, screenSize: screenSize)
        if !assignLead && DisplayManager.shared.screenFrames.count > 1 {
            // Distribute companion geese across connected screens.
            let idx = (numID - 1) % DisplayManager.shared.screenFrames.count
            let pt = DisplayManager.shared.randomVisiblePoint(margin: 80, preferredScreenIndex: idx)
            instance.simulation.position = pt
            instance.simulation.targetPos = pt
            instance.simulation.lFootPos = instance.simulation.footHome(rightFoot: false)
            instance.simulation.rFootPos = instance.simulation.footHome(rightFoot: true)
        }
        let gid = instance.id
        instance.simulation.onFootLand = { [weak sim = instance.simulation] in
            guard let sim else { return }
            let moveSound: MovementSound = sim.speedTier == .walk ? .tinyFootstep : .runningFootstep
            _ = SoundEffectEngine.shared.playMovement(moveSound, category: .footsteps, priority: .low, cooldown: 0.22)
        }
        instance.simulation.onHonk = { [weak scene, weak sim = instance.simulation] in
            let sleeping = (sim?.currentTask is NapTask) || (sim?.currentTask is DeepSleepTask)
            scene?.playSoundEvent(.random, gooseID: gid, isSleeping: sleeping)
        }
        instance.simulation.onBite = {
            _ = SoundEffectEngine.shared.playMovement(.beakPeck, category: .footsteps, priority: .low, cooldown: 0.35)
        }

        instance.marksNode.zPosition = 5 + CGFloat(numID) * 0.1
        instance.container.zPosition = CGFloat(10 + numID * 20)
        scene.addChild(instance.marksNode)
        scene.addChild(instance.container)

        geese.append(instance)
        if !assignLead {
            NotificationManager.shared.post(
                category: .newGoose,
                title: "New Goose Joined",
                body: "Goose \(numID) has entered your desktop."
            )
        }
        return instance
    }

    /// Removes the specified goose (or the newest non-lead goose if `id == nil`).
    /// Releases all locks/tasks held by that goose before removal.
    @discardableResult
    func removeGoose(id: UUID? = nil) -> Bool {
        let index: Int?
        if let id {
            index = geese.firstIndex { $0.id == id }
        } else if let nonLead = geese.lastIndex(where: { !$0.isLead }) {
            index = nonLead
        } else {
            index = geese.indices.last
        }
        guard let idx = index else { return false }
        let removed = geese.remove(at: idx)
        SoundEffectEngine.shared.clearGooseState(for: removed.id)
        removed.teardown()
        return true
    }

    func removeAllGeese() {
        let copy = geese
        geese.removeAll()
        for g in copy {
            SoundEffectEngine.shared.clearGooseState(for: g.id)
            g.teardown()
        }
        nextNumericID = 1
    }

    func enforceCap() {
        let cap = effectiveMaxCount
        while geese.count > cap {
            guard removeGoose(id: nil) else { break }
        }
    }

    func allSimulations() -> [GooseSimulation] {
        geese.map(\.simulation)
    }

    /// Relocates any off-screen geese safely onto the nearest visible display
    /// when displays are disconnected or resolution/arrangement changes.
    func relocateOffscreenGeese(using displayManager: DisplayManager, newUnionSize: CGSize) {
        for goose in geese {
            goose.simulation.screenSize = newUnionSize
            let clampedPos = displayManager.clampToNearestVisibleDisplay(goose.simulation.position, margin: 45)
            if clampedPos != goose.simulation.position {
                goose.simulation.position = clampedPos
                goose.simulation.velocity = .zero2
                goose.simulation.lFootPos = goose.simulation.footHome(rightFoot: false)
                goose.simulation.rFootPos = goose.simulation.footHome(rightFoot: true)
            }
            goose.simulation.targetPos = displayManager.clampToNearestVisibleDisplay(goose.simulation.targetPos, margin: 45)
        }
    }

    /// Single unified per-frame update driving every goose, timeouts,
    /// personality evolution, companion decisions, and peer interactions.
    func tickAll(dt: TimeInterval, currentTime: TimeInterval, scene: GooseScene) {
        GameTime.tick(dt: dt)
        enforceCap()
        GlobalActionCoordinator.shared.tickTimeouts()

        let settings = GooseSettings.shared
        let controller = GooseController.shared

        for goose in geese {
            guard goose.isAlive else { continue }
            goose.personality.syncFromSettings()
            let isSleeping = goose.simulation.currentTask is NapTask || goose.simulation.currentTask is DeepSleepTask
            let isActive = !(goose.simulation.currentTask is WanderTask)
            goose.personality.tick(dt: dt, isSleeping: isSleeping, isActiveTask: isActive)

            goose.simulation.speedMultiplier = CGFloat(settings.movementSpeed * goose.personality.speedEmotionMultiplier)
            goose.simulation.animationMultiplier = CGFloat(settings.animationSpeed)
            goose.simulation.sizeScale = CGFloat(settings.gooseSize)

            var waitingForLock = false
            if !goose.isLead {
                thinkCompanion(goose, controller: controller, settings: settings, scene: scene)
                if case .waitingForLock = goose.aiState {
                    waitingForLock = true
                }
            }

            BehaviorScheduler.shared.tick(simulation: goose.simulation)
            goose.simulation.tick()
            goose.art.update(simulation: goose.simulation)
            if !waitingForLock {
                goose.refreshAIState(from: goose.simulation.currentTask)
            }

            let s = CGFloat(settings.gooseSize)
            let bob = goose.isLead ? scene.currentDanceBob : .zero
            goose.container.setScale(s)
            goose.container.position = CGPoint(
                x: goose.simulation.position.x * (1 - s) + bob.x,
                y: goose.simulation.position.y * (1 - s) + bob.y
            )
        }

        GooseInteractionSystem.shared.tick(geese: geese, scene: scene)
    }

    private func thinkCompanion(
        _ goose: GooseInstance,
        controller: GooseController,
        settings: GooseSettings,
        scene: GooseScene
    ) {
        let activityScale = FullscreenMonitor.shared.activityMultiplier
        guard controller.allowsProactive, settings.randomBehavior,
              activityScale > 0,
              GameTime.time >= goose.nextThinkTime else {
            return
        }
        goose.nextThinkTime = GameTime.time + CGFloat.random(in: 10...22) / CGFloat(max(0.1, settings.activityFrequency * activityScale))

        guard goose.simulation.currentTask is WanderTask else { return }

        let sleepWeight = settings.allows(.sleepMode) ? 0.16 * goose.personality.sleepMultiplier : 0
        let chaseWeight = settings.allows(.mouseChase) ? 0.14 * goose.personality.prankMultiplier : 0
        let theftWeight = settings.effectiveMouseTheft ? 0.08 * goose.personality.aggressionMultiplier * settings.mouseTheftProbability : 0
        let messWeight = settings.allows(.desktopMess) ? 0.10 * goose.personality.prankMultiplier : 0
        let peekWeight = settings.allows(.windowPeek) ? 0.10 * goose.personality.curiosityMultiplier : 0

        let roll = Double.random(in: 0..<1)
        if roll < sleepWeight {
            _ = BehaviorScheduler.shared.request(
                priority: .ambient,
                task: NapTask(personality: goose.personality),
                behavior: .sleepMode,
                timeout: 12,
                on: goose.simulation
            )
        } else if roll < sleepWeight + theftWeight {
            // Goes through GlobalActionCoordinator; gracefully falls back if lock is busy.
            let task = NabMouseTask(gooseID: goose.id, effects: scene, personality: goose.personality)
            if !BehaviorScheduler.shared.request(
                priority: .prank,
                task: task,
                behavior: .mouseTheft,
                timeout: settings.mouseChaseDuration + settings.mouseDragDuration + 2,
                on: goose.simulation
            ) {
                goose.aiState = .waitingForLock(.mouse)
            }
        } else if roll < sleepWeight + theftWeight + chaseWeight {
            _ = BehaviorScheduler.shared.request(
                priority: .prank,
                task: MouseChaseTask(effects: scene, personality: goose.personality),
                behavior: .mouseChase,
                timeout: settings.mouseChaseDuration + 2,
                on: goose.simulation
            )
        } else if roll < sleepWeight + theftWeight + chaseWeight + messWeight {
            _ = BehaviorScheduler.shared.request(
                priority: .prank,
                task: DesktopMessTask(effects: scene),
                behavior: .desktopMess,
                timeout: 18,
                on: goose.simulation
            )
        } else if roll < sleepWeight + theftWeight + chaseWeight + messWeight + peekWeight {
            _ = BehaviorScheduler.shared.request(
                priority: .prank,
                task: WindowPeekTask(effects: scene),
                behavior: .windowPeek,
                timeout: 14,
                on: goose.simulation
            )
        }
    }
}
