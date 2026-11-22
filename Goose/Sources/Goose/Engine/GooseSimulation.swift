import CoreGraphics
import Foundation

/// Goose body speed presets. Selected by tasks.
enum SpeedTier {
    case walk
    case run
    case charge
}

/// The "soul" of the goose: position, velocity, feet animation state, and
/// the currently-running task. Updated every frame; rig + visuals derive
/// from this snapshot.
@MainActor
final class GooseSimulation {
    var screenSize: CGSize = .zero

    var position: CGPoint = CGPoint(x: 300, y: 300)
    var velocity: CGPoint = .zero2
    var direction: CGFloat = 90
    var targetPos: CGPoint = CGPoint(x: 300, y: 300)
    var targetDirection: CGPoint = .zero2

    /// Set every frame from Settings (Goose → Movement / Animation speed).
    var speedMultiplier: CGFloat = 1
    var animationMultiplier: CGFloat = 1
    /// Goose size multiplier (Settings → General). Scales the beak anchor so
    /// carried windows / the captured cursor follow the visual beak.
    var sizeScale: CGFloat = 1

    private var baseSpeed: CGFloat = 80
    private var baseAcceleration: CGFloat = 1300
    private var baseStepTime: CGFloat = 0.2
    private(set) var speedTier: SpeedTier = .walk

    var currentSpeed: CGFloat { baseSpeed * speedMultiplier }
    var currentAcceleration: CGFloat { baseAcceleration * speedMultiplier }
    var stepTime: CGFloat { baseStepTime / max(animationMultiplier, 0.1) }

    var neckLerpPercent: CGFloat = 0
    var overrideExtendNeck = false

    var lFootPos: CGPoint = .zero2
    var rFootPos: CGPoint = .zero2
    private var lFootMoveOrigin: CGPoint = .zero2
    private var rFootMoveOrigin: CGPoint = .zero2
    private var lFootMoveDir: CGPoint = .zero2
    private var rFootMoveDir: CGPoint = .zero2
    private var lFootMoveTimeStart: CGFloat = -1
    private var rFootMoveTimeStart: CGFloat = -1

    var footMarks: [FootMark] = Array(repeating: FootMark(), count: 64)
    private var footMarkIndex = 0
    var trackMudEndTime: CGFloat = -1

    private(set) var currentTask: GooseTask?

    var onFootLand: (() -> Void)?
    var onHonk: (() -> Void)?
    var onBite: (() -> Void)?

    init() {
        lFootPos = footHome(rightFoot: false)
        rFootPos = footHome(rightFoot: true)
    }

    func setSpeed(_ tier: SpeedTier) {
        speedTier = tier
        switch tier {
        case .walk:
            baseSpeed = 80
            baseAcceleration = 1300
            baseStepTime = 0.2
        case .run:
            baseSpeed = 200
            baseAcceleration = 1300
            baseStepTime = 0.2
        case .charge:
            baseSpeed = 400
            baseAcceleration = 2300
            baseStepTime = 0.1
        }
    }

    func setTask(_ task: GooseTask) {
        // Give the outgoing task a chance to release visuals/state. Critical
        // for tasks like ChillingTask that paint headphones / music-notes /
        // dance bob and would otherwise leave them stuck on if preempted by
        // a click, a rage event, or any other setTask caller.
        currentTask?.stop(simulation: self)
        currentTask = task
        task.start(simulation: self)
    }

    func tick() {
        targetDirection = CGPoint.normalize(targetPos - position)
        overrideExtendNeck = false
        currentTask?.tick(simulation: self)

        let smoothed = CGPoint.lerp(.fromAngleDegrees(direction), targetDirection, 0.25)
        direction = atan2(smoothed.y, smoothed.x) * SamMath.rad2Deg

        // Deadband: snap cleanly when within a single frame's step to prevent micro-jitter.
        let toTarget = targetPos - position
        let dist = CGPoint.magnitude(toTarget)
        let snapThreshold = max(1.5, currentSpeed * GameTime.deltaTime)
        if dist > snapThreshold {
            velocity += CGPoint.normalize(toTarget) * currentAcceleration * GameTime.deltaTime
            if CGPoint.magnitude(velocity) > currentSpeed {
                velocity = CGPoint.normalize(velocity) * currentSpeed
            }
            position += velocity * GameTime.deltaTime
        } else {
            velocity = .zero2
        }

        solveFeet()

        let neckTarget: CGFloat = (overrideExtendNeck || speedTier != .walk) ? 1 : 0
        neckLerpPercent = SamMath.lerp(neckLerpPercent, neckTarget, 0.075)
    }

