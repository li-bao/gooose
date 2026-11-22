import CoreGraphics
import Foundation

enum SocialInteractionKind: String, CaseIterable, Sendable {
    case chasePeer
    case avoidPeer
    case walkTogether
    case greetPeer
    case argue
    case playTogether
    case sleepTogether
    case stealMeme
    case shareMemo
    case tugNote
    case spectateHolder
    case flockGather

    var displayName: String {
        switch self {
        case .chasePeer:      return "Chasing another goose"
        case .avoidPeer:      return "Dodging another goose"
        case .walkTogether:   return "Walking together"
        case .greetPeer:      return "Greeting another goose"
        case .argue:          return "Fighting over turf"
        case .playTogether:   return "Playing with another goose"
        case .sleepTogether:  return "Sleeping together"
        case .stealMeme:      return "Stealing a meme"
        case .shareMemo:      return "Sharing a memo"
        case .tugNote:        return "Fighting over a note"
        case .spectateHolder: return "Watching another goose"
        case .flockGather:    return "Flock gathering"
        }
    }
}

/// Decorative multi-goose social behavior. Never acquires Mouse or Window locks,
/// and exits gracefully if the partner goose disappears or sleeps.
@MainActor
final class GooseInteractionTask: GooseTask {
    let kind: SocialInteractionKind
    private weak var partner: GooseInstance?
    private weak var effects: GooseSceneEffects?
    private let flockAnchor: CGPoint?
    private let duration: CGFloat
    private var endTime: CGFloat = 0
    private var nextChatterTime: CGFloat = 0

    init(
        kind: SocialInteractionKind,
        partner: GooseInstance?,
        effects: GooseSceneEffects? = nil,
        flockAnchor: CGPoint? = nil,
        duration: CGFloat = 6.0
    ) {
        self.kind = kind
        self.partner = partner
        self.effects = effects
        self.flockAnchor = flockAnchor
        self.duration = duration
    }

    func start(simulation: GooseSimulation) {
        endTime = GameTime.time + duration
        nextChatterTime = GameTime.time + 1.2

        switch kind {
        case .chasePeer, .avoidPeer, .spectateHolder, .playTogether, .stealMeme:
            simulation.setSpeed(.run)
        case .walkTogether, .flockGather, .greetPeer, .shareMemo:
            simulation.setSpeed(.walk)
            if GooseSettings.shared.allows(.footprints) {
                simulation.trackMudEndTime = max(simulation.trackMudEndTime, GameTime.time + duration)
            }
        case .sleepTogether:
            simulation.setSpeed(.walk)
        case .argue, .tugNote:
            simulation.setSpeed(.walk)
            simulation.overrideExtendNeck = true
            effects?.playSoundEvent(.prank)
        }
    }

    func tick(simulation: GooseSimulation) {
        if GameTime.time >= endTime {
            simulation.setTask(WanderTask())
            return
        }

        if kind != .flockGather {
            guard let partner, partner.isAlive else {
                simulation.setTask(WanderTask())
                return
            }
            if kind == .spectateHolder, GlobalActionCoordinator.shared.mouseHolderID != partner.id {
                simulation.setTask(WanderTask())
                return
            }

            let partnerPos = partner.simulation.position
            switch kind {
            case .chasePeer, .playTogether, .stealMeme:
                simulation.targetPos = partnerPos

            case .avoidPeer:
                let away = CGPoint.normalize(simulation.position - partnerPos)
                let dir = away == .zero2 ? CGPoint(x: 1, y: 0) : away
                let target = simulation.position + dir * 160
                simulation.targetPos = clamp(target, to: simulation.screenSize)

            case .walkTogether:
                let side = CGPoint(x: partner.simulation.targetPos.x + 48, y: partner.simulation.targetPos.y + 18)
                simulation.targetPos = clamp(side, to: simulation.screenSize)

            case .greetPeer, .shareMemo:
                let dist = CGPoint.distance(simulation.position, partnerPos)
                if dist > 68 {
                    simulation.targetPos = partnerPos
                } else {
                    simulation.velocity = .zero2
                    simulation.targetPos = simulation.position
                    let toPartner = partnerPos - simulation.position
                    if toPartner != .zero2 {
                        simulation.direction = atan2(toPartner.y, toPartner.x) * SamMath.rad2Deg
                    }
                    if GameTime.time >= nextChatterTime {
                        nextChatterTime = GameTime.time + 3.0
                        effects?.spawnHearts(at: simulation.beakPosition, count: 1)
                        effects?.showTaunt(kind == .shareMemo ? "check this memo!" : "honk! 👋", at: simulation.beakPosition)
                    }
                }

            case .sleepTogether:
                let spot = CGPoint(x: partnerPos.x + 42, y: partnerPos.y)
                if CGPoint.distance(simulation.position, spot) > 22 {
                    simulation.targetPos = clamp(spot, to: simulation.screenSize)
                } else {
                    simulation.velocity = .zero2
                    simulation.targetPos = simulation.position
                }

            case .argue, .tugNote:
                simulation.overrideExtendNeck = true
                let dist = CGPoint.distance(simulation.position, partnerPos)
                if dist > 62 {
                    simulation.targetPos = partnerPos
                } else {
                    simulation.velocity = .zero2
                    let toPartner = partnerPos - simulation.position
                    if toPartner != .zero2 {
                        simulation.direction = atan2(toPartner.y, toPartner.x) * SamMath.rad2Deg
                    }
                    simulation.targetPos = simulation.position
                    if GameTime.time >= nextChatterTime {
                        nextChatterTime = GameTime.time + 2.5
                        effects?.playSoundEvent(.peek)
                        let line = kind == .tugNote ? "mine! honk!" : "honk?! no, honk!"
                        effects?.showTaunt(line, at: simulation.beakPosition)
                    }
                }

            case .spectateHolder:
                let behind = partnerPos + CGPoint(x: -55, y: -35)
                simulation.targetPos = clamp(behind, to: simulation.screenSize)

            case .flockGather:
                break
            }
        } else if let anchor = flockAnchor {
            let dist = CGPoint.distance(simulation.position, anchor)
            if dist > 75 {
                simulation.targetPos = anchor
            } else {
                simulation.velocity = .zero2
                simulation.targetPos = simulation.position
            }
        }
    }

    private func clamp(_ p: CGPoint, to size: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(45, p.x), max(46, size.width - 45)),
            y: min(max(45, p.y), max(46, size.height - 45))
        )
    }
}
