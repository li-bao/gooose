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

    deinit {
        baseTask?.cancel()
        watchTask?.cancel()
    }

    func start() {
        stop()
        baseTask = Task { [weak self] in
            while !Task.isCancelled {
                let s = GooseSettings.shared
                let freq = max(0.1, s.ambientSoundFrequency * s.soundFrequency * max(0.25, s.randomHonkFrequency.intervalMultiplier))
                let seconds = Double.random(in: Tuning.honkBaseRange) / freq
                try? await Task.sleep(for: .seconds(seconds))
                if Task.isCancelled { return }
                guard let self else { return }
                guard s.randomHonking,
                      s.randomHonkFrequency != .off,
                      s.masterSoundEnabled,
                      !s.muteGoose,
                      !s.isQuietHoursActive(),
                      FullscreenMonitor.shared.activityMultiplier > 0,
                      GooseController.shared.allowsProactive else { continue }

                if let sim = self.simulation {
                    if sim.currentTask is NapTask || sim.currentTask is DeepSleepTask {
                        // Sleeping geese must not emit random honks.
                        continue
                    }
                    if Double.random(in: 0..<1) < s.randomHonkFrequency.triggerProbability {
                        sim.onHonk?()
                    }
                }
            }
        }
        watchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                if Task.isCancelled { return }
                guard let self else { return }
                self.checkAppChange()
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
              s.randomHonkFrequency != .off,
              s.masterSoundEnabled,
              !s.muteGoose,
              !s.isQuietHoursActive(),
              FullscreenMonitor.shared.activityMultiplier > 0,
              GooseController.shared.allowsProactive else { return }
        guard let current, current != lastSeenApp, lastSeenApp != nil else { return }
        let now = Date()
        guard now.timeIntervalSince(lastBonusHonk) >= Tuning.honkAppChangeDebounce else { return }
        lastBonusHonk = now
        if let sim = simulation,
           !(sim.currentTask is NapTask || sim.currentTask is DeepSleepTask),
           Double.random(in: 0..<1) < (s.randomHonkFrequency.triggerProbability * 0.5) {
            sim.onHonk?()
        }
    }
}
