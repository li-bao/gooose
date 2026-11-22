import Foundation

/// Stateful per-goose personality and emotional state.
/// Lead goose stays in sync with `GooseSettings.shared` trait sliders and
/// writes evolved traits back when `personalityEvolution` is enabled. Companion
/// geese carry slight individual variation and evolve independently.
@MainActor
final class GoosePersonality {
    let numericID: Int
    let isLead: Bool

    // Core traits (0...1)
    private(set) var naughty: Double
    private(set) var aggressive: Double
    private(set) var laziness: Double
    private(set) var curious: Double
    private(set) var affectionate: Double

    // Dynamic internal state
    private(set) var emotion: GooseEmotion = .happy
    /// Energy in 0...100 (inversely tracks fatigue so 100 = rested, 0 = exhausted).
    private(set) var energy: Double = 85.0
    private(set) var fatigue: Double = 0.15
    private(set) var boredom: Double = 0.0
    private(set) var evasiveness: Double = 0.0
    private(set) var approachability: Double = 0.5
    private(set) var interruptionCount: Int = 0
    private(set) var timeSinceLastInteraction: TimeInterval = 0
    private var lastAngryAt: TimeInterval = -999
    private var lastPatAt: TimeInterval = -999
    private var elapsedSincePersist: TimeInterval = 0

    init(numericID: Int = 1, isLead: Bool) {
        self.numericID = numericID
        self.isLead = isLead
        let s = GooseSettings.shared
        if let saved = GooseStatePersistence.shared.state(for: numericID) {
            self.emotion = saved.emotion
            self.energy = min(100, max(0, saved.energy))
            self.fatigue = 1.0 - (self.energy / 100.0)
            self.naughty = saved.naughty
            self.aggressive = saved.aggressive
            self.laziness = saved.laziness
            self.curious = saved.curious
            self.affectionate = saved.affectionate
        } else if isLead {
            naughty = s.naughty
            aggressive = s.aggressive
            laziness = s.laziness
            curious = s.curious
            affectionate = s.affectionate
        } else {
            func jitter(_ base: Double) -> Double {
                min(1, max(0, base + Double.random(in: -0.15...0.15)))
            }
            naughty = jitter(s.naughty)
            aggressive = jitter(s.aggressive)
            laziness = jitter(s.laziness)
            curious = jitter(s.curious)
            affectionate = jitter(s.affectionate)
        }
        updateEmotion(isSleeping: false, isActiveTask: false)
    }

    /// Lead goose pulls live slider edits from settings unless evolution nudged locally.
    func syncFromSettings() {
        guard isLead else { return }
        let s = GooseSettings.shared
        naughty = s.naughty
        aggressive = s.aggressive
        laziness = s.laziness
        curious = s.curious
        affectionate = s.affectionate
    }

    private func pushToSettingsIfLead(previousDominant: String) {
        guard isLead, GooseSettings.shared.personalityEvolution else { return }
        let s = GooseSettings.shared
        s.naughty = naughty
        s.aggressive = aggressive
        s.laziness = laziness
        s.curious = curious
        s.affectionate = affectionate
        let after = dominantTrait
        if previousDominant != after {
            NotificationManager.shared.post(
                category: .personalityChanged,
                title: "Personality Evolved",
                body: "Goose mood shifted to \(after)."
            )
        }
    }

    /// Advances fatigue, energy (0...100), boredom, emotion, and periodic persistence.
    func tick(dt: TimeInterval, isSleeping: Bool, isActiveTask: Bool) {
        guard dt > 0 else { return }
        timeSinceLastInteraction += dt

        if isSleeping {
            // Sleeping recovers energy/fatigue and calms boredom slightly.
            energy = min(100.0, energy + dt * 4.5)
            fatigue = max(0, 1.0 - energy / 100.0)
            boredom = max(0, boredom - dt * 0.008)
        } else {
            let drainPerSec = isActiveTask ? 0.65 : 0.25
            energy = max(0.0, energy - dt * drainPerSec * (0.7 + laziness * 0.6))
            fatigue = min(1, 1.0 - energy / 100.0)
            let boredomGain = timeSinceLastInteraction > 20 ? 0.008 : 0.002
            boredom = min(1, boredom + dt * boredomGain * (0.6 + naughty * 0.8))
        }

        updateEmotion(isSleeping: isSleeping, isActiveTask: isActiveTask)

        elapsedSincePersist += dt
        if elapsedSincePersist >= 15.0 {
            elapsedSincePersist = 0
            persistState()
        }
    }

    func persistState() {
        GooseStatePersistence.shared.saveState(
            numericID: numericID,
            emotion: emotion,
            energy: energy,
            naughty: naughty,
            aggressive: aggressive,
            laziness: laziness,
            curious: curious,
            affectionate: affectionate
        )
    }

    private func updateEmotion(isSleeping: Bool, isActiveTask: Bool) {
        let now = Double(GameTime.time)
        if isSleeping || energy < 25 {
            emotion = .sleepy
        } else if now - lastAngryAt < 14 {
            emotion = .angry
        } else if now - lastPatAt < 12 {
            emotion = .happy
        } else if boredom > 0.58 {
            emotion = .bored
        } else if isActiveTask && (naughty > 0.6 || aggressive > 0.6) {
            emotion = .excited
        } else if naughty >= 0.55 {
            emotion = .mischievous
        } else if curious >= 0.6 {
            emotion = .curious
        } else {
            emotion = .happy
        }
    }

