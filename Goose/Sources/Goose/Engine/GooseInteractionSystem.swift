import CoreGraphics
import Foundation

/// Evaluates peer interactions across active geese on the main loop
/// (no extra per-goose timers). Respects sleeping geese and never steals
/// or interferes with global resource locks.
@MainActor
final class GooseInteractionSystem {
    static let shared = GooseInteractionSystem()

    private var nextEvaluationTime: CGFloat = 0
    private static let evaluationInterval: CGFloat = 6.0

    private init() {}

    func reset() {
        nextEvaluationTime = 0
    }

    func tick(geese: [GooseInstance], scene: GooseSceneEffects) {
        guard geese.count >= 2,
              GooseController.shared.allowsProactive,
              GooseSettings.shared.randomBehavior else {
            return
        }
        guard GameTime.time >= nextEvaluationTime else { return }
        nextEvaluationTime = GameTime.time + Self.evaluationInterval

        // 1) If one goose holds Mouse Lock, nearby idle peers may spectate/chase it.
        if let holderID = GlobalActionCoordinator.shared.mouseHolderID,
           let holder = geese.first(where: { $0.id == holderID && $0.isAlive }) {
            for peer in geese where peer.id != holderID && isAvailableForSocial(peer) {
                if Double.random(in: 0..<1) < 0.45 {
                    let task = GooseInteractionTask(kind: .spectateHolder, partner: holder, effects: scene, duration: 5.5)
                    peer.simulation.setTask(task)
                    peer.recordInteraction("Spectated Goose \(holder.numericID)")
                }
            }
            return
        }

        // 2) Gather available (non-sleeping, non-lock-holding, wandering) geese.
        let available = geese.filter(isAvailableForSocial)
        guard available.count >= 2 else { return }

        // 20% chance of flock gathering when 3+ geese are free.
        if available.count >= 3 && Double.random(in: 0..<1) < 0.22 {
            let anchor = CGPoint(
                x: CGFloat.random(in: 140...max(141, available[0].simulation.screenSize.width - 140)),
                y: CGFloat.random(in: 140...max(141, available[0].simulation.screenSize.height - 140))
            )
            for goose in available {
                let task = GooseInteractionTask(kind: .flockGather, partner: nil, effects: scene, flockAnchor: anchor, duration: 6.5)
                goose.simulation.setTask(task)
                goose.recordInteraction("Joined flock gathering")
            }
            return
        }

        // Pair two geese for chase/avoid/walk/argue/tugNote.
        let a = available[0]
        let b = available[1]
        let kinds: [SocialInteractionKind] = [.chasePeer, .walkTogether, .argue, .tugNote]
        let pick = kinds.randomElement() ?? .walkTogether

        switch pick {
        case .chasePeer:
            a.simulation.setTask(GooseInteractionTask(kind: .chasePeer, partner: b, effects: scene, duration: 5.0))
            b.simulation.setTask(GooseInteractionTask(kind: .avoidPeer, partner: a, effects: scene, duration: 5.0))
            a.recordInteraction("Chased Goose \(b.numericID)")
            b.recordInteraction("Dodged Goose \(a.numericID)")

        case .walkTogether:
            a.simulation.setTask(GooseInteractionTask(kind: .walkTogether, partner: b, effects: scene, duration: 6.0))
            b.simulation.setTask(GooseInteractionTask(kind: .walkTogether, partner: a, effects: scene, duration: 6.0))
            a.recordInteraction("Walked with Goose \(b.numericID)")
            b.recordInteraction("Walked with Goose \(a.numericID)")

        case .argue, .tugNote:
            a.simulation.setTask(GooseInteractionTask(kind: pick, partner: b, effects: scene, duration: 5.5))
            b.simulation.setTask(GooseInteractionTask(kind: pick, partner: a, effects: scene, duration: 5.5))
            a.recordInteraction("\(pick.rawValue) with Goose \(b.numericID)")
            b.recordInteraction("\(pick.rawValue) with Goose \(a.numericID)")

        default:
            break
        }
    }

    private func isAvailableForSocial(_ goose: GooseInstance) -> Bool {
        guard goose.isAlive else { return false }
        let coord = GlobalActionCoordinator.shared
        if coord.mouseHolderID == goose.id || coord.windowHolderID == goose.id {
            return false
        }
        return goose.simulation.currentTask is WanderTask
    }
}
