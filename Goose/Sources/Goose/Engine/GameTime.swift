import Foundation
import QuartzCore

/// Monotonic game clock. Tick once per frame from the run loop.
/// Supports pause/resume without time jumps so footprints and timers remain consistent.
@MainActor
enum GameTime {
    static let frameRate: Int = 60
    private(set) static var deltaTime: CGFloat = 1.0 / 60.0

    private static let start = CACurrentMediaTime()
    private static var pausedOffset: CFTimeInterval = 0
    private static var pauseStartedAt: CFTimeInterval?
    private(set) static var time: CGFloat = 0

    static var isPaused: Bool { pauseStartedAt != nil }

    static func setPaused(_ paused: Bool) {
        let now = CACurrentMediaTime()
        if paused {
            if pauseStartedAt == nil {
                pauseStartedAt = now
            }
        } else {
            if let started = pauseStartedAt {
                pausedOffset += max(0, now - started)
                pauseStartedAt = nil
            }
        }
    }

    static func tick(dt: TimeInterval? = nil) {
        if let dt {
            deltaTime = CGFloat(min(0.05, max(1.0 / 240.0, dt)))
        } else {
            deltaTime = 1.0 / 60.0
        }
        guard pauseStartedAt == nil else { return }
        time = CGFloat(max(0, CACurrentMediaTime() - start - pausedOffset))
    }

    /// Advances `time` deterministically by `dt` (for headless unit/self tests).
    static func stepForTesting(dt: TimeInterval = 1.0 / 60.0) {
        deltaTime = CGFloat(min(0.05, max(1.0 / 240.0, dt)))
        time += deltaTime
    }
}
