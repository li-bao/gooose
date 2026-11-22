import AppKit
import CoreGraphics
import Foundation

/// Iconic Desktop Goose Memo Editor delivery:
/// 1. Goose runs to the configured visible display edge (Left/Right/Top/Bottom/Carry).
/// 2. `GooseNotepadWindow` appears right at the screen edge (non-interactive).
/// 3. Goose grabs the window edge and drags it smoothly along a curved eased
///    path onto `NSScreen.visibleFrame`, with Animation Studio rotation/bob/offset.
/// 4. Plays an elastic settle bounce, then unlocks full user editing & interaction.
@MainActor
final class NotepadDeliveryTask: GooseTask {
    enum Stage: Equatable {
        case walkingToEdge
        case draggingIn
        case settling
    }

    let gooseID: UUID
    private let noteTitle: String
    private let noteBody: String
    private weak var effects: GooseSceneEffects?
    private var windowLease: ResourceLease?

    private(set) var currentStage: Stage = .walkingToEdge
    private(set) var isDeliveryCompleted = false
    private(set) var deliveryHonkCount = 0

    private var activeEntryStyle: MemoEntryStyle = .dragFromLeft
    private var edgeStartScene: CGPoint = .zero
    private var targetScreenFrame: CGRect = .zero
    private var startCenterScene: CGPoint = .zero
    private var controlPointScene: CGPoint = .zero
    private var dropCenterScene: CGPoint = .zero
    private var finalClampedGlobalOrigin: CGPoint = .zero

    private var stageDeadline: CGFloat = 0
    private var dragElapsed: CGFloat = 0
    private var dragDuration: CGFloat = 2.0
    private var settleElapsed: CGFloat = 0
    private let settleDuration: CGFloat = 0.24
    private var notepadWindow: GooseNotepadWindow?

    var currentWindowOrigin: CGPoint? { notepadWindow?.frame.origin }
    var activeWindow: GooseNotepadWindow? { notepadWindow }

    init(gooseID: UUID = UUID(), title: String, body: String, effects: GooseSceneEffects?) {
        self.gooseID = gooseID
        self.noteTitle = title
        self.noteBody = body
        self.effects = effects
    }

    func start(simulation: GooseSimulation) {
        guard let lease = GlobalActionCoordinator.shared.acquireLock(
            for: gooseID,
            resource: .window,
            priority: .normalPrank,
            timeout: 24.0,
            onCancel: { [weak simulation] in
                if let simulation, simulation.currentTask is NotepadDeliveryTask {
                    simulation.setTask(WanderTask())
                }
            }
        ) else {
            DispatchQueue.main.async { [weak simulation] in
                if simulation?.currentTask is NotepadDeliveryTask {
                    simulation?.setTask(WanderTask())
                }
            }
            return
        }

        windowLease = lease
        let dm = DisplayManager.shared
        let idx = dm.screenIndex(for: simulation.position) ?? 0
        let localVisible = dm.visibleFrame(forScreenIndex: idx, fallbackSize: simulation.screenSize)
        targetScreenFrame = localVisible

        let cfg = AnimationStudioStore.shared.settings
        if cfg.entryStyle == .randomEdge {
            // Default to nearest horizontal edge or any edge.
            let nearLeft = (simulation.position.x - localVisible.minX) < (localVisible.maxX - simulation.position.x)
            activeEntryStyle = Bool.random()
                ? (nearLeft ? .dragFromLeft : .dragFromRight)
                : ([.dragFromLeft, .dragFromRight, .dragFromTop, .dragFromBottom].randomElement() ?? .dragFromLeft)
        } else {
            activeEntryStyle = cfg.entryStyle
        }

        edgeStartScene = Self.edgePoint(for: activeEntryStyle, in: localVisible, near: simulation.position)
        simulation.setSpeed(.run)
        simulation.targetPos = edgeStartScene
        currentStage = .walkingToEdge
        stageDeadline = GameTime.time + 10.0
    }

    func tick(simulation: GooseSimulation) {
        guard let lease = windowLease, GlobalActionCoordinator.shared.isValidLease(lease) else {
            simulation.setTask(WanderTask())
            return
        }

        switch currentStage {
        case .walkingToEdge:
            if CGPoint.distance(simulation.position, edgeStartScene) < 34 || GameTime.time >= stageDeadline {
                beginDrag(simulation: simulation)
            }
        case .draggingIn:
            tickDrag(simulation: simulation)
        case .settling:
            tickSettle(simulation: simulation)
        }
    }

    func stop(simulation: GooseSimulation) {
        if let lease = windowLease {
            windowLease = nil
            GlobalActionCoordinator.shared.releaseLock(lease)
        }
        if !isDeliveryCompleted, let win = notepadWindow {
            win.resetDragVisual()
            win.close()
            notepadWindow = nil
        }
    }

