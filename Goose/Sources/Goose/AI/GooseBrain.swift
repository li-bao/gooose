import Foundation

/// Hybrid brain. Roulette over actions for everything except `.note`, which
/// tries Foundation Models with a deterministic fallback.
///
/// Honks are NOT in this distribution — `HonkTicker` owns honk cadence.
@MainActor
final class GooseBrain {
    enum Status: Sendable {
        case ready
        case unavailable(String)
    }

    private let personality: Personality
    private let llm: LLMProvider
    private var recentNoteTitles: [String] = []
    private static let recentNoteCap = 5
    private static let recentBrowseCap = 5

    init(personality: Personality = .default, llm: LLMProvider = FoundationModelClient()) {
        self.personality = personality
        self.llm = llm
    }

    /// Brain is always ready — the FM-unavailability case is handled by falling
    /// back to deterministic pools. Read `fmClient.status` for FM diagnostics.
    var status: Status { .ready }

    /// Returns a decision, or nil only if `recentActions` filtering rejected
    /// every reroll (extremely unlikely — we cap retries at 3).
    func decide(
        snapshot: ContextSnapshot,
        recentActions: [String],
        personality: GoosePersonality? = nil
    ) async -> GooseDecision? {
        for _ in 0..<3 {
            if let candidate = await rollOnce(snapshot: snapshot, goosePersonality: personality) {
                let key = summary(of: candidate)
                if recentActions.last == key || recentActions.last == candidate.action.rawValue { continue }
                return candidate
            }
        }
        return await rollOnce(snapshot: snapshot, goosePersonality: personality)
    }

    private func rollOnce(snapshot: ContextSnapshot, goosePersonality: GoosePersonality?) async -> GooseDecision? {
        let bucket = Personality.bucket(for: snapshot.frontmostAppName)
        let tone = Personality.tone(forTimeOnApp: snapshot.elapsedOnApp, idle: snapshot.idleSeconds)
        let settings = GooseSettings.shared

        // Weighted roulette driven by settings + ChaosLevel + live GoosePersonality state.
        let prank = settings.prankFrequency * (goosePersonality?.prankMultiplier ?? GooseSettings.traitFactor(settings.naughty))
        let curious = goosePersonality?.curiosityMultiplier ?? GooseSettings.traitFactor(settings.curious)
        let lazy = goosePersonality?.sleepMultiplier ?? GooseSettings.traitFactor(settings.laziness)
        let aggr = goosePersonality?.aggressionMultiplier ?? GooseSettings.traitFactor(settings.aggressive)

        let windows = settings.allows(.windowPranks)
        let browse = windows && settings.allowWebBrowsing
        let hasAX = AccessibilityProbe.hasAccessibilityPermission

        var weights: [(GooseDecisionType, Double)] = [
            (.wander, settings.wanderingEnabled ? 28 : 0),
            (.note, (settings.allows(.stickyNotes) && settings.notepadDeliveriesEnabled) ? 24 * prank : 0),
            (.meme, (settings.memesEnabled && !UserContentManager.shared.memes.isEmpty && !settings.allPranksDisabled) ? 16 * prank * curious : 0),
            (.nap, settings.allows(.sleepMode) ? 6 * lazy : 0),
            (.deepSleep, settings.allows(.sleepMode) ? 9 * lazy : 0),
            (.photo, windows ? 7 * prank * curious : 0),
            (.browse, browse ? 7 * prank * curious : 0),
            (.fakeError, settings.allows(.fakeErrors) ? 6 * prank : 0),
            (.desktopMess, settings.allows(.desktopMess) ? 6 * prank : 0),
            (.gooseTheft, settings.allows(.gooseTheft) ? 5 * prank * aggr : 0),
            (.windowPeek, settings.allows(.windowPeek) ? 7 * curious : 0),
            (.windowPrank, (windows && hasAX) ? 6 * prank * aggr : 0),
            (.mouseChase, settings.allows(.mouseChase) ? 7 * ((goosePersonality?.approachBias ?? 0.5) + 0.5) : 0),
            (.mouseTheft, settings.effectiveMouseTheft ? 6 * prank * aggr * settings.mouseTheftProbability : 0),
        ]
        weights.removeAll { $0.1 <= 0 }
        let total = weights.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return GooseDecision(action: .wander) }

