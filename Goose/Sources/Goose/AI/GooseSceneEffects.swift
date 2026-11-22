import CoreGraphics
import Foundation

/// Side-effect surface that action tasks call into. Implemented by
/// `GooseScene` so tasks remain decoupled from SpriteKit / AppKit specifics.
@MainActor
protocol GooseSceneEffects: AnyObject {
    // Native window dragging — used by `DragWindowTask` for both notes (real
    // `NSTextView` content) and photos (real `NSImageView` content).
    func attachDraggedWindow(_ window: FloatingWindow, at point: CGPoint, direction: CGFloat)
    func updateDraggedWindowPosition(_ point: CGPoint, direction: CGFloat)
    func detachDraggedWindow()

    /// Toggle the chilling-headphones overlay on the goose.
    func setHeadphones(visible: Bool)

    /// Toggle the floating music-note particle emitter around the goose's head.
    func setMusicNotes(active: Bool)

    /// Toggle the chaotic head-banging dance bob on the goose container.
    func setDancing(active: Bool)

    /// Toggle sleep visual indicator ("z Z z") on the goose.
    func setSleeping(active: Bool)

    /// Show a floating taunt bubble near the goose's beak.
    func showTaunt(_ text: String, at point: CGPoint)

    /// Present a parody fake-error / notification window.
    func showFakeError(style: FakeErrorWindow.Style, customText: String?)

    /// Spawn visual-only fake documents/folders/icons on the desktop overlay.
    func spawnDesktopMess(at point: CGPoint, count: Int)

    /// Pick a virtual icon on the overlay (if any) for GooseTheftTask to steal.
    func takeVirtualIconForTheft() -> (label: String, position: CGPoint)?

    /// Attach/update/cleanup a stolen virtual icon sprite anchored to the beak.
    func attachStolenVirtualIcon(label: String, at point: CGPoint)
    func updateStolenVirtualIcon(at point: CGPoint)
    func detachStolenVirtualIcon()

    /// Event-specific audio + particle feedback.
    func playSoundEvent(_ event: HonkEvent)
    func spawnHearts(at point: CGPoint, count: Int)
}
