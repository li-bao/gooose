import AppKit
import CoreGraphics
import Foundation

/// Playful / skittish cursor interaction without stealing the pointer:
/// the goose circles near the cursor within `mouseChaseRange`, and may flee
/// when the cursor lunges too close (driven by `personality.fleeChance`).
@MainActor
final class MouseChaseTask: GooseTask {
    private static let fleeTriggerRadius: CGFloat = 55

    private weak var effects: GooseSceneEffects?
    private weak var personality: GoosePersonality?

    private var endTime: CGFloat = 0
    private var orbitAngle: CGFloat = 0
    private var fleeUntil: CGFloat = 0
    private var fleeTarget: CGPoint = .zero2
    private var orbitRadius: CGFloat = 90

    var isFleeing: Bool { GameTime.time < fleeUntil }

    init(effects: GooseSceneEffects? = nil, personality: GoosePersonality? = nil) {
        self.effects = effects
        self.personality = personality
    }

    func start(simulation: GooseSimulation) {
        let settings = GooseSettings.shared
        guard settings.allows(.mouseChase) else {
            DispatchQueue.main.async { [weak simulation] in simulation?.setTask(WanderTask()) }
            return
        }
        simulation.setSpeed(.run)
        orbitAngle = CGFloat.random(in: 0...(2 * .pi))
        let maxRange = CGFloat(max(80, settings.mouseChaseRange))
        orbitRadius = min(maxRange * 0.65, max(55, maxRange * 0.45))
        let duration = CGFloat(max(3, settings.mouseChaseDuration))
        endTime = GameTime.time + duration
        fleeUntil = 0
        effects?.playSoundEvent(.random)
    }

    func tick(simulation: GooseSimulation) {
        guard GooseSettings.shared.allows(.mouseChase), GooseController.shared.allowsProactive else {
            simulation.setTask(WanderTask())
            return
        }

        if GameTime.time >= endTime {
            simulation.setTask(WanderTask())
            return
        }

        let mouse = DisplayManager.shared.globalToScene(NSEvent.mouseLocation)
        let dist = CGPoint.distance(simulation.position, mouse)

        if isFleeing {
            simulation.setSpeed(.charge)
            simulation.targetPos = fleeTarget
            if CGPoint.distance(simulation.position, fleeTarget) < 25 {
                fleeUntil = 0
                simulation.setSpeed(.run)
            }
            return
        }

        let trigger = Self.fleeTriggerRadius * simulation.sizeScale
        let fleeProbability = personality?.fleeChance ?? 0.35
        if dist < trigger && Double.random(in: 0..<1) < fleeProbability {
            personality?.recordCaught()
            let away = CGPoint.normalize(simulation.position - mouse)
            let fallbackDir = away == .zero2 ? CGPoint(x: 1, y: 0) : away
            let fleeDist = CGFloat(max(120, GooseSettings.shared.mouseChaseRange))
            let raw = simulation.position + fallbackDir * fleeDist
            fleeTarget = CGPoint(
                x: min(max(60, raw.x), max(61, simulation.screenSize.width - 60)),
                y: min(max(60, raw.y), max(61, simulation.screenSize.height - 60))
            )
            fleeUntil = GameTime.time + 1.8
            effects?.playSoundEvent(.peek)
            return
        }

        // Orbit around the cursor within the configured chase range.
        let maxRange = CGFloat(max(80, GooseSettings.shared.mouseChaseRange))
        let radius = min(orbitRadius, maxRange * 0.8)
        orbitAngle += 1.9 * GameTime.deltaTime
        let desired = CGPoint(
            x: mouse.x + cos(orbitAngle) * radius,
            y: mouse.y + sin(orbitAngle) * radius
        )
        simulation.targetPos = CGPoint(
            x: min(max(40, desired.x), max(41, simulation.screenSize.width - 40)),
            y: min(max(40, desired.y), max(41, simulation.screenSize.height - 40))
        )
    }
}