        var roll = Double.random(in: 0..<total)
        var chosen: GooseDecisionType = .wander
        for (type, w) in weights {
            if roll < w { chosen = type; break }
            roll -= w
        }

        switch chosen {
        case .note: return await pickNote(bucket: bucket, tone: tone, snapshot: snapshot, goosePersonality: goosePersonality)
        case .meme: return GooseDecision(action: .meme)
        case .nap: return GooseDecision(action: .nap)
        case .deepSleep: return GooseDecision(action: .deepSleep)
        case .photo: return GooseDecision(action: .photo)
        case .browse: return pickBrowse(bucket: bucket)
        case .fakeError: return GooseDecision(action: .fakeError)
        case .desktopMess: return GooseDecision(action: .desktopMess)
        case .gooseTheft: return GooseDecision(action: .gooseTheft)
        case .windowPeek: return GooseDecision(action: .windowPeek)
        case .windowPrank: return GooseDecision(action: .windowPrank)
        case .mouseChase: return GooseDecision(action: .mouseChase)
        case .mouseTheft: return GooseDecision(action: .mouseTheft)
        case .wander, .chill: return GooseDecision(action: .wander)
        }
    }

    private func pickNote(
        bucket: Personality.AppBucket,
        tone: Personality.Tone,
        snapshot: ContextSnapshot,
        goosePersonality: GoosePersonality? = nil
    ) async -> GooseDecision {
        let generated: GeneratedNote?
        if let aware = llm as? SettingsAwareLLM {
            generated = await aware.generateNote(systemPrompt: personality.systemPrompt, snapshot: snapshot, personality: goosePersonality)
        } else {
            generated = await llm.generateNote(systemPrompt: personality.systemPrompt, snapshot: snapshot)
        }
        if let generated {
            rememberNote(title: generated.title)
            return GooseDecision(action: .note, noteTitle: generated.title, noteBody: generated.body)
        }
        let pool = personality.notePool(tone: tone, bucket: bucket)
        // Anti-repetition: prefer entries not in the recent ring buffer.
        let fresh = pool.filter { !recentNoteTitles.contains($0.title) }
        let candidates = fresh.isEmpty ? pool : fresh
        let pick = candidates.randomElement() ?? ("untitled.txt", "honk")
        rememberNote(title: pick.title)
        return GooseDecision(action: .note, noteTitle: pick.title, noteBody: pick.body)
    }

    private func rememberNote(title: String) {
        recentNoteTitles.append(title)
        if recentNoteTitles.count > Self.recentNoteCap {
            recentNoteTitles.removeFirst()
        }
    }

    private var recentBrowseURLs: [String] = []

    private func pickBrowse(bucket: Personality.AppBucket) -> GooseDecision {
        let choices = personality.browseChoices(bucket: bucket)
        let fresh = choices.filter { !recentBrowseURLs.contains($0.url.absoluteString) }
        let candidates = fresh.isEmpty ? choices : fresh
        guard let pick = candidates.randomElement() else {
            return GooseDecision(action: .wander)
        }
        recentBrowseURLs.append(pick.url.absoluteString)
        if recentBrowseURLs.count > Self.recentBrowseCap {
            recentBrowseURLs.removeFirst()
        }
        return GooseDecision(action: .browse, browseURL: pick.url)
    }

    private func summary(of decision: GooseDecision) -> String {
        switch decision.action {
        case .wander: return "wander"
        case .nap: return "nap"
        case .deepSleep: return "deepSleep"
        case .note: return "note(\(decision.noteTitle.prefix(30)))"
        case .meme: return "meme"
        case .photo: return "photo"
        case .browse: return "browse(\(decision.browseURL?.absoluteString.prefix(40) ?? ""))"
        case .chill: return "chill(\(decision.spotifyURI?.suffix(20) ?? ""))"
        case .fakeError: return "fakeError"
        case .desktopMess: return "desktopMess"
        case .gooseTheft: return "gooseTheft"
        case .windowPeek: return "windowPeek"
        case .windowPrank: return "windowPrank"
        case .mouseChase: return "mouseChase"
        case .mouseTheft: return "mouseTheft"
        }
    }
}
