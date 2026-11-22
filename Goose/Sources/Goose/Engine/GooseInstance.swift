import CoreGraphics
import Foundation
import SpriteKit

enum GooseAIState: Sendable, Equatable {
    case idle
    case thinking
    case acting(String)
    case sleeping
    case interacting(String)
    case waitingForLock(GlobalResourceType)

    var displayText: String {
        switch self {
        case .idle:                   return "Idle"
        case .thinking:               return "Thinking"
        case .acting(let name):       return name
        case .sleeping:               return "Sleeping"
        case .interacting(let desc):  return desc
        case .waitingForLock(let r):  return "Waiting (\(r.rawValue))"
        }
    }
}

struct GooseInteractionRecord: Sendable {
    let timestamp: Date
    let summary: String
}

/// First-class individual goose actor/entity managed by `GooseManager`.
/// Owns its own UUID, personality, simulation, animation rig, AI state,
/// individual cooldowns, energy, and bounded interaction history.
@MainActor
final class GooseInstance: Identifiable {
    let id = UUID()
    let numericID: Int
    let isLead: Bool

    let simulation = GooseSimulation()
    let art = GooseArt()
    let container = SKNode()
    let personality: GoosePersonality

    var aiState: GooseAIState = .idle
    var behaviorCooldowns: [GooseBehavior: Date] = [:]
    var interactionHistory: [GooseInteractionRecord] = []
    var nextThinkTime: CGFloat
    private(set) var isAlive = true

    private static let historyCap = 20

    var marksNode: SKNode { art.marksNode }

    /// Individual energy level (0.0 exhausted ... 1.0 rested), derived from `personality.energy`.
    var energy: Double { max(0, min(1, personality.energy / 100.0)) }
    var energyPercent: Int { Int(personality.energy.rounded()) }
    var emotion: GooseEmotion { personality.emotion }

    init(numericID: Int, isLead: Bool, screenSize: CGSize) {
        self.numericID = numericID
        self.isLead = isLead
        self.personality = GoosePersonality(numericID: numericID, isLead: isLead)

        simulation.screenSize = screenSize
        let w = max(220, screenSize.width)
        let h = max(220, screenSize.height)
        if isLead {
            simulation.position = CGPoint(x: w / 2, y: h / 2)
            simulation.direction = 180
        } else {
            simulation.position = CGPoint(x: CGFloat.random(in: 100...(w - 100)),
                                          y: CGFloat.random(in: 100...(h - 100)))
            simulation.direction = CGFloat.random(in: 0..<360)
        }
        simulation.targetPos = simulation.position
        simulation.lFootPos = simulation.footHome(rightFoot: false)
        simulation.rFootPos = simulation.footHome(rightFoot: true)
        simulation.setTask(WanderTask())

        container.addChild(art.node)
        art.update(simulation: simulation)
        nextThinkTime = GameTime.time + CGFloat.random(in: 8...14)
    }

    func canUseBehavior(_ behavior: GooseBehavior, cooldown: TimeInterval) -> Bool {
        guard let last = behaviorCooldowns[behavior] else { return true }
        return Date().timeIntervalSince(last) >= cooldown
    }

    func markBehaviorUsed(_ behavior: GooseBehavior) {
        behaviorCooldowns[behavior] = Date()
    }

    func recordInteraction(_ summary: String) {
        interactionHistory.append(GooseInteractionRecord(timestamp: Date(), summary: summary))
        if interactionHistory.count > Self.historyCap {
            interactionHistory.removeFirst(interactionHistory.count - Self.historyCap)
        }
    }

    func refreshAIState(from task: GooseTask?) {
        switch task {
        case is NapTask, is DeepSleepTask:
            aiState = .sleeping
        case let social as GooseInteractionTask:
            aiState = .interacting(social.kind.displayName)
        case is WanderTask, .none:
            aiState = .idle
        case is NabMouseTask:
            aiState = .acting("Mouse Theft")
        case is DragWindowTask:
            aiState = .acting("Window Drag")
        case is WindowPrankTask:
            aiState = .acting("Window Prank")
        case is MouseChaseTask:
            aiState = .acting("Mouse Chase")
        case is FakeErrorTask:
            aiState = .acting("Fake Error")
        case is DesktopMessTask:
            aiState = .acting("Desktop Mess")
        case is GooseTheftTask:
            aiState = .acting("Goose Theft")
        case is WindowPeekTask:
            aiState = .acting("Window Peek")
        default:
            aiState = .acting("Busy")
        }
    }

    /// Cleanly cancels active tasks, releases ALL coordinator locks held by
    /// this goose, and removes its SpriteKit nodes from the scene.
    func teardown() {
        guard isAlive else { return }
        isAlive = false
        personality.persistState()
        GlobalActionCoordinator.shared.releaseAllLocks(for: id)
        BehaviorScheduler.shared.cancelAll(on: simulation)
        simulation.clearFootMarks()
        container.removeFromParent()
        art.marksNode.removeFromParent()
    }
}
