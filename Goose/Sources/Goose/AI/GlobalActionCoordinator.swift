import ApplicationServices
import CoreGraphics
import Foundation

enum GlobalResourceType: String, Hashable, Sendable {
    case none
    case mouse
    case window
    case screenCapture
}

enum ActionPriority: Int, Comparable, Sendable {
    case decorative = 20
    case normalPrank = 40
    case activeGlobalPrank = 60
    case userDirectControl = 80
    case emergencyStop = 100

    static func < (lhs: ActionPriority, rhs: ActionPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum CoordinatedTaskStatus: String, Sendable {
    case pending
    case running
    case completed
    case cancelled
    case timedOut
    case failed
}

@MainActor
final class CancellationToken {
    private(set) var isCancelled = false
    var onCancel: (() -> Void)?

    init(onCancel: (() -> Void)? = nil) {
        self.onCancel = onCancel
    }

    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        let handler = onCancel
        onCancel = nil
        handler?()
    }
}

struct CoordinatedTask: Identifiable, Sendable {
    let id: UUID
    let gooseID: UUID
    let resourceType: GlobalResourceType
    let priority: ActionPriority
    let startTime: Date
    let timeout: TimeInterval
    var status: CoordinatedTaskStatus
}

struct ResourceLease: Sendable, Equatable {
    let id: UUID
    let gooseID: UUID
    let resourceType: GlobalResourceType
    let acquiredAt: Date
    let expiresAt: Date
    let priority: ActionPriority
}

/// Sole authority for global system resource locks (Mouse & Window) across all geese.
/// Invariant: at any instant, `activeMouseHolderCount <= 1` and `activeWindowHolderCount <= 1`.
/// No task may invoke `CGWarpMouseCursorPosition` or `AXUIElement` window moves without
/// presenting a valid, active `ResourceLease` from this coordinator.
@MainActor
final class GlobalActionCoordinator {
    static let shared = GlobalActionCoordinator()

    static let maxMouseLockDuration: TimeInterval = 20.0
    static let maxWindowLockDuration: TimeInterval = 20.0

    private var mouseLease: ResourceLease?
    private var windowLease: ResourceLease?
    private var tokens: [UUID: CancellationToken] = [:]
    private(set) var activeTasks: [UUID: CoordinatedTask] = [:]
    private var lastGrantAt: [UUID: Date] = [:]

    private(set) var maxObservedConcurrentMouseHolders = 0
    private(set) var maxObservedConcurrentWindowHolders = 0

    private init() {}

    var mouseHolderID: UUID? { mouseLease?.gooseID }
    var windowHolderID: UUID? { windowLease?.gooseID }

    var activeMouseHolderCount: Int { mouseLease == nil ? 0 : 1 }
    var activeWindowHolderCount: Int { windowLease == nil ? 0 : 1 }

    /// Attempts to acquire an exclusive lease on `resource` for `gooseID`.
    /// Rejects lower-or-equal priority requests while held; preempts only if
    /// `priority` strictly outranks the current holder.
    func acquireLock(
        for gooseID: UUID,
        resource: GlobalResourceType,
        priority: ActionPriority,
        timeout: TimeInterval,
        onCancel: (() -> Void)? = nil
    ) -> ResourceLease? {
        tickTimeouts()

        guard resource == .mouse || resource == .window else {
            return nil
        }

        let maxCap = resource == .mouse ? Self.maxMouseLockDuration : Self.maxWindowLockDuration
        let effectiveTimeout = max(0.5, min(maxCap, timeout))
        let existing = (resource == .mouse) ? mouseLease : windowLease

        if let current = existing {
            if current.gooseID == gooseID {
                // Same goose re-acquiring: replace cleanly without increasing holder count.
                releaseLock(current, status: .cancelled)
            } else if priority > current.priority {
                // Strictly higher priority preempts the existing holder.
                releaseLock(current, status: .cancelled)
            } else {
                // Reject cleanly so caller picks a non-conflicting behavior.
                return nil
            }
        }

        let now = Date()
        let leaseID = UUID()
        let lease = ResourceLease(
            id: leaseID,
            gooseID: gooseID,
            resourceType: resource,
            acquiredAt: now,
            expiresAt: now.addingTimeInterval(effectiveTimeout),
            priority: priority
        )

        let token = CancellationToken(onCancel: onCancel)
        tokens[leaseID] = token
        activeTasks[leaseID] = CoordinatedTask(
            id: leaseID,
            gooseID: gooseID,
            resourceType: resource,
            priority: priority,
            startTime: now,
            timeout: effectiveTimeout,
            status: .running
        )
        lastGrantAt[gooseID] = now

        if resource == .mouse {
            mouseLease = lease
            maxObservedConcurrentMouseHolders = max(maxObservedConcurrentMouseHolders, activeMouseHolderCount)
        } else {
            windowLease = lease
            maxObservedConcurrentWindowHolders = max(maxObservedConcurrentWindowHolders, activeWindowHolderCount)
        }
        return lease
    }

