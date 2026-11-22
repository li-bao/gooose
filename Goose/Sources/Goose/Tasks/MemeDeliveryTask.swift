import AppKit
import CoreGraphics
import Foundation

/// Goose walks to the configured display edge, grabs a `GooseNotepadWindow`
/// (unified Memo Editor container) holding a user-imported PNG/JPG/JPEG/WEBP/animated GIF
/// meme + editable caption, drags it smoothly onto `NSScreen.visibleFrame`, plays a
/// settle bounce, and unlocks interaction.
@MainActor
final class MemeDeliveryTask: GooseTask {
    enum Stage: Equatable {
        case walkingToEdge
        case pullingIn
        case settling
    }

    let gooseID: UUID
    private let memeItem: MemeItem
    private let caption: String
    private weak var effects: GooseSceneEffects?
    private var windowLease: ResourceLease?

    private(set) var stage: Stage = .walkingToEdge
    private var activeEntryStyle: MemoEntryStyle = .dragFromLeft
    private var stageDeadline: CGFloat = 0
    private var edgeStartScene: CGPoint = .zero
    private var startCenterScene: CGPoint = .zero
    private var dropTargetScene: CGPoint = .zero
    private var controlPointScene: CGPoint = .zero
    private var finalClampedGlobalOrigin: CGPoint = .zero
    private var pullElapsed: CGFloat = 0
    private var pullDuration: CGFloat = 2.0
    private var settleElapsed: CGFloat = 0
    private let settleDuration: CGFloat = 0.24
    private var targetScreenFrame: CGRect = .zero
    private var window: GooseNotepadWindow?
    private var deliveryCompleted = false
    private var didEmitDeliveryHonk = false

    init(gooseID: UUID = UUID(), item: MemeItem, caption: String = "", effects: GooseSceneEffects?) {
        self.gooseID = gooseID
        self.memeItem = item
        self.caption = caption
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
        let localVisible = dm.visibleFrame(forScreenIndex: screenIdx, fallbackSize: simulation.screenSize)
        targetScreenFrame = localVisible

        let cfg = AnimationStudioStore.shared.settings
        if cfg.entryStyle == .randomEdge {
            let nearLeft = (simulation.position.x - localVisible.minX) < (localVisible.maxX - simulation.position.x)
            activeEntryStyle = Bool.random()
                ? (nearLeft ? .dragFromLeft : .dragFromRight)
                : ([.dragFromLeft, .dragFromRight, .dragFromTop, .dragFromBottom].randomElement() ?? .dragFromLeft)
        } else {
            activeEntryStyle = cfg.entryStyle
        }

        edgeStartScene = NotepadDeliveryTask.edgePoint(for: activeEntryStyle, in: localVisible, near: simulation.position)
        simulation.setSpeed(.run)
        simulation.targetPos = edgeStartScene
        stage = .walkingToEdge
        stageDeadline = GameTime.time + 10.0
    }

    func tick(simulation: GooseSimulation) {
        guard let lease = windowLease, GlobalActionCoordinator.shared.isValidLease(lease) else {
            simulation.setTask(WanderTask())
            return
        }

        switch stage {
        case .walkingToEdge:
            if CGPoint.distance(simulation.position, edgeStartScene) < 34 || GameTime.time >= stageDeadline {
                beginPull(simulation: simulation)
            }
        case .pullingIn:
            tickPull(simulation: simulation)
        case .settling:
            tickSettle(simulation: simulation)
        }
    }

    func stop(simulation: GooseSimulation) {
        if let lease = windowLease {
            windowLease = nil
            GlobalActionCoordinator.shared.releaseLock(lease)
        }
        if !deliveryCompleted, let win = window {
            win.resetDragVisual()
            win.close()
            window = nil
        }
    }

