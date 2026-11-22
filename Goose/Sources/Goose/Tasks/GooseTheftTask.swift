import CoreGraphics
import Foundation

/// Visual-only icon theft: the goose runs to a virtual icon on the overlay
/// (or creates a transient visual icon), grabs it with its beak, and drags it
/// off the edge of the screen. Never moves or modifies real desktop files.
@MainActor
final class GooseTheftTask: GooseTask {
    private enum Stage {
        case approachIcon
        case dragOffscreen
    }

    private weak var effects: GooseSceneEffects?
    private var stage: Stage = .approachIcon
    private var iconLabel = "Important.app"
    private var iconOrigin: CGPoint = .zero2
    private var exitPoint: CGPoint = .zero2
    private var stageEndTime: CGFloat = 0
    private var attached = false

    init(effects: GooseSceneEffects? = nil) {
        self.effects = effects
    }

    func start(simulation: GooseSimulation) {
        guard GooseSettings.shared.allows(.gooseTheft) else {
            DispatchQueue.main.async { [weak simulation] in simulation?.setTask(WanderTask()) }
            return
        }

        if let existing = effects?.takeVirtualIconForTheft() {
            iconLabel = existing.label
            iconOrigin = existing.position
        } else {
            iconLabel = DesktopMessOverlay.ItemKind.sampleNames[.fakeIcon]?.randomElement() ?? "Trash (Full)"
            let w = max(240, simulation.screenSize.width)
            let h = max(240, simulation.screenSize.height)
            iconOrigin = CGPoint(x: CGFloat.random(in: 120...(w - 120)), y: CGFloat.random(in: 140...(h - 140)))
        }

        stage = .approachIcon
        attached = false
        simulation.setSpeed(.run)
        simulation.targetPos = iconOrigin
        simulation.trackMudEndTime = max(simulation.trackMudEndTime, GameTime.time + 12.0)
        stageEndTime = GameTime.time + 6.0
    }

    func tick(simulation: GooseSimulation) {
        guard GooseSettings.shared.allows(.gooseTheft), GooseController.shared.allowsProactive else {
            simulation.setTask(WanderTask())
            return
        }

        switch stage {
        case .approachIcon:
            simulation.targetPos = iconOrigin
            if CGPoint.distance(simulation.position, iconOrigin) < 30 || GameTime.time >= stageEndTime {
                attached = true
                effects?.attachStolenVirtualIcon(label: iconLabel, at: simulation.beakPosition)
                effects?.playSoundEvent(.theft) ?? simulation.onHonk?()
                GooseStats.shared.recordPrank("Stole virtual icon: \(iconLabel)", kind: .window)

                let toLeft = simulation.position.x < simulation.screenSize.width * 0.5
                exitPoint = CGPoint(
                    x: toLeft ? -70 : simulation.screenSize.width + 70,
                    y: simulation.position.y
                )
                simulation.setSpeed(.charge)
                simulation.targetPos = exitPoint
                stage = .dragOffscreen
                stageEndTime = GameTime.time + 6.0
            }

        case .dragOffscreen:
            if attached {
                effects?.updateStolenVirtualIcon(at: simulation.beakPosition)
            }
            if CGPoint.distance(simulation.position, exitPoint) < 35 || GameTime.time >= stageEndTime {
                simulation.setTask(WanderTask())
            }
        }
    }

    func stop(simulation: GooseSimulation) {
        if attached {
            effects?.detachStolenVirtualIcon()
            attached = false
        }
    }
}
