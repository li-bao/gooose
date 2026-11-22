import Foundation

/// Independent ambient sound cadence — triggers both duck quacks and goose honks
/// according to user sound category toggles, quiet mode, and sound frequency.
@MainActor
final class HonkTicker {
    private weak var simulation: GooseSimulation?
    private weak var perception: PerceptionEngine?
    private var baseTask: Task<Void, Never>?
    private var watchTask: Task<Void, Never>?
    private var lastBonusHonk: Date = .distantPast
    private var lastSeenApp: String?

    init(simulation: GooseSimulation, perception: PerceptionEngine) {
        self.simulation = simulation
        self.perception = perception
    }

    func start() {
        stop()
        baseTask = Task { [weak self] in
            while !Task.isCancelled {
                let s = GooseSettings.shared
                let freq = max(0.1, s.ambientSoundFrequency * s.soundFrequency)
                let seconds = Double.random(in: Tuning.honkBaseRange) / freq
                try? await Task.sleep(for: .seconds(seconds))
                if Task.isCancelled { return }
                guard s.randomHonking,
                      s.masterSoundEnabled,
                      !s.muteGoose,
                      !s.isQuietHoursActive(),
                      GooseController.shared.allowsProactive else { continue }

                if let sim = self?.simulation {
                    if sim.currentTask is NapTask || sim.currentTask is DeepSleepTask {
                        _ = SoundEffectEngine.shared.playGoose(.sleepingSound, priority: .low, cooldown: 6.0)
                    } else {
                        sim.onHonk?()
                    }
                }
            }
        }
        watchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                if Task.isCancelled { return }
                self?.checkAppChange()
            }
        }
    }

    func stop() {
        baseTask?.cancel()
        watchTask?.cancel()
        baseTask = nil
        watchTask = nil
    }

    private func checkAppChange() {
        let current = perception?.lastFrontmostAppName
        defer { lastSeenApp = current }
        let s = GooseSettings.shared
        guard s.randomHonking,
              s.masterSoundEnabled,
              !s.muteGoose,
              !s.isQuietHoursActive(),
              GooseController.shared.allowsProactive else { return }
        guard let current, current != lastSeenApp, lastSeenApp != nil else { return }
        let now = Date()
        guard now.timeIntervalSince(lastBonusHonk) >= Tuning.honkAppChangeDebounce else { return }
        lastBonusHonk = now
        if let sim = simulation, !(sim.currentTask is NapTask || sim.currentTask is DeepSleepTask) {
            sim.onHonk?()
        }
    }
}