    private func beginPull(simulation: GooseSimulation) {
        let memoWin = GooseNotepadWindow(title: memeItem.filename, body: caption, memeItem: memeItem)
        memoWin.setInteractive(false)
        NotepadWindowRegistry.shared.register(memoWin, maxVisible: GooseSettings.shared.maxVisibleMemes)
        self.window = memoWin

        let s = memoWin.targetSize
        let startOrigin = NotepadDeliveryTask.edgeWindowOrigin(
            for: activeEntryStyle,
            edgePoint: edgeStartScene,
            in: targetScreenFrame,
            windowSize: s
        )
        startCenterScene = CGPoint(x: startOrigin.x + s.width * 0.5, y: startOrigin.y + s.height * 0.5)

        let safeMinX = targetScreenFrame.minX + 40
        let safeMaxX = max(safeMinX + 1, targetScreenFrame.maxX - s.width - 40)
        let safeMinY = targetScreenFrame.minY + 40
        let safeMaxY = max(safeMinY + 1, targetScreenFrame.maxY - s.height - 48)

        let finalSceneOrigin = CGPoint(
            x: CGFloat.random(in: safeMinX...safeMaxX),
            y: CGFloat.random(in: safeMinY...safeMaxY)
        )
        dropTargetScene = CGPoint(
            x: finalSceneOrigin.x + s.width * 0.5,
            y: finalSceneOrigin.y + s.height * 0.5
        )
        let arcOffset: CGFloat = (dropTargetScene.y >= startCenterScene.y) ? 28 : -28
        let rawMidY = (startCenterScene.y + dropTargetScene.y) * 0.5 + arcOffset
        let safeMidY = SamMath.clamp(
            rawMidY,
            targetScreenFrame.minY + s.height * 0.5 + 12,
            max(targetScreenFrame.minY + s.height * 0.5 + 13, targetScreenFrame.maxY - s.height * 0.5 - 12)
        )
        controlPointScene = CGPoint(
            x: (startCenterScene.x + dropTargetScene.x) * 0.5,
            y: safeMidY
        )

        let cfg = AnimationStudioStore.shared.settings
        let dist = CGPoint.distance(startCenterScene, dropTargetScene)
        let speed = max(0.5, min(2.0, CGFloat(GooseSettings.shared.deliveryAnimationSpeed) * CGFloat(cfg.movementSpeed)))
        let baseDuration = SamMath.clamp(CGFloat(cfg.entryDuration) * (0.8 + dist / 1400.0), 1.5, 3.0)
        pullDuration = SamMath.clamp(baseDuration / speed, 1.2, 3.5)

        let startGlobal = DisplayManager.shared.sceneToGlobal(startOrigin)
        memoWin.setFrameOrigin(startGlobal)
        memoWin.orderFrontRegardless()

        pullElapsed = 0
        stage = .pullingIn
        if !AudioPackManager.shared.playEventSound(.memeAppearance) {
            _ = SoundEffectEngine.shared.playMovement(.memeDrag, category: .meme, priority: .normal)
        }
        if !didEmitDeliveryHonk {
            didEmitDeliveryHonk = true
            effects?.playSoundEvent(.delivery, gooseID: gooseID, isSleeping: false)
        }
    }

