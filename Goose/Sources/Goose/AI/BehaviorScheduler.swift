import Foundation

/// Unified behavior scheduler shared across all geese.
/// Enforces priority ordering, sleep protection, global/per-behavior cooldowns,
/// mutual exclusion for cursor/window tasks, and task timeouts.
@MainActor
final class BehaviorScheduler {
    static let shared = BehaviorScheduler()

    enum Priority: Int, Comparable, Sendable {
        case idle = 10
        case ambient = 30
        case prank = 50
        case reactive = 80
        case emergency = 100

        static func < (lhs: Priority, rhs: Priority) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    private struct ActiveSlot {
        let priority: Priority
        let behavior: GooseBehavior?
        let deadline: CGFloat?
    }

    private var slots: [ObjectIdentifier: ActiveSlot] = [:]
    private var lastBehaviorUse: [GooseBehavior: Date] = [:]
    private var recentDecisions: [String] = []
    private static let recentCap = 5
    private static let perBehaviorCooldown: TimeInterval = 12

    private init() {}

    /// Checks whether `simulation` can accept a task of `priority` right now.
    func allowsTaskStart(priority: Priority, behavior: GooseBehavior?, on simulation: GooseSimulation) -> Bool {
        let controller = GooseController.shared
        let settings = GooseSettings.shared

        if priority == .emergency { return true }
        guard controller.allowsProactive else { return false }

        if let behavior, !settings.allows(behavior) {
            return false
        }

        // Fullscreen game awareness: pause high-disruption pranks during fullscreen games.
        if priority < .reactive,
           FullscreenMonitor.shared.suppressesHighDisruptionPranks,
           let behavior,
           [.mouseTheft, .mouseDragging, .windowPranks, .fakeErrors].contains(behavior) {
            return false
        }

        // Sleep protection: proactive actions never interrupt a sleeping goose.
        let isSleeping = simulation.currentTask is NapTask || simulation.currentTask is DeepSleepTask
        if isSleeping && priority < .reactive {
            return false
        }

        // Prank cooldowns (reactive user-triggered responses bypass proactive cooldown).
        if priority == .prank {
            guard controller.prankCooldownElapsed() else { return false }
            if let behavior, let last = lastBehaviorUse[behavior],
               Date().timeIntervalSince(last) < Self.perBehaviorCooldown {
                return false
            }
        }

        // Do not let a lower-priority request preempt a running higher-priority task.
        let key = ObjectIdentifier(simulation)
        if let active = slots[key], !(simulation.currentTask is WanderTask) {
            if priority < active.priority {
                return false
            }
        }

        return true
    }

    /// Attempts to schedule `task` onto `simulation` with priority, cooldown, and timeout guards.
    @discardableResult
    func request(
        priority: Priority,
        task: GooseTask,
        behavior: GooseBehavior? = nil,
        timeout: TimeInterval? = nil,
        on simulation: GooseSimulation
    ) -> Bool {
        guard allowsTaskStart(priority: priority, behavior: behavior, on: simulation) else {
            return false
        }

        // Mutexes via GlobalActionCoordinator: refuse global-resource tasks when lock is held by another goose.
        if task is NabMouseTask, let holder = GlobalActionCoordinator.shared.mouseHolderID {
            let candidateID = (task as? NabMouseTask)?.gooseID
            if holder != candidateID && priority < .reactive {
                return false
            }
        }
        if (task is WindowPrankTask || task is DragWindowTask), let holder = GlobalActionCoordinator.shared.windowHolderID {
            let candidateID = (task as? WindowPrankTask)?.gooseID ?? (task as? DragWindowTask)?.gooseID
            if holder != candidateID && priority < .reactive {
                return false
            }
        }

        let key = ObjectIdentifier(simulation)
        let deadline: CGFloat? = timeout.map { GameTime.time + CGFloat($0) }
        slots[key] = ActiveSlot(priority: priority, behavior: behavior, deadline: deadline)

        if let behavior {
            lastBehaviorUse[behavior] = Date()
            recentDecisions.append(behavior.rawValue)
            if recentDecisions.count > Self.recentCap {
                recentDecisions.removeFirst()
            }
        }

        simulation.setTask(task)
        return true
    }

    /// Periodic maintenance called during simulation ticks to enforce task timeouts.
    func tick(simulation: GooseSimulation) {
        let key = ObjectIdentifier(simulation)
        guard let slot = slots[key] else { return }

        if simulation.currentTask is WanderTask {
            slots.removeValue(forKey: key)
            return
        }

        if let deadline = slot.deadline, GameTime.time >= deadline {
            slots.removeValue(forKey: key)
            simulation.setTask(WanderTask())
        }
    }

    func cancelAll(on simulation: GooseSimulation) {
        slots.removeValue(forKey: ObjectIdentifier(simulation))
        simulation.setTask(WanderTask())
    }

    func emergencyStop(on simulations: [GooseSimulation]) {
        slots.removeAll()
        GlobalActionCoordinator.shared.emergencyStopAll()
        for sim in simulations {
            sim.setTask(WanderTask())
        }
    }

    func resetCooldowns() {
        lastBehaviorUse.removeAll()
        recentDecisions.removeAll()
        slots.removeAll()
    }
}