    func isValidLease(_ lease: ResourceLease) -> Bool {
        if let tok = tokens[lease.id], tok.isCancelled {
            return false
        }
        if Date() >= lease.expiresAt {
            return false
        }
        switch lease.resourceType {
        case .mouse:
            return mouseLease?.id == lease.id
        case .window:
            return windowLease?.id == lease.id
        case .none, .screenCapture:
            return false
        }
    }

    func releaseLock(_ lease: ResourceLease, status: CoordinatedTaskStatus = .completed) {
        if mouseLease?.id == lease.id {
            mouseLease = nil
        }
        if windowLease?.id == lease.id {
            windowLease = nil
        }
        let token = tokens.removeValue(forKey: lease.id)
        if var task = activeTasks.removeValue(forKey: lease.id) {
            task.status = status
        }
        if status == .cancelled || status == .timedOut || status == .failed {
            token?.cancel()
        }
    }

    /// Cancels and releases every lock and task owned by `gooseID` (e.g. on removal).
    func releaseAllLocks(for gooseID: UUID) {
        if let m = mouseLease, m.gooseID == gooseID {
            releaseLock(m, status: .cancelled)
        }
        if let w = windowLease, w.gooseID == gooseID {
            releaseLock(w, status: .cancelled)
        }
        let matching = activeTasks.values.filter { $0.gooseID == gooseID }.map(\.id)
        for taskID in matching {
            activeTasks.removeValue(forKey: taskID)
            tokens.removeValue(forKey: taskID)?.cancel()
        }
        lastGrantAt.removeValue(forKey: gooseID)
    }

    /// Immediately cancels every active task token and clears all global locks.
    func emergencyStopAll() {
        let allTokens = Array(tokens.values)
        mouseLease = nil
        windowLease = nil
        tokens.removeAll()
        activeTasks.removeAll()
        for tok in allTokens {
            tok.cancel()
        }
    }

    /// Expires any leases whose deadline has passed so a stuck task cannot starve others.
    func tickTimeouts() {
        let now = Date()
        if let m = mouseLease, now >= m.expiresAt {
            releaseLock(m, status: .timedOut)
        }
        if let w = windowLease, now >= w.expiresAt {
            releaseLock(w, status: .timedOut)
        }
    }

    /// Fairness helper: seconds since `gooseID` last held a global resource lock.
    func timeSinceLastGrant(for gooseID: UUID) -> TimeInterval {
        guard let date = lastGrantAt[gooseID] else { return .greatestFiniteMagnitude }
        return Date().timeIntervalSince(date)
    }

    func resetMetrics() {
        maxObservedConcurrentMouseHolders = activeMouseHolderCount
        maxObservedConcurrentWindowHolders = activeWindowHolderCount
    }

    // MARK: - Guarded Global Resource Operations

    /// The ONLY permitted path for warping the system cursor.
    @discardableResult
    func warpMouseGuarded(to point: CGPoint, lease: ResourceLease) -> Bool {
        guard lease.resourceType == .mouse, isValidLease(lease) else {
            return false
        }
        CGWarpMouseCursorPosition(point)
        return true
    }

    /// The ONLY permitted path for repositioning an external app window via Accessibility.
    @discardableResult
    func setWindowOriginGuarded(_ element: AXUIElement, to point: CGPoint, lease: ResourceLease) -> Bool {
        guard lease.resourceType == .window, isValidLease(lease) else {
            return false
        }
        return AccessibilityProbe.setWindowOrigin(element, to: point)
    }
}
