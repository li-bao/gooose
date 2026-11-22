import CoreGraphics
import Foundation

/// Goose roams the screen, pausing briefly between random walks. Mirrors the
/// `Task_Wander` state machine from the original game.
@MainActor
final class WanderTask: GooseTask {
    private static let minWanderingTime: CGFloat = 20
    private static let maxWanderingTime: CGFloat = 40
    private static let arrivalThreshold: CGFloat = 20

    private var wanderingStartTime: CGFloat = 0
    private var wanderingDuration: CGFloat = 0
    private var pauseStartTime: CGFloat = -1
    private var pauseDuration: CGFloat = 0

    func start(simulation: GooseSimulation) {
        simulation.setSpeed(.walk)
        wanderingStartTime = GameTime.time
        wanderingDuration = Self.randomWanderDuration()
        pauseStartTime = -1
    }

    func tick(simulation: GooseSimulation) {
        if GameTime.time - wanderingStartTime > wanderingDuration {
            start(simulation: simulation)
            return
        }

        if pauseStartTime > 0 {
            tickPause(simulation: simulation)
        } else {
            tickWalk(simulation: simulation)
        }
    }

    private func tickPause(simulation: GooseSimulation) {
        if GameTime.time - pauseStartTime > pauseDuration {
            pauseStartTime = -1
            pickNextTarget(simulation: simulation)
        } else {
            simulation.velocity = .zero2
            // Pin target to current position so the engine's velocity
            // integration doesn't keep nudging the goose toward an
            // already-arrived target during the pause.
            simulation.targetPos = simulation.position
        }
    }

    private func tickWalk(simulation: GooseSimulation) {
        if CGPoint.distance(simulation.position, simulation.targetPos) < Self.arrivalThreshold {
            pauseStartTime = GameTime.time
            pauseDuration = Self.randomPauseDuration()
        }
    }

    private func pickNextTarget(simulation: GooseSimulation) {
        let maxDistance = Self.randomWalkTime() * simulation.currentSpeed
        let dm = DisplayManager.shared
        let candidate: CGPoint
        if dm.screenFrames.count > 1 && Double.random(in: 0..<1) < 0.35 {
            // Cross-display roam: allow geese to stroll onto another connected monitor.
            candidate = dm.randomVisiblePoint(margin: 45)
        } else if !dm.screenFrames.isEmpty {
            let idx = dm.screenIndex(for: simulation.position)
            candidate = dm.randomVisiblePoint(margin: 45, preferredScreenIndex: idx)
        } else {
            candidate = CGPoint(
                x: SamMath.randomRange(0, simulation.screenSize.width),
                y: SamMath.randomRange(0, simulation.screenSize.height)
            )
        }
        let nextTarget: CGPoint
        if CGPoint.distance(simulation.position, candidate) > maxDistance {
            let direction = CGPoint.normalize(candidate - simulation.position)
            nextTarget = simulation.position + direction * maxDistance
        } else {
            nextTarget = candidate
        }
        simulation.targetPos = dm.screenFrames.isEmpty
            ? nextTarget
            : dm.clampToNearestVisibleDisplay(nextTarget, margin: 30)
    }

    private static func randomWanderDuration() -> CGFloat {
        guard GameTime.time >= 1 else { return minWanderingTime }
        return SamMath.randomRange(minWanderingTime, maxWanderingTime)
    }

    private static func randomWalkTime() -> CGFloat {
        SamMath.randomRange(1, 6)
    }

    private static func randomPauseDuration() -> CGFloat {
        1 + CGFloat.random(in: 0...1)
    }
}
