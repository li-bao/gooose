import Foundation

/// The only LLM entry point the rest of the app talks to. It enforces every
/// AI-related user setting before any provider is touched:
///  - AI master switch and prank-text switch
///  - provider selection
///  - external (OpenAI) opt-in — never used unless the user explicitly opted in
///  - minimum interval between requests
/// Returning `nil` makes callers fall back to the deterministic pools.
@MainActor
final class SettingsAwareLLM: LLMProvider {
    let apple = FoundationModelClient()
    let openAI = OpenAIClient()
    private var lastRequest: Date = .distantPast

    var label: String { "SettingsAwareLLM" }

    var status: LLMStatus {
        activeProviders().isEmpty ? .unavailable("no AI provider active") : .ready
    }

    /// Providers that may be used right now, in priority order.
    func activeProviders() -> [LLMProvider] {
        let s = GooseSettings.shared
        guard s.aiEnabled else { return [] }
        let externalAllowed = s.externalAIOptIn && openAI.status.isReady
        let appleReady: [LLMProvider] = apple.status.isReady ? [apple] : []
        switch s.aiProvider {
        case .auto: return (externalAllowed ? [openAI] : []) + appleReady
        case .appleOnDevice: return appleReady
        case .openAI: return externalAllowed ? [openAI] : []
        }
    }

    /// Human-readable one-line state for the Control Center / AI tab.
    var summary: String {
        let s = GooseSettings.shared
        guard s.aiEnabled else { return "AI disabled (deterministic behavior only)" }
        let active = activeProviders()
        if active.isEmpty { return "No provider available (deterministic fallback)" }
        return active.map { p -> String in
            p === openAI ? "OpenAI \(s.aiModel)" : "Apple on-device"
        }.joined(separator: " → ")
    }

    var appleStatusText: String {
        switch apple.status {
        case .ready: return "Ready"
        case .unavailable(let r): return "Unavailable (\(r))"
        }
    }

    var openAIStatusText: String {
        if !GooseSettings.shared.externalAIOptIn { return "Off (not opted in)" }
        switch openAI.status {
        case .ready: return "Ready"
        case .unavailable: return "No API key"
        }
    }

    func generateNote(systemPrompt: String, snapshot: ContextSnapshot) async -> GeneratedNote? {
        return await generateNote(systemPrompt: systemPrompt, snapshot: snapshot, personality: nil)
    }

    func generateNote(systemPrompt: String, snapshot: ContextSnapshot, personality: GoosePersonality?) async -> GeneratedNote? {
        let s = GooseSettings.shared
        guard s.aiPrankText, throttleAllows() else { return nil }
        let prompt = Self.styled(systemPrompt, personality: personality)
        for provider in activeProviders() {
            if let r = await provider.generateNote(systemPrompt: prompt, snapshot: snapshot) { return r }
        }
        return nil
    }

    func decideChill(systemPrompt: String, snapshot: ContextSnapshot, candidates: [PlaylistCandidate]) async -> ChillDecision? {
        guard throttleAllows() else { return nil }
        let prompt = Self.styled(systemPrompt, personality: nil)
        for provider in activeProviders() {
            if let r = await provider.decideChill(systemPrompt: prompt, snapshot: snapshot, candidates: candidates) { return r }
        }
        return nil
    }

    /// Generates a short taunt after a prank (e.g. cursor theft), using the
    /// active LLM provider when enabled & unthrottled, otherwise returning a
    /// personality-matched deterministic taunt.
    func generateTaunt(personality: GoosePersonality?, event: String) async -> String {
        let s = GooseSettings.shared
        if s.aiEnabled, s.aiPrankText, throttleAllows() {
            let sys = Self.styled(
                "You are a desktop goose. Write a 1-line taunt (under 48 chars, lowercase, no emojis) for event: \(event).",
                personality: personality
            )
            let snap = ContextSnapshot.empty()
            for provider in activeProviders() {
                if let note = await provider.generateNote(systemPrompt: sys, snapshot: snap) {
                    let line = note.body.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !line.isEmpty { return String(line.prefix(56)) }
                }
            }
        }
        return Self.localTaunt(for: personality, event: event)
    }