    var speedEmotionMultiplier: Double {
        switch emotion {
        case .sleepy:      return 0.72
        case .bored:       return 0.90
        case .excited, .angry: return 1.15
        case .happy, .mischievous, .curious: return 1.0
        }
    }

    // MARK: - Interaction events (drive Personality Evolution)

    /// Goose was caught / poked or held by the user — becomes more evasive.
    func recordCaught() {
        timeSinceLastInteraction = 0
        boredom = max(0, boredom - 0.1)
        evasiveness = min(1, evasiveness + 0.14)
        approachability = max(0, approachability - 0.08)
        if GooseSettings.shared.personalityEvolution {
            let before = dominantTrait
            aggressive = min(1, aggressive + 0.015)
            affectionate = max(0, affectionate - 0.01)
            pushToSettingsIfLead(previousDominant: before)
        }
    }

    /// User petted / hovered gently — becomes more approachable and affectionate.
    func recordPat() {
        timeSinceLastInteraction = 0
        lastPatAt = Double(GameTime.time)
        boredom = max(0, boredom - 0.12)
        evasiveness = max(0, evasiveness - 0.05)
        approachability = min(1, approachability + 0.10)
        if GooseSettings.shared.personalityEvolution {
            let before = dominantTrait
            affectionate = min(1, affectionate + 0.015)
            aggressive = max(0, aggressive - 0.01)
            pushToSettingsIfLead(previousDominant: before)
        }
    }

    /// User clicked the goose — wants to approach more or chase depending on mood.
    func recordClick() {
        timeSinceLastInteraction = 0
        boredom = max(0, boredom - 0.08)
        approachability = min(1, approachability + 0.06)
        if GooseSettings.shared.personalityEvolution {
            let before = dominantTrait
            curious = min(1, curious + 0.012)
            pushToSettingsIfLead(previousDominant: before)
        }
    }

    /// A goose window was closed or task was interrupted — shifts toward mischief/aggression.
    func recordInterrupted() {
        interruptionCount += 1
        timeSinceLastInteraction = 0
        lastAngryAt = Double(GameTime.time)
        boredom = min(1, boredom + 0.12)
        if GooseSettings.shared.personalityEvolution {
            let before = dominantTrait
            naughty = min(1, naughty + 0.025)
            aggressive = min(1, aggressive + 0.02)
            laziness = max(0, laziness - 0.015)
            pushToSettingsIfLead(previousDominant: before)
        }
    }

    func resetTransientState() {
        energy = 100.0
        fatigue = 0
        boredom = 0
        evasiveness = 0
        approachability = 0.5
        interruptionCount = 0
        timeSinceLastInteraction = 0
        emotion = .happy
    }

    // MARK: - Behavior Decision Multipliers (actually drive scheduling & AI)

    /// Higher naughty + boredom boosts autonomous prank rate; high fatigue / low energy dampens it.
    var prankMultiplier: Double {
        let base = GooseSettings.traitFactor(naughty)
        let boredomBoost = 1.0 + boredom * 0.65
        let fatigueBrake = max(0.35, 1.0 - fatigue * 0.55)
        let emotionFactor: Double = (emotion == .mischievous || emotion == .excited) ? 1.25 : (emotion == .sleepy ? 0.6 : 1.0)
        return base * boredomBoost * fatigueBrake * emotionFactor
    }

    /// Higher laziness + fatigue strongly increases sleep/nap probability.
    var sleepMultiplier: Double {
        GooseSettings.traitFactor(laziness) * (1.0 + fatigue * 1.8)
    }

    /// Probability of fleeing rather than charging when cursor gets close.
    var fleeChance: Double {
        let raw = evasiveness * 0.65 + (1.0 - aggressive) * 0.25 - approachability * 0.15
        return min(0.9, max(0.05, raw))
    }

    /// Tendency to linger near the cursor when affectionate/curious.
    var approachBias: Double {
        min(1, max(0, (affectionate * 0.5 + approachability * 0.35 + curious * 0.15)))
    }

    var curiosityMultiplier: Double {
        GooseSettings.traitFactor(curious) * (1.0 + boredom * 0.25)
    }

    var aggressionMultiplier: Double {
        GooseSettings.traitFactor(aggressive) * (1.0 + min(0.5, Double(interruptionCount) * 0.05))
    }

    /// Dominant trait label for UI & AI prompts.
    var dominantTrait: String {
        let pairs: [(String, Double)] = [
            ("Naughty", naughty),
            ("Aggressive", aggressive),
            ("Lazy", laziness),
            ("Curious", curious),
            ("Affectionate", affectionate),
        ]
        return pairs.max(by: { $0.1 < $1.1 })?.0 ?? "Naughty"
    }

    var summaryText: String {
        "\(emotion.title) · \(Int(energy.rounded()))% energy"
    }

    var promptContext: String {
        String(
            format: "traits(naughty=%.2f, aggressive=%.2f, lazy=%.2f, curious=%.2f, affectionate=%.2f) state(fatigue=%.2f, boredom=%.2f, evasiveness=%.2f)",
            naughty, aggressive, laziness, curious, affectionate, fatigue, boredom, evasiveness
        )
    }
}
