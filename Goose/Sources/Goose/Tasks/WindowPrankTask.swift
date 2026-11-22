import AppKit
import CoreGraphics
import Foundation

/// Goose runs to the frontmost external application's window, peeks beside its
/// edge, and nudges it slightly via Accessibility (`kAXPositionAttribute`).
/// Requires Accessibility permission; aborts cleanly if unavailable or stopped.
@MainActor
final class WindowPrankTask: GooseTask {
    private enum Stage {
        case approach
        case pushing
    }

    let gooseID: UUID
    private weak var effects: GooseSceneEffects?
    private weak var personality: GoosePersonality?
    private var windowLease: ResourceLease?

    private var targetWindow: AccessibilityProbe.WindowInfo?
    private var stage: Stage = .approach
    private var stageEndTime: CGFloat = 0
    private var approachPoint: CGPoint = .zero2
    private var pushDirX: CGFloat = 1
    private var pushedSoFar: CGFloat = 0
    private var totalNudge: CGFloat = 40
    private var currentWindowOrigin: CGPoint = .zero2

    init(gooseID: UUID = UUID(), effects: GooseSceneEffects? = nil, personality: GoosePersonality? = nil) {
        self.gooseID = gooseID
        self.effects = effects
        self.personality = personality
    }

    func start(simulation: GooseSimulation) {
        guard GooseSettings.shared.allows(.windowPranks),
              let win = AccessibilityProbe.frontmostExternalWindow(),
              let lease = GlobalActionCoordinator.shared.acquireLock(
                for: gooseID,
                resource: .window,
                priority: .normalPrank,
                timeout: 12.0,
                onCancel: { [weak simulation] in
                    if let simulation, simulation.currentTask is WindowPrankTask {
                        simulation.setTask(WanderTask())
                    }
                }
              ) else {
            DispatchQueue.main.async { [weak simulation] in
                if simulation?.currentTask is WindowPrankTask {
                    simulation?.setTask(WanderTask())
                }
            }
            return
        }

        windowLease = lease
        targetWindow = win
        currentWindowOrigin = win.frame.origin
        totalNudge = CGFloat(max(10, min(120, GooseSettings.shared.windowNudgeAmplitude)))

        let screenH = NSScreen.main?.frame.height ?? simulation.screenSize.height
        let sceneFrame = win.sceneFrame(screenHeight: screenH)
        let goRight = sceneFrame.midX < simulation.screenSize.width * 0.5
        pushDirX = goRight ? 1 : -1

        // Approach left edge if pushing right, or right edge if pushing left.
        let edgeX = goRight ? max(30, sceneFrame.minX - 18) : min(simulation.screenSize.width - 30, sceneFrame.maxX + 18)
        let edgeY = min(max(60, sceneFrame.midY), max(61, simulation.screenSize.height - 60))
        approachPoint = CGPoint(x: edgeX, y: edgeY)

        simulation.setSpeed(.run)
        simulation.targetPos = approachPoint
        stage = .approach
        stageEndTime = GameTime.time + 7.0
    }

    func tick(simulation: GooseSimulation) {
        guard GooseSettings.shared.allows(.windowPranks),
              GooseController.shared.allowsProactive,
              let lease = windowLease,
              GlobalActionCoordinator.shared.isValidLease(lease),
              let win = targetWindow else {
            simulation.setTask(WanderTask())
            return
        }

        switch stage {
        case .approach:
            simulation.targetPos = approachPoint
            if CGPoint.distance(simulation.position, approachPoint) < 28 || GameTime.time >= stageEndTime {
                stage = .pushing
                pushedSoFar = 0
                stageEndTime = GameTime.time + 1.4
                effects?.playSoundEvent(.prank) ?? simulation.onHonk?()
                GooseStats.shared.recordPrank("Nudged window: \(win.title ?? "app")", kind: .window)
            }

        case .pushing:
            let step = (totalNudge / 1.0) * GameTime.deltaTime
            let remaining = totalNudge - pushedSoFar
            let delta = min(step, max(0, remaining))
            if delta > 0.05 {
                let screenW = NSScreen.main?.frame.width ?? simulation.screenSize.width
                let nextX = min(max(0, currentWindowOrigin.x + pushDirX * delta), max(0, screenW - win.frame.width))
                currentWindowOrigin.x = nextX
                if !GlobalActionCoordinator.shared.setWindowOriginGuarded(win.element, to: currentWindowOrigin, lease: lease) {
                    simulation.setTask(WanderTask())
                    return
                }
                pushedSoFar += delta
                simulation.position.x += pushDirX * delta
                simulation.targetPos = CGPoint(x: simulation.position.x + pushDirX * 20, y: simulation.position.y)
            }
            if pushedSoFar >= totalNudge || GameTime.time >= stageEndTime {
                simulation.setTask(WanderTask())
            }
        }
    }

    func stop(simulation: GooseSimulation) {
        if let lease = windowLease {
            windowLease = nil
            GlobalActionCoordinator.shared.releaseLock(lease)
        }
        targetWindow = nil
    }
}