    private func beginDrag(simulation: GooseSimulation) {
        let win = GooseNotepadWindow(title: noteTitle, body: noteBody)
        win.setInteractive(false)
        NotepadWindowRegistry.shared.register(win, maxVisible: GooseSettings.shared.maxVisibleNotepads)
        notepadWindow = win

        let size = win.targetSize
        let startOrigin = Self.edgeWindowOrigin(for: activeEntryStyle, edgePoint: edgeStartScene, in: targetScreenFrame, windowSize: size)
        startCenterScene = CGPoint(x: startOrigin.x + size.width * 0.5, y: startOrigin.y + size.height * 0.5)

        let minCenterX = targetScreenFrame.minX + 48 + size.width * 0.5
        let maxCenterX = max(minCenterX + 1, targetScreenFrame.maxX - 48 - size.width * 0.5)
        let minCenterY = targetScreenFrame.minY + 48 + size.height * 0.5
        let maxCenterY = max(minCenterY + 1, targetScreenFrame.maxY - 48 - size.height * 0.5)

        dropCenterScene = CGPoint(
            x: CGFloat.random(in: minCenterX...maxCenterX),
            y: CGFloat.random(in: minCenterY...maxCenterY)
        )

        let arcOffset: CGFloat = (dropCenterScene.y >= startCenterScene.y) ? 26 : -26
        let rawMidY = (startCenterScene.y + dropCenterScene.y) * 0.5 + arcOffset
        let safeMidY = SamMath.clamp(
            rawMidY,
            targetScreenFrame.minY + size.height * 0.5 + 12,
            max(targetScreenFrame.minY + size.height * 0.5 + 13, targetScreenFrame.maxY - size.height * 0.5 - 12)
        )
        controlPointScene = CGPoint(
            x: (startCenterScene.x + dropCenterScene.x) * 0.5,
            y: safeMidY
        )

        let cfg = AnimationStudioStore.shared.settings
        let dist = CGPoint.distance(startCenterScene, dropCenterScene)
        let speed = max(0.5, min(2.0, CGFloat(GooseSettings.shared.deliveryAnimationSpeed) * CGFloat(cfg.movementSpeed)))
        let baseDuration = SamMath.clamp(CGFloat(cfg.entryDuration) * (0.8 + dist / 1400.0), 1.5, 3.0)
        dragDuration = SamMath.clamp(baseDuration / speed, 1.2, 3.5)

        let initialGlobal = DisplayManager.shared.sceneToGlobal(startOrigin)
        win.setFrameOrigin(initialGlobal)
        win.orderFrontRegardless()

        dragElapsed = 0
        currentStage = .draggingIn
        if !AudioPackManager.shared.playEventSound(.memoDrag) {
            _ = SoundEffectEngine.shared.playMovement(.paperSlide, category: .notepad, priority: .normal)
        }
        if deliveryHonkCount == 0 {
            deliveryHonkCount += 1
            effects?.playSoundEvent(.delivery, gooseID: gooseID, isSleeping: false)
        }
    }

    private func tickDrag(simulation: GooseSimulation) {
        guard let win = notepadWindow else {
            simulation.setTask(WanderTask())
            return
        }

        let cfg = AnimationStudioStore.shared.settings
        dragElapsed += GameTime.deltaTime
        let rawU = min(1.0, dragElapsed / max(0.1, dragDuration))
        let t = cfg.easeCurve.evaluate(rawU)
        let u = 1.0 - t

        let bezierX = u * u * startCenterScene.x + 2 * u * t * controlPointScene.x + t * t * dropCenterScene.x
        let bezierY = u * u * startCenterScene.y + 2 * u * t * controlPointScene.y + t * t * dropCenterScene.y
        let bobY = sin(rawU * .pi * 3.5) * 4.0 * (1.0 - rawU)
        let windowCenterScene = CGPoint(x: bezierX, y: bezierY + bobY)

        let tangentX = 2 * u * (controlPointScene.x - startCenterScene.x) + 2 * t * (dropCenterScene.x - controlPointScene.x)
        let tangentY = 2 * u * (controlPointScene.y - startCenterScene.y) + 2 * t * (dropCenterScene.y - controlPointScene.y)
        if hypot(tangentX, tangentY) > 0.01 {
            simulation.direction = atan2(tangentY, tangentX) * SamMath.rad2Deg
        }

        let size = win.targetSize
        let offset = CGFloat(cfg.dragOffset)
        let gooseAnchor: CGPoint
        switch activeEntryStyle {
        case .dragFromRight:
            gooseAnchor = CGPoint(x: windowCenterScene.x - size.width * 0.5 - offset, y: windowCenterScene.y - 10)
        case .dragFromTop:
            gooseAnchor = CGPoint(x: windowCenterScene.x, y: windowCenterScene.y - size.height * 0.5 - offset)
        case .dragFromBottom:
            gooseAnchor = CGPoint(x: windowCenterScene.x, y: windowCenterScene.y + size.height * 0.5 + offset)
        case .gooseCarry:
            gooseAnchor = CGPoint(x: windowCenterScene.x, y: windowCenterScene.y - 18)
        default:
            gooseAnchor = CGPoint(x: windowCenterScene.x + size.width * 0.5 + offset, y: windowCenterScene.y - 10)
        }
        simulation.position = gooseAnchor
        simulation.targetPos = gooseAnchor
        simulation.overrideExtendNeck = true

        let maxRotRad = CGFloat(cfg.rotationDegrees) * SamMath.deg2Rad
        let tilt = sin(rawU * .pi * 3.0) * maxRotRad * (1.0 - rawU)
        win.applyDragVisual(tiltRadians: tilt)

        let globalCenter = DisplayManager.shared.sceneToGlobal(windowCenterScene)
        let currentOrigin = CGPoint(
            x: globalCenter.x - size.width * 0.5,
            y: globalCenter.y - size.height * 0.5
        )
        win.setFrameOrigin(currentOrigin)

        if rawU >= 1.0 {
            let finalGlobalCenter = DisplayManager.shared.sceneToGlobal(dropCenterScene)
            let rawFinalOrigin = CGPoint(
                x: finalGlobalCenter.x - size.width * 0.5,
                y: finalGlobalCenter.y - size.height * 0.5
            )
            finalClampedGlobalOrigin = MemeDeliveryTask.clampWindowOrigin(
                rawFinalOrigin,
                windowSize: size,
                onlyClampAtFinal: true
            )
            win.setFrameOrigin(finalClampedGlobalOrigin)
            settleElapsed = 0
            currentStage = .settling
            if !AudioPackManager.shared.playEventSound(.memoDrop) {
                _ = SoundEffectEngine.shared.playMovement(.notepadLand, category: .notepad, priority: .normal)
            }
        }
    }

