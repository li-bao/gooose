import AppKit
import CoreGraphics
import Foundation

/// Goose sits still for a random short interval, resting and recovering fatigue.
/// Can be woken by clicking near the goose.
@MainActor
final class NapTask: GooseTask {
    private static let wakeClickRadius: CGFloat = 55

    private weak var effects: GooseSceneEffects?
    private weak var personality: GoosePersonality?
    private var endTime: CGFloat = 0
    private var lastLeftMouseDown = false

    init(effects: GooseSceneEffects? = nil, personality: GoosePersonality? = nil) {
        self.effects = effects
        self.personality = personality
    }

    func start(simulation: GooseSimulation) {
        simulation.velocity = .zero2
        simulation.targetPos = simulation.position
        let duration = SamMath.randomRange(4, 9)
        endTime = GameTime.time + duration
        lastLeftMouseDown = NSEvent.pressedMouseButtons & 1 != 0
        effects?.setSleeping(active: true)
        NotificationManager.shared.post(
            category: .gooseSleeping,
            title: "Goose is Napping",
            body: "Shh… the goose curled up for a short nap."
        )
    }

    func tick(simulation: GooseSimulation) {
        simulation.velocity = .zero2
        simulation.targetPos = simulation.position

        let leftPressed = NSEvent.pressedMouseButtons & 1 != 0
        let clickRising = leftPressed && !lastLeftMouseDown
        lastLeftMouseDown = leftPressed
        if clickRising && CGPoint.distance(DisplayManager.shared.globalToScene(NSEvent.mouseLocation), simulation.position) <= Self.wakeClickRadius * simulation.sizeScale {
            personality?.recordClick()
            effects?.playSoundEvent(.sleepWake) ?? simulation.onHonk?()
            simulation.setTask(WanderTask())
            return
        }

        if GameTime.time >= endTime {
            simulation.setTask(WanderTask())
        }
    }

    func stop(simulation: GooseSimulation) {
        effects?.setSleeping(active: false)
    }
}
