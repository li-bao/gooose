import AppKit
import CoreGraphics
import Foundation

/// Iconic Desktop Goose Notepad delivery:
/// 1. Goose walks to the display edge.
/// 2. `GooseNotepadWindow` spawns outside visible screen bounds.
/// 3. Goose grabs the notepad edge with its beak and drags it along a smooth
///    quadratic Bezier path onto the visible screen (`NSScreen.visibleFrame`).
/// 4. Goose releases the interactive notepad and reacts.
@MainActor
final class NotepadDeliveryTask: GooseTask {
    enum Stage {
        case walkingToEdge
        case draggingIn
    }

    let gooseID: UUID
    private let noteTitle: String
    private let noteBody: String
    private weak var effects: GooseSceneEffects?
    private var windowLease: ResourceLease?

    private var stage: Stage = .walkingToEdge
    private var edgeStartScene: CGPoint = .zero
    private var targetScreenFrame: CGRect = .zero
    private var controlPointScene: CGPoint = .zero
    private var dropCenterScene: CGPoint = .zero
    private var progress: CGFloat = 0
    private var notepadWindow: GooseNotepadWindow?

    init(gooseID: UUID = UUID(), title: String, body: String, effects: GooseSceneEffects) {
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
        let localFrame = dm.screenFrames.indices.contains(idx)
            ? dm.screenFrames[idx]
            : CGRect(origin: .zero, size: simulation.screenSize)
        targetScreenFrame = localFrame

        let onLeft = (simulation.position.x - localFrame.minX) < (localFrame.maxX - simulation.position.x)
        let edgeX = onLeft ? localFrame.minX + 10 : localFrame.maxX - 10
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
                beginDrag(simulation: simulation)
            }
        case .draggingIn:
            tickDrag(simulation: simulation)
        }
    }

    func stop(simulation: GooseSimulation) {
        if let lease = windowLease {
            windowLease = nil
            GlobalActionCoordinator.shared.releaseLock(lease)
        }
    }

    private func beginDrag(simulation: GooseSimulation) {
        let win = GooseNotepadWindow(title: noteTitle, body: noteBody)
        NotepadWindowRegistry.shared.register(win, maxVisible: GooseSettings.shared.maxVisibleNotepads)
        notepadWindow = win

        let size = win.targetSize
        let minX = targetScreenFrame.minX + 50 + size.width * 0.5
        let maxX = max(minX + 1, targetScreenFrame.maxX - 50 - size.width * 0.5)
        let minY = targetScreenFrame.minY + 60 + size.height * 0.5
        let maxY = max(minY + 1, targetScreenFrame.maxY - 70 - size.height * 0.5)

        dropCenterScene = CGPoint(
            x: CGFloat.random(in: minX...maxX),
            y: CGFloat.random(in: minY...maxY)
        )
        controlPointScene = CGPoint(
            x: (edgeStartScene.x + dropCenterScene.x) * 0.5,
            y: max(edgeStartScene.y, dropCenterScene.y) + 75
        )

        let offscreenOrigin = MemeDeliveryTask.offscreenOriginGlobal(
            sceneOrigin: edgeStartScene,
            screenFrame: targetScreenFrame,
            windowSize: size
        )
        win.setFrameOrigin(offscreenOrigin)
        win.orderFrontRegardless()

        progress = 0
        stage = .draggingIn
        _ = SoundEffectEngine.shared.playMovement(.paperSlide, category: .notepad, priority: .normal)
    }

    private func tickDrag(simulation: GooseSimulation) {
        guard let win = notepadWindow else {
            simulation.setTask(WanderTask())
            return
        }

        let speed = max(0.35, CGFloat(GooseSettings.shared.deliveryAnimationSpeed))
        progress = min(1.0, progress + CGFloat(GameTime.deltaTime) * 0.72 * speed)

        let t = progress
        let u = 1.0 - t
        let pos = CGPoint(
            x: u * u * edgeStartScene.x + 2 * u * t * controlPointScene.x + t * t * dropCenterScene.x,
            y: u * u * edgeStartScene.y + 2 * u * t * controlPointScene.y + t * t * dropCenterScene.y
        )

        simulation.position = pos
        simulation.targetPos = pos
        simulation.overrideExtendNeck = true

        let globalCenter = DisplayManager.shared.sceneToGlobal(pos)
        let rawOrigin = CGPoint(
            x: globalCenter.x - win.targetSize.width * 0.5,
            y: globalCenter.y - win.targetSize.height * 0.5
        )
        let finalOrigin = MemeDeliveryTask.clampWindowOrigin(
            rawOrigin,
            windowSize: win.targetSize,
            onlyClampAtFinal: t >= 1.0
        )
        win.setFrameOrigin(finalOrigin)

        if progress >= 1.0 {
            win.scheduleAutoDismiss(after: GooseSettings.shared.notepadLifetime)
            _ = SoundEffectEngine.shared.playMovement(.notepadLand, category: .notepad, priority: .normal)
            effects?.playSoundEvent(.prank)
            simulation.setTask(WanderTask())
        }
    }
}
