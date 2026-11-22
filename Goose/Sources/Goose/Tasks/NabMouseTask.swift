import AppKit
import CoreGraphics
import Foundation

/// Goose chases the cursor; once close enough it "captures" the cursor and
/// drags it across the screen using `CGWarpMouseCursorPosition`. Mirrors the
/// chase / drag staging from the original `Task_NabMouse`.
@MainActor
final class NabMouseTask: GooseTask {
    private static let captureDistance: CGFloat = 18
    private static let dropDistance: CGFloat = 30
    private static let mudDuration: CGFloat = 12.0

    private enum Stage {
        case chase
        case drag
    }

    /// Only one goose may own the cursor at a time (arbitrated by `GlobalActionCoordinator`).
    let gooseID: UUID
    private let priority: ActionPriority
    private weak var effects: GooseSceneEffects?
    private weak var personality: GoosePersonality?
    private var mouseLease: ResourceLease?

    private var stage: Stage = .chase
    private var willSteal = true
    private var ownsCursor = false

    /// For the Control Center.
    var isCapturing: Bool { stage == .drag }
    private var stageEndTime: CGFloat = 0
    private var nextDirectionShiftTime: CGFloat = 0
    private var directionShiftsRemaining = 0
    private var dragTarget: CGPoint = .zero2
    private var didRecordSteal = false

    init(
        gooseID: UUID = UUID(),
        priority: ActionPriority = .normalPrank,
        effects: GooseSceneEffects? = nil,
        personality: GoosePersonality? = nil
    ) {
        self.gooseID = gooseID
        self.priority = priority
        self.effects = effects
        self.personality = personality
    }

    func start(simulation: GooseSimulation) {
        let settings = GooseSettings.shared
        let totalBudget = TimeInterval(settings.mouseChaseDuration + settings.mouseDragDuration + 4.0)
        guard let lease = GlobalActionCoordinator.shared.acquireLock(
            for: gooseID,
            resource: .mouse,
            priority: priority,
            timeout: totalBudget,
            onCancel: { [weak simulation] in
                if let simulation, simulation.currentTask is NabMouseTask {
                    simulation.setTask(WanderTask())
                }
            }
        ) else {
            // Another goose already holds Mouse Lock: do not compete or touch cursor.
            willSteal = false
            ownsCursor = false
            DispatchQueue.main.async { [weak simulation] in
                if simulation?.currentTask is NabMouseTask {
                    simulation?.setTask(WanderTask())
                }
            }
            return
        }

        mouseLease = lease
        ownsCursor = true
        didRecordSteal = false
        simulation.setSpeed(.run)
        simulation.trackMudEndTime = max(simulation.trackMudEndTime, GameTime.time + Self.mudDuration)
        effects?.playSoundEvent(.theft) ?? simulation.onHonk?()
        stage = .chase
        let aggr = personality?.aggressionMultiplier ?? GooseSettings.traitFactor(settings.aggressive)
        let theftChance = min(1, settings.mouseTheftProbability * aggr)
        willSteal = settings.effectiveMouseTheft && Double.random(in: 0..<1) < theftChance
        stageEndTime = GameTime.time + CGFloat(settings.mouseChaseDuration)
    }

    func stop(simulation: GooseSimulation) {
        if let lease = mouseLease {
            mouseLease = nil
            GlobalActionCoordinator.shared.releaseLock(lease, status: didRecordSteal ? .completed : .cancelled)
        }
        if didRecordSteal {
            let beak = simulation.beakPosition
            let p = personality
            let eff = effects
            Task { @MainActor in
                let line = await GooseController.shared.llm.generateTaunt(personality: p, event: "stole mouse cursor")
                eff?.showTaunt(line, at: beak)
            }
            didRecordSteal = false
        }
        ownsCursor = false
    }

    /// Force-release (Emergency Stop / disabling theft). Safe to call anytime.
    static func releaseHolder() {
        if let id = GlobalActionCoordinator.shared.mouseHolderID {
            GlobalActionCoordinator.shared.releaseAllLocks(for: id)
        }
    }

    func tick(simulation: GooseSimulation) {
        guard ownsCursor, let lease = mouseLease, GlobalActionCoordinator.shared.isValidLease(lease) else {
            simulation.setTask(WanderTask())
            return
        }
        switch stage {
        case .chase:
            tickChase(simulation: simulation)
        case .drag:
            tickDrag(simulation: simulation, lease: lease)
        }
    }

