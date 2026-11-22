import AppKit
import CoreGraphics
import Foundation

/// Goose walks to the display edge, grabs a user-imported MemeWindow (PNG/JPG/animated GIF)
/// from outside visible screen bounds, pulls it smoothly onto the screen along a Bezier
/// path, releases it cleanly inside `visibleFrame`, and reacts.
@MainActor
final class MemeDeliveryTask: GooseTask {
    enum Stage {
        case walkingToEdge
        case pullingIn
    }

    let gooseID: UUID
    private let memeItem: MemeItem
    private weak var effects: GooseSceneEffects?
    private var windowLease: ResourceLease?

    private var stage: Stage = .walkingToEdge
    private var edgeStartScene: CGPoint = .zero
    private var dropTargetScene: CGPoint = .zero
    private var controlPointScene: CGPoint = .zero
    private var pullProgress: CGFloat = 0
    private var targetScreenFrame: CGRect = .zero
    private var window: MemeWindow?

    init(gooseID: UUID = UUID(), item: MemeItem, effects: GooseSceneEffects) {
        self.gooseID = gooseID
        self.memeItem = item
        self.effects = effects
    }

    func start(simulation: GooseSimulation) {
        guard let lease = GlobalActionCoordinator.shared.acquireLock(
            for: gooseID,
            resource: .window,
            priority: .normalPrank,
            timeout: 24.0,
            onCancel: { [weak simulation] in
                if let simulation, simulation.currentTask is MemeDeliveryTask {
                    simulation.setTask(WanderTask())
                }
            }
        ) else {
            DispatchQueue.main.async { [weak simulation] in
                if simulation?.currentTask is MemeDeliveryTask {
                    simulation?.setTask(WanderTask())
                }
            }
            return
        }

        windowLease = lease
        let dm = DisplayManager.shared
        let screenIdx = dm.screenIndex(for: simulation.position) ?? 0
        let localFrame = dm.screenFrames.indices.contains(screenIdx)
            ? dm.screenFrames[screenIdx]
            : CGRect(origin: .zero, size: simulation.screenSize)
        targetScreenFrame = localFrame

        let fromLeft = (simulation.position.x - localFrame.minX) < (localFrame.maxX - simulation.position.x)
        let edgeX = fromLeft ? localFrame.minX + 12 : localFrame.maxX - 12
        let edgeY = CGFloat.random(in: (localFrame.minY + 120)...max(localFrame.minY + 121, localFrame.maxY - 120))
        edgeStartScene = CGPoint(x: edgeX, y: edgeY)

        simulation.setSpeed(.run)
        simulation.targetPos = edgeStartScene
        stage = .walkingToEdge
    }

    func tick(simulation: GooseSimulation) {
        guard let lease = windowLease, GlobalActionCoordinator.shared.isValidLease(lease) else {
            simulation.setTask(WanderTask())
            return
        }

        switch stage {
        case .walkingToEdge:
            if CGPoint.distance(simulation.position, edgeStartScene) < 34 {
                beginPull(simulation: simulation)
            }
        case .pullingIn:
            tickPull(simulation: simulation)
        }
    }

    func stop(simulation: GooseSimulation) {
        if let lease = windowLease {
            windowLease = nil
            GlobalActionCoordinator.shared.releaseLock(lease)
        }
    }