    private func tickPull(simulation: GooseSimulation) {
        guard let memeWin = window else {
            simulation.setTask(WanderTask())
            return
        }

        let cfg = AnimationStudioStore.shared.settings
        pullElapsed += GameTime.deltaTime
        let rawU = min(1.0, pullElapsed / max(0.1, pullDuration))
        let t = cfg.easeCurve.evaluate(rawU)
        let oneMinusT = 1.0 - t

        let bezierX = oneMinusT * oneMinusT * startCenterScene.x + 2 * oneMinusT * t * controlPointScene.x + t * t * dropTargetScene.x
        let bezierY = oneMinusT * oneMinusT * startCenterScene.y + 2 * oneMinusT * t * controlPointScene.y + t * t * dropTargetScene.y
        let bobY = sin(rawU * .pi * 3.5) * 4.0 * (1.0 - rawU)
        let windowCenterScene = CGPoint(x: bezierX, y: bezierY + bobY)

        let tangentX = 2 * oneMinusT * (controlPointScene.x - startCenterScene.x) + 2 * t * (dropTargetScene.x - controlPointScene.x)
        let tangentY = 2 * oneMinusT * (controlPointScene.y - startCenterScene.y) + 2 * t * (dropTargetScene.y - controlPointScene.y)
        if hypot(tangentX, tangentY) > 0.01 {
            simulation.direction = atan2(tangentY, tangentX) * SamMath.rad2Deg
        }

        let s = memeWin.targetSize
        let offset = CGFloat(cfg.dragOffset)
        let gooseAnchor: CGPoint
        switch activeEntryStyle {
        case .dragFromRight:
            gooseAnchor = CGPoint(x: windowCenterScene.x - s.width * 0.5 - offset, y: windowCenterScene.y - 10)
        case .dragFromTop:
            gooseAnchor = CGPoint(x: windowCenterScene.x, y: windowCenterScene.y - s.height * 0.5 - offset)
        case .dragFromBottom:
            gooseAnchor = CGPoint(x: windowCenterScene.x, y: windowCenterScene.y + s.height * 0.5 + offset)
        case .gooseCarry:
            gooseAnchor = CGPoint(x: windowCenterScene.x, y: windowCenterScene.y - 18)
        default:
            gooseAnchor = CGPoint(x: windowCenterScene.x + s.width * 0.5 + offset, y: windowCenterScene.y - 10)
        }
        simulation.position = gooseAnchor
        simulation.targetPos = gooseAnchor
        simulation.overrideExtendNeck = true

        let maxRotRad = CGFloat(cfg.rotationDegrees) * SamMath.deg2Rad
        let tilt = sin(rawU * .pi * 3.0) * maxRotRad * (1.0 - rawU)
        memeWin.applyDragVisual(tiltRadians: tilt)

        let globalCenter = DisplayManager.shared.sceneToGlobal(windowCenterScene)
        let origin = CGPoint(x: globalCenter.x - s.width * 0.5, y: globalCenter.y - s.height * 0.5)
        memeWin.setFrameOrigin(origin)

        if rawU >= 1.0 {
            let finalGlobalCenter = DisplayManager.shared.sceneToGlobal(dropTargetScene)
            finalClampedGlobalOrigin = Self.clampWindowOrigin(
                CGPoint(x: finalGlobalCenter.x - s.width * 0.5, y: finalGlobalCenter.y - s.height * 0.5),
                windowSize: s,
                onlyClampAtFinal: true
            )
            memeWin.setFrameOrigin(finalClampedGlobalOrigin)
            settleElapsed = 0
            stage = .settling
            if !AudioPackManager.shared.playEventSound(.memoDrop) {
                _ = SoundEffectEngine.shared.playMovement(.notepadLand, category: .meme, priority: .normal)
            }
        }
    }

    private func tickSettle(simulation: GooseSimulation) {
        guard let memeWin = window else {
            simulation.setTask(WanderTask())
            return
        }

        let bounce = CGFloat(AnimationStudioStore.shared.settings.bounceIntensity)
        settleElapsed += GameTime.deltaTime
        let p = min(1.0, settleElapsed / settleDuration)
        let scale = 1.0 + sin(p * .pi) * (0.045 * bounce) * (1.0 - p)
        let dy = -sin(p * .pi) * (4.0 * bounce) * (1.0 - p)

        memeWin.applyDragVisual(tiltRadians: 0, scale: scale)
        memeWin.setFrameOrigin(CGPoint(x: finalClampedGlobalOrigin.x, y: finalClampedGlobalOrigin.y + dy))

        if p >= 1.0 {
            memeWin.resetDragVisual()
            memeWin.setFrameOrigin(finalClampedGlobalOrigin)
            memeWin.setInteractive(true)
            memeWin.scheduleAutoDismiss(after: GooseSettings.shared.memeLifetime)
            effects?.spawnHearts(at: simulation.position, count: 3)
            deliveryCompleted = true
            window = nil
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