    func footHome(rightFoot: Bool) -> CGPoint {
        let bias: CGFloat = rightFoot ? 1 : 0
        let perpendicular = CGPoint.fromAngleDegrees(direction + 90)
        return position + perpendicular * bias * 6
    }

    /// Tip of the goose's beak in world coordinates. Cheap to read each frame
    /// — recomputes the rig from current `position`/`direction`/`neckLerp`.
    /// Used by tasks that need to anchor things (a captured cursor, a stolen
    /// window) to the goose's beak.
    var beakPosition: CGPoint {
        var rig = GooseRig()
        rig.update(position: position, directionDegrees: direction, neckLerp: neckLerpPercent)
        let tip = rig.head2EndPoint
        return CGPoint(x: position.x + (tip.x - position.x) * sizeScale,
                       y: position.y + (tip.y - position.y) * sizeScale)
    }

    private func solveFeet() {
        let lHome = footHome(rightFoot: false)
        let rHome = footHome(rightFoot: true)
        let bothFeetIdle = lFootMoveTimeStart < 0 && rFootMoveTimeStart < 0

        if bothFeetIdle {
            if CGPoint.distance(lFootPos, lHome) > 5 {
                beginFootStep(left: true, home: lHome)
                return
            }
            if CGPoint.distance(rFootPos, rHome) > 5 {
                beginFootStep(left: false, home: rHome)
                return
            }
            return
        }

        if lFootMoveTimeStart >= 0 {
            advanceFootStep(left: true, home: lHome)
        } else if rFootMoveTimeStart >= 0 {
            advanceFootStep(left: false, home: rHome)
        }
    }

    private func beginFootStep(left: Bool, home: CGPoint) {
        let direction = CGPoint.normalize(home - (left ? lFootPos : rFootPos))
        if left {
            lFootMoveOrigin = lFootPos
            lFootMoveDir = direction
            lFootMoveTimeStart = GameTime.time
        } else {
            rFootMoveOrigin = rFootPos
            rFootMoveDir = direction
            rFootMoveTimeStart = GameTime.time
        }
    }

    private func advanceFootStep(left: Bool, home: CGPoint) {
        let moveDir = left ? lFootMoveDir : rFootMoveDir
        let origin = left ? lFootMoveOrigin : rFootMoveOrigin
        let target = home + moveDir * 0.4 * 5
        let startTime = left ? lFootMoveTimeStart : rFootMoveTimeStart
        let elapsed = GameTime.time - startTime

        if elapsed >= stepTime {
            placeFoot(left: left, at: target)
            if left { lFootMoveTimeStart = -1 } else { rFootMoveTimeStart = -1 }
            onFootLand?()
            // Leave directional footprints during muddy chases/drags or regular walks
            // whenever Footprints are enabled (subtle step cadence on normal walks).
            if GooseSettings.shared.allows(.footprints),
               (GameTime.time < trackMudEndTime || speedTier == .walk || speedTier == .run) {
                addFootMark(at: target, isRight: !left)
            }
        } else {
            let p = elapsed / stepTime
            let interpolated = CGPoint.lerp(origin, target, Easings.cubicEaseInOut(p))
            placeFoot(left: left, at: interpolated)
        }
    }

    private func placeFoot(left: Bool, at point: CGPoint) {
        if left {
            lFootPos = point
        } else {
            rFootPos = point
        }
    }

    func addFootMark(at point: CGPoint, isRight: Bool = false) {
        let settings = GooseSettings.shared
        guard settings.allows(.footprints) else { return }
        syncFootMarkCapacity(max(16, min(128, settings.footprintMaxCount)))
        guard !footMarks.isEmpty else { return }
        let angle = direction * SamMath.deg2Rad
        footMarks[footMarkIndex] = FootMark(position: point, angle: angle, isRight: isRight, time: GameTime.time)
        footMarkIndex = (footMarkIndex + 1) % footMarks.count
    }

    func syncFootMarkCapacity(_ capacity: Int) {
        let target = max(16, min(128, capacity))
        guard footMarks.count != target else { return }
        if target > footMarks.count {
            footMarks.append(contentsOf: repeatElement(FootMark(), count: target - footMarks.count))
        } else {
            let ordered = (0..<footMarks.count).map { footMarks[(footMarkIndex + $0) % footMarks.count] }
            footMarks = Array(ordered.suffix(target))
            footMarkIndex = 0
        }
    }

    func clearFootMarks() {
        for i in footMarks.indices {
            footMarks[i] = FootMark()
        }
        footMarkIndex = 0
    }
}