    private func beginPull(simulation: GooseSimulation) {
        guard let memeWin = MemeWindow(item: memeItem) else {
            simulation.setTask(WanderTask())
            return
        }
        MemeWindowRegistry.shared.register(memeWin, maxVisible: GooseSettings.shared.maxVisibleMemes)
        self.window = memeWin

        let s = memeWin.targetSize
        let safeMinX = targetScreenFrame.minX + 40
        let safeMaxX = max(safeMinX + 1, targetScreenFrame.maxX - s.width - 40)
        let safeMinY = targetScreenFrame.minY + 40
        let safeMaxY = max(safeMinY + 1, targetScreenFrame.maxY - s.height - 60)

        let finalSceneOrigin = CGPoint(
            x: CGFloat.random(in: safeMinX...safeMaxX),
            y: CGFloat.random(in: safeMinY...safeMaxY)
        )
        dropTargetScene = CGPoint(
            x: finalSceneOrigin.x + s.width * 0.5,
            y: finalSceneOrigin.y + s.height * 0.5
        )
        controlPointScene = CGPoint(
            x: (edgeStartScene.x + dropTargetScene.x) * 0.5,
            y: max(edgeStartScene.y, dropTargetScene.y) + 80
        )

        let startGlobal = Self.offscreenOriginGlobal(
            sceneOrigin: edgeStartScene,
            screenFrame: targetScreenFrame,
            windowSize: s
        )
        memeWin.setFrameOrigin(startGlobal)
        memeWin.orderFrontRegardless()

        pullProgress = 0
        stage = .pullingIn
        _ = SoundEffectEngine.shared.playMovement(.memeDrag, category: .meme, priority: .normal)
    }

    private func tickPull(simulation: GooseSimulation) {
        guard let memeWin = window else {
            simulation.setTask(WanderTask())
            return
        }

        let speed = max(0.35, CGFloat(GooseSettings.shared.deliveryAnimationSpeed))
        pullProgress = min(1.0, pullProgress + CGFloat(GameTime.deltaTime) * 0.68 * speed)

        let t = pullProgress
        let oneMinusT = 1.0 - t
        let pos = CGPoint(
            x: oneMinusT * oneMinusT * edgeStartScene.x + 2 * oneMinusT * t * controlPointScene.x + t * t * dropTargetScene.x,
            y: oneMinusT * oneMinusT * edgeStartScene.y + 2 * oneMinusT * t * controlPointScene.y + t * t * dropTargetScene.y
        )

        simulation.position = pos
        simulation.targetPos = pos
        simulation.overrideExtendNeck = true

        let globalCenter = DisplayManager.shared.sceneToGlobal(pos)
        let clampedOrigin = Self.clampWindowOrigin(
            CGPoint(x: globalCenter.x - memeWin.targetSize.width * 0.5, y: globalCenter.y - memeWin.targetSize.height * 0.5),
            windowSize: memeWin.targetSize,
            onlyClampAtFinal: t >= 1.0
        )
        memeWin.setFrameOrigin(clampedOrigin)

        if pullProgress >= 1.0 {
            memeWin.scheduleAutoDismiss(after: GooseSettings.shared.memeLifetime)
            _ = SoundEffectEngine.shared.playMovement(.notepadLand, category: .meme, priority: .normal)
            effects?.playSoundEvent(.prank)
            effects?.spawnHearts(at: simulation.position, count: 3)
            simulation.setTask(WanderTask())
        }
    }

    static func offscreenOriginGlobal(sceneOrigin: CGPoint, screenFrame: CGRect, windowSize: CGSize) -> CGPoint {
        let edgeGlobal = DisplayManager.shared.sceneToGlobal(sceneOrigin)
        let onLeft = (sceneOrigin.x - screenFrame.minX) < (screenFrame.maxX - sceneOrigin.x)
        return CGPoint(
            x: onLeft ? edgeGlobal.x - windowSize.width - 30 : edgeGlobal.x + 30,
            y: edgeGlobal.y - windowSize.height * 0.5
        )
    }

    static func clampWindowOrigin(_ origin: CGPoint, windowSize: CGSize, onlyClampAtFinal: Bool) -> CGPoint {
        guard onlyClampAtFinal else { return origin }
        let center = CGPoint(x: origin.x + windowSize.width * 0.5, y: origin.y + windowSize.height * 0.5)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return origin }
        return CGPoint(
            x: min(max(visible.minX + 12, origin.x), max(visible.minX + 12, visible.maxX - windowSize.width - 12)),
            y: min(max(visible.minY + 12, origin.y), max(visible.minY + 12, visible.maxY - windowSize.height - 12))
        )
    }
}
