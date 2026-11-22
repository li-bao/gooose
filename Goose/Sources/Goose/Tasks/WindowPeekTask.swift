import AppKit
import CoreGraphics
import Foundation

/// Goose hides behind a window edge (or screen edge fallback), peeks out
/// playfully, honks softly, and ducks back.
@MainActor
final class WindowPeekTask: GooseTask {
    private enum Stage {
        case hideAtEdge
        case peeking
        case linger
        case retreat
    }

    private weak var effects: GooseSceneEffects?
    private var stage: Stage = .hideAtEdge
    private var hiddenPos: CGPoint = .zero2
    private var peekPos: CGPoint = .zero2
    private var stageEndTime: CGFloat = 0

    init(effects: GooseSceneEffects? = nil) {
        self.effects = effects
    }

    func start(simulation: GooseSimulation) {
        guard GooseSettings.shared.allows(.windowPeek) else {
            DispatchQueue.main.async { [weak simulation] in simulation?.setTask(WanderTask()) }
            return
        }

        let s = simulation.screenSize
        let screenH = NSScreen.main?.frame.height ?? s.height
        let frame: CGRect
        if let win = AccessibilityProbe.frontmostExternalWindow() {
            frame = win.sceneFrame(screenHeight: screenH)
        } else {
            frame = CGRect(x: 160, y: 140, width: max(300, s.width - 320), height: max(240, s.height - 280))
        }

        // Pick left, right, or top edge to peek from.
        let side = Int.random(in: 0...2)
        let clampedY = min(max(80, frame.midY + CGFloat.random(in: -100...100)), max(81, s.height - 80))
        let clampedX = min(max(80, frame.midX + CGFloat.random(in: -120...120)), max(81, s.width - 80))

        switch side {
        case 0: // Left edge
            hiddenPos = CGPoint(x: max(20, frame.minX + 18), y: clampedY)
            peekPos = CGPoint(x: max(12, frame.minX - 24), y: clampedY)
        case 1: // Right edge
            hiddenPos = CGPoint(x: min(s.width - 20, frame.maxX - 18), y: clampedY)
            peekPos = CGPoint(x: min(s.width - 12, frame.maxX + 24), y: clampedY)
        default: // Top edge
            hiddenPos = CGPoint(x: clampedX, y: max(20, frame.maxY - 22))
            peekPos = CGPoint(x: clampedX, y: min(s.height - 24, frame.maxY + 24))
        }

        simulation.setSpeed(.run)
        simulation.targetPos = hiddenPos
        stage = .hideAtEdge
        stageEndTime = GameTime.time + 5.0
    }

    func tick(simulation: GooseSimulation) {
        guard GooseSettings.shared.allows(.windowPeek), GooseController.shared.allowsProactive else {
            simulation.setTask(WanderTask())
            return
        }

        switch stage {
        case .hideAtEdge:
            simulation.targetPos = hiddenPos
            if CGPoint.distance(simulation.position, hiddenPos) < 22 || GameTime.time >= stageEndTime {
                stage = .peeking
                simulation.setSpeed(.walk)
                simulation.overrideExtendNeck = true
                simulation.targetPos = peekPos
                stageEndTime = GameTime.time + 2.0
            }

        case .peeking:
            simulation.overrideExtendNeck = true
            simulation.targetPos = peekPos
            if CGPoint.distance(simulation.position, peekPos) < 12 || GameTime.time >= stageEndTime {
                effects?.playSoundEvent(.peek) ?? simulation.onHonk?()
                GooseStats.shared.recordPrank("Peeked from behind a window", kind: .window)
                stage = .linger
                stageEndTime = GameTime.time + 2.2
            }

        case .linger:
            simulation.overrideExtendNeck = true
            simulation.velocity = .zero2
            simulation.targetPos = peekPos
            if GameTime.time >= stageEndTime {
                stage = .retreat
                simulation.targetPos = hiddenPos
                stageEndTime = GameTime.time + 1.5
            }

        case .retreat:
            simulation.targetPos = hiddenPos
            if CGPoint.distance(simulation.position, hiddenPos) < 15 || GameTime.time >= stageEndTime {
                simulation.setTask(WanderTask())
            }
        }
    }
}