    private func tickSettle(simulation: GooseSimulation) {
        guard let win = notepadWindow else {
            simulation.setTask(WanderTask())
            return
        }

        let bounce = CGFloat(AnimationStudioStore.shared.settings.bounceIntensity)
        settleElapsed += GameTime.deltaTime
        let p = min(1.0, settleElapsed / settleDuration)
        let scale = 1.0 + sin(p * .pi) * (0.045 * bounce) * (1.0 - p)
        let dy = -sin(p * .pi) * (4.0 * bounce) * (1.0 - p)

        win.applyDragVisual(tiltRadians: 0, scale: scale)
        win.setFrameOrigin(CGPoint(x: finalClampedGlobalOrigin.x, y: finalClampedGlobalOrigin.y + dy))

        if p >= 1.0 {
            win.resetDragVisual()
            win.setFrameOrigin(finalClampedGlobalOrigin)
            win.setInteractive(true)
            win.scheduleAutoDismiss(after: GooseSettings.shared.notepadLifetime)
            isDeliveryCompleted = true
            notepadWindow = nil
            simulation.setTask(WanderTask())
        }
    }

    // MARK: - Shared Edge Geometry Helpers

    static func edgePoint(for style: MemoEntryStyle, in visible: CGRect, near pos: CGPoint) -> CGPoint {
        let minY = visible.minY + 110
        let maxY = max(minY + 1, visible.maxY - 110)
        let minX = visible.minX + 140
        let maxX = max(minX + 1, visible.maxX - 140)
        switch style {
        case .dragFromLeft, .gooseCarry, .randomEdge:
            return CGPoint(x: visible.minX + 18, y: CGFloat.random(in: minY...maxY))
        case .dragFromRight:
            return CGPoint(x: visible.maxX - 18, y: CGFloat.random(in: minY...maxY))
        case .dragFromTop:
            return CGPoint(x: CGFloat.random(in: minX...maxX), y: visible.maxY - 18)
        case .dragFromBottom:
            return CGPoint(x: CGFloat.random(in: minX...maxX), y: visible.minY + 18)
        }
    }

    static func edgeWindowOrigin(
        for style: MemoEntryStyle,
        edgePoint: CGPoint,
        in visible: CGRect,
        windowSize: CGSize
    ) -> CGPoint {
        let clampedY = min(
            max(visible.minY + 16, edgePoint.y - windowSize.height * 0.5),
            max(visible.minY + 16, visible.maxY - windowSize.height - 16)
        )
        let clampedX = min(
            max(visible.minX + 16, edgePoint.x - windowSize.width * 0.5),
            max(visible.minX + 16, visible.maxX - windowSize.width - 16)
        )
        switch style {
        case .dragFromLeft, .gooseCarry, .randomEdge:
            return CGPoint(x: visible.minX - windowSize.width + 8, y: clampedY)
        case .dragFromRight:
            return CGPoint(x: visible.maxX - 8, y: clampedY)
        case .dragFromTop:
            return CGPoint(x: clampedX, y: visible.maxY - 8)
        case .dragFromBottom:
            return CGPoint(x: clampedX, y: visible.minY - windowSize.height + 8)
        }
    }
}
