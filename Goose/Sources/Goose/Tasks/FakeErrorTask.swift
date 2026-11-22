import CoreGraphics
import Foundation

/// Goose honks and presents a parody Fake Error / Crash / System Notification
/// window (never masquerading as a password or security prompt).
@MainActor
final class FakeErrorTask: GooseTask {
    private weak var effects: GooseSceneEffects?
    private weak var personality: GoosePersonality?
    private var triggered = false

    init(effects: GooseSceneEffects? = nil, personality: GoosePersonality? = nil) {
        self.effects = effects
        self.personality = personality
    }

    func start(simulation: GooseSimulation) {
        guard GooseSettings.shared.allows(.fakeErrors) else {
            DispatchQueue.main.async { [weak simulation] in simulation?.setTask(WanderTask()) }
            return
        }
        simulation.velocity = .zero2
        simulation.targetPos = simulation.position
        effects?.playSoundEvent(.prank) ?? simulation.onHonk?()

        let style = FakeErrorWindow.Style.allCases.randomElement() ?? .warning
        let eff = effects
        let pers = personality
        triggered = true
        GooseStats.shared.recordPrank("Fake \(style.rawValue) alert", kind: .window)

        Task { @MainActor [weak simulation] in
            let text = await GooseController.shared.llm.generateFakeErrorMessage(personality: pers, style: style)
            guard GooseSettings.shared.allows(.fakeErrors), GooseController.shared.allowsProactive else {
                simulation?.setTask(WanderTask())
                return
            }
            eff?.showFakeError(style: style, customText: text)
            simulation?.setTask(WanderTask())
        }
    }

    func tick(simulation: GooseSimulation) {
        simulation.velocity = .zero2
        if !triggered {
            simulation.setTask(WanderTask())
        }
    }
}
