import CoreGraphics
import Foundation

/// Goose dashes across a few spots on screen and drops visual-only fake files,
/// folders, and icons onto `DesktopMessOverlay`. Never touches real files.
@MainActor
final class DesktopMessTask: GooseTask {
    private weak var effects: GooseSceneEffects?
    private var targets: [CGPoint] = []
    private var currentIndex = 0
    private var stageDeadline: CGFloat = 0

    init(effects: GooseSceneEffects? = nil) {
        self.effects = effects
    }

    func start(simulation: GooseSimulation) {
        guard GooseSettings.shared.allows(.desktopMess) else {
            DispatchQueue.main.async { [weak simulation] in simulation?.setTask(WanderTask()) }
            return
        }
        let drops = Int.random(in: 2...3)
        let w = max(220, simulation.screenSize.width)
        let h = max(260, simulation.screenSize.height)
        let minX = min(100, w * 0.25)
        let maxX = max(minX + 1, w - minX)
        let minY = min(120, h * 0.25)
        let maxY = max(minY + 1, h - minY)
        targets = (0..<drops).map { _ in
            CGPoint(x: CGFloat.random(in: minX...maxX), y: CGFloat.random(in: minY...maxY))
        }
        currentIndex = 0
        simulation.setSpeed(.run)
        simulation.trackMudEndTime = max(simulation.trackMudEndTime, GameTime.time + 10.0)
        if let first = targets.first {
            simulation.targetPos = first
        }
        stageDeadline = GameTime.time + 4.5
        GooseStats.shared.recordPrank("Dropped virtual desktop clutter", kind: .window)
    }

    func tick(simulation: GooseSimulation) {
        guard GooseSettings.shared.allows(.desktopMess),
              GooseController.shared.allowsProactive,
              currentIndex < targets.count else {
            simulation.setTask(WanderTask())
            return
        }

        let target = targets[currentIndex]
        simulation.targetPos = target
        if CGPoint.distance(simulation.position, target) < 28 || GameTime.time >= stageDeadline {
            effects?.spawnDesktopMess(at: simulation.beakPosition, count: 1)
            effects?.playSoundEvent(.prank) ?? simulation.onHonk?()
            currentIndex += 1
            if currentIndex < targets.count {
                simulation.targetPos = targets[currentIndex]
                stageDeadline = GameTime.time + 4.5
            } else {
                simulation.setTask(WanderTask())
            }
        }
    }
}