    /// Generates a short reaction line when the user pats, clicks, or closes a goose window.
    func generateReaction(personality: GoosePersonality?, interaction: GooseStats.Interaction) async -> String {
        let label: String
        switch interaction {
        case .pat: label = "user petted the goose"
        case .poke: label = "user poked the goose"
        case .windowClosed: label = "user closed the goose window"
        }
        let s = GooseSettings.shared
        if s.aiEnabled, s.aiPrankText, throttleAllows() {
            let sys = Self.styled(
                "You are a desktop goose. Write a 1-line reaction (under 48 chars, lowercase) to: \(label).",
                personality: personality
            )
            let snap = ContextSnapshot.empty()
            for provider in activeProviders() {
                if let note = await provider.generateNote(systemPrompt: sys, snapshot: snap) {
                    let line = note.body.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !line.isEmpty { return String(line.prefix(56)) }
                }
            }
        }
        return Self.localReaction(for: personality, interaction: interaction)
    }

    /// Generates parody fake-error text, falling back to style-appropriate parody lines.
    func generateFakeErrorMessage(personality: GoosePersonality?, style: FakeErrorWindow.Style) async -> String {
        let custom = GooseSettings.shared.fakeErrorCustomText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty { return custom }

        let s = GooseSettings.shared
        if s.aiEnabled, s.aiPrankText, throttleAllows() {
            let sys = Self.styled(
                "Write a 1-sentence obviously-fake parody alert message for a desktop goose prank (style: \(style.rawValue)). Never ask for passwords or mimic real security warnings.",
                personality: personality
            )
            let snap = ContextSnapshot.empty()
            for provider in activeProviders() {
                if let note = await provider.generateNote(systemPrompt: sys, snapshot: snap) {
                    let line = note.body.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !line.isEmpty { return String(line.prefix(90)) }
                }
            }
        }
        return FakeErrorWindow.Style.sampleMessages[style]?.randomElement() ?? "Honk."
    }

    static func localTaunt(for personality: GoosePersonality?, event: String) -> String {
        let trait = personality?.dominantTrait ?? "Naughty"
        let pool: [String]
        switch trait {
        case "Aggressive":
            pool = ["mine now. honk.", "touch it again i dare you", "cursor confiscated.", "yield to the beak"]
        case "Lazy":
            pool = ["that took effort. nap time.", "barely even tried. honk.", "ok returning it. tired."]
        case "Curious":
            pool = ["ooh shiny arrow", "what does this button do", "inspecting your pointer...", "honk?"]
        case "Affectionate":
            pool = ["just wanted attention. honk", "boop. gave it back", "hey look at me instead"]
        default: // Naughty
            pool = ["yoink. honk.", "too slow, human.", "rent is due in bread", "nice mouse. be a shame if...", "honk!!"]
        }
        return pool.randomElement() ?? "honk."
    }

    static func localReaction(for personality: GoosePersonality?, interaction: GooseStats.Interaction) -> String {
        switch interaction {
        case .pat:
            return (personality?.affectionate ?? 0.5) >= 0.5
                ? ["soft honk ♥", "acceptable pets", "more bread next time"].randomElement()!
                : ["hiss... fine.", "do not touch the feathers"].randomElement()!
        case .poke:
            return ["hey!!", "excuse me?! honk.", "you asked for this"].randomElement()!
        case .windowClosed:
            return ["how dare you", "that was art.", "you just made an enemy"].randomElement()!
        }
    }

    private func throttleAllows() -> Bool {
        guard !activeProviders().isEmpty else { return false }
        let interval = GooseSettings.shared.aiRequestInterval
        guard Date().timeIntervalSince(lastRequest) >= interval else { return false }
        lastRequest = Date()
        return true
    }

    private static func styled(_ prompt: String, personality: GoosePersonality?) -> String {
        var parts = [prompt]
        let suffix = GooseSettings.shared.aiPersonality.promptSuffix
        if !suffix.isEmpty { parts.append(suffix) }
        if let personality {
            parts.append("Current goose state: \(personality.dominantTrait) mood (\(personality.promptContext)).")
        }
        return parts.joined(separator: " ")
    }
}