    private func tickChase(simulation: GooseSimulation) {
        let mouse = DisplayManager.shared.globalToScene(NSEvent.mouseLocation)
        simulation.targetPos = CGPoint(x: mouse.x, y: mouse.y - 23 * simulation.sizeScale)
        let beak = simulation.beakPosition
        let captureRadius = Self.captureDistance * max(1, simulation.sizeScale)

        if CGPoint.distance(beak, mouse) < captureRadius {
            let settings = GooseSettings.shared
            guard willSteal else {
                // Caught up with the cursor but chose (or is not allowed) to let go.
                simulation.onHonk?()
                simulation.setTask(WanderTask())
                return
            }
            GooseStats.shared.recordPrank("Stole the mouse cursor", kind: .mouseTheft)
            guard settings.allows(.mouseDragging) else {
                effects?.playSoundEvent(.theft) ?? simulation.onHonk?()
                simulation.setTask(WanderTask())
                return
            }
            didRecordSteal = true
            stage = .drag
            let dragDuration = CGFloat(max(2.0, settings.mouseDragDuration))
            stageEndTime = GameTime.time + dragDuration
            directionShiftsRemaining = Int.random(in: 1...2)
            nextDirectionShiftTime = GameTime.time + dragDuration * CGFloat.random(in: 0.35...0.55)
            dragTarget = pickDragTarget(simulation: simulation)
            simulation.targetPos = dragTarget
            effects?.playSoundEvent(.theft) ?? simulation.onHonk?()
            return
        }

        if GameTime.time >= stageEndTime {
            simulation.setTask(WanderTask())
        }
    }

    private func tickDrag(simulation: GooseSimulation, lease: ResourceLease) {
        // Re-check every frame: disabling theft/dragging (or Emergency Stop / lock expiry)
        // must hand the cursor back immediately.
        guard ownsCursor,
              GooseSettings.shared.effectiveMouseTheft,
              GooseSettings.shared.allows(.mouseDragging) else {
            simulation.setTask(WanderTask())
            return
        }
        if directionShiftsRemaining > 0 && GameTime.time >= nextDirectionShiftTime {
            directionShiftsRemaining -= 1
            dragTarget = pickRandomDetourTarget(simulation: simulation, excluding: dragTarget)
            nextDirectionShiftTime = GameTime.time + CGFloat.random(in: 1.0...2.0)
        }
        simulation.targetPos = dragTarget
        let beak = simulation.beakPosition
        if !GlobalActionCoordinator.shared.warpMouseGuarded(to: globalScreenPoint(from: beak), lease: lease) {
            simulation.setTask(WanderTask())
            return
        }

        let goosePos = simulation.position
        if CGPoint.distance(goosePos, dragTarget) < Self.dropDistance || GameTime.time >= stageEndTime {
            simulation.setTask(WanderTask())
        }
    }

    private func pickRandomDetourTarget(simulation: GooseSimulation, excluding current: CGPoint) -> CGPoint {
        let s = simulation.screenSize
        let margin: CGFloat = 80
        let candidates: [CGPoint] = [
            CGPoint(x: margin, y: margin),
            CGPoint(x: max(margin + 1, s.width - margin), y: margin),
            CGPoint(x: margin, y: max(margin + 1, s.height - margin)),
            CGPoint(x: max(margin + 1, s.width - margin), y: max(margin + 1, s.height - margin)),
            CGPoint(x: s.width * 0.5, y: s.height * 0.5),
        ].filter { CGPoint.distance($0, current) > 120 }
        return candidates.randomElement() ?? pickDragTarget(simulation: simulation)
    }

    private func pickDragTarget(simulation: GooseSimulation) -> CGPoint {
        let s = simulation.screenSize
        let goose = simulation.position
        let candidates: [CGPoint] = [
            CGPoint(x: 60, y: 60),
            CGPoint(x: s.width - 60, y: 60),
            CGPoint(x: 60, y: s.height - 60),
            CGPoint(x: s.width - 60, y: s.height - 60),
        ]
        return candidates.max { a, b in
            CGPoint.distance(goose, a) < CGPoint.distance(goose, b)
        } ?? CGPoint(x: 80, y: 80)
    }

    /// Converts a SpriteKit scene point (y-up, scene local) to Quartz global
    /// coordinates that `CGWarpMouseCursorPosition` accepts across multi-display layouts.
    private func globalScreenPoint(from scenePoint: CGPoint) -> CGPoint {
        DisplayManager.shared.sceneToCG(scenePoint)
    }
}

/// Central entry points for reactive behaviors, so every trigger respects
/// the same switches.
@MainActor
enum GooseReactions {
    /// Start chasing (and possibly stealing) the cursor. Returns false if
    /// the current settings / run state forbid it.
    @discardableResult
    static func startMouseChase(
        on simulation: GooseSimulation,
        gooseID: UUID = UUID(),
        priority: ActionPriority = .userDirectControl,
        effects: GooseSceneEffects? = nil,
        personality: GoosePersonality? = nil
    ) -> Bool {
        guard GooseController.shared.allowsProactive,
              GooseSettings.shared.allows(.mouseChase) else { return false }
        if let holderID = GlobalActionCoordinator.shared.mouseHolderID,
           holderID != gooseID,
           priority <= .normalPrank {
            return false
        }
        simulation.setTask(NabMouseTask(gooseID: gooseID, priority: priority, effects: effects, personality: personality))
        return true
    }

    /// The goose was angered (closed window / woken from deep sleep).
    @discardableResult
    static func rage(
        on simulation: GooseSimulation,
        gooseID: UUID = UUID(),
        effects: GooseSceneEffects? = nil,
        personality: GoosePersonality? = nil
    ) -> Bool {
        guard GooseSettings.shared.allows(.angryMode) else { return false }
        return startMouseChase(on: simulation, gooseID: gooseID, priority: .userDirectControl, effects: effects, personality: personality)
    }
}
