import AppKit
import SpriteKit

@MainActor
final class OverlayWindow: NSWindow {
    let gooseScene: GooseScene
    private let skView: SKView

    init() {
        DisplayManager.shared.refreshScreens()
        let frame = DisplayManager.shared.unionFrame
        let scene = GooseScene(size: frame.size)
        scene.scaleMode = .resizeFill
        scene.backgroundColor = .clear
        self.gooseScene = scene

        let view = SKView(frame: NSRect(origin: .zero, size: frame.size))
        view.allowsTransparency = true
        view.ignoresSiblingOrder = true
        view.preferredFramesPerSecond = 60
        view.presentScene(scene)
        self.skView = view

        super.init(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        contentView = view
    }

    func updateForScreens() {
        DisplayManager.shared.refreshScreens()
        let union = DisplayManager.shared.unionFrame
        setFrame(union, display: true)
        let localSize = union.size
        skView.frame = NSRect(origin: .zero, size: localSize)
        gooseScene.size = localSize
        gooseScene.handleScreenParametersChanged()
    }

    func setRenderingPaused(_ paused: Bool) {
        skView.isPaused = paused
    }

    func setPreferredFPS(_ fps: Int) {
        let clamped = max(15, min(60, fps))
        if skView.preferredFramesPerSecond != clamped {
            skView.preferredFramesPerSecond = clamped
        }
    }

    var isRenderingPaused: Bool { skView.isPaused }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
