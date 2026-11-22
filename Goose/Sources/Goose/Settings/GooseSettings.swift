import Combine
import Foundation
import ServiceManagement

// MARK: - Enums

enum ChaosLevel: String, CaseIterable, Identifiable, Sendable {
    case low, normal, high, extreme
    var id: String { rawValue }

    /// Slider values applied when the user picks a level.
    var preset: (theft: Double, prank: Double, chase: Double, cooldown: Double) {
        switch self {
        case .low:     return (0.4, 0.5, 5, 60)
        case .normal:  return (1.0, 1.0, 8, 20)
        case .high:    return (1.0, 1.8, 12, 10)
        case .extreme: return (1.0, 3.0, 20, 0)
        }
    }
}

enum AIProviderChoice: String, CaseIterable, Identifiable, Sendable {
    case auto, appleOnDevice, openAI
    var id: String { rawValue }
}

enum AIPersonalityStyle: String, CaseIterable, Identifiable, Sendable {
    case sarcastic, friendly, chaotic, deadpan
    var id: String { rawValue }

    /// Appended to the system prompt when generating text.
    var promptSuffix: String {
        switch self {
        case .sarcastic: return ""
        case .friendly: return "Tone override: be warm and playfully teasing instead of cynical."
        case .chaotic: return "Tone override: be unhinged, erratic and absurd, but still short."
        case .deadpan: return "Tone override: be flat, deadpan and understated."
        }
    }
}

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system, english, traditionalChinese
    var id: String { rawValue }
}

enum RandomHonkFrequency: String, CaseIterable, Identifiable, Codable, Sendable {
    case off, low, medium, high
    var id: String { rawValue }

    var intervalMultiplier: Double {
        switch self {
        case .off:    return 0
        case .low:    return 0.5
        case .medium: return 1.0
        case .high:   return 1.8
        }
    }

    var triggerProbability: Double {
        switch self {
        case .off:    return 0
        case .low:    return 0.35
        case .medium: return 0.65
        case .high:   return 0.90
        }
    }
}

enum HotkeyAction: String, CaseIterable, Identifiable, Sendable {
    case pauseResume
    case hideAll
    case showAll
    case spawnGoose
    case emergencyStop
    case openControlCenter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pauseResume:       return "Pause / Resume"
        case .hideAll:           return "Hide All Geese"
        case .showAll:           return "Show All Geese"
        case .spawnGoose:        return "Spawn Goose"
        case .emergencyStop:     return "Emergency Stop"
        case .openControlCenter: return "Open Control Center"
        }
    }

    var defaultBinding: HotkeyBinding {
        // Default modifiers: ⌃⌥⌘ (cmdKey 256 + optionKey 2048 + controlKey 4096 = 6400)
        let mods: UInt32 = 6400
        switch self {
        case .pauseResume:       return HotkeyBinding(keyCode: 35, modifiers: mods, display: "⌃⌥⌘P")
        case .hideAll:           return HotkeyBinding(keyCode: 4,  modifiers: mods, display: "⌃⌥⌘H")
        case .showAll:           return HotkeyBinding(keyCode: 1,  modifiers: mods, display: "⌃⌥⌘S")
        case .spawnGoose:        return HotkeyBinding(keyCode: 45, modifiers: mods, display: "⌃⌥⌘N")
        case .emergencyStop:     return HotkeyBinding(keyCode: 14, modifiers: mods, display: "⌃⌥⌘E")
        case .openControlCenter: return HotkeyBinding(keyCode: 8,  modifiers: mods, display: "⌃⌥⌘C")
        }
    }
}

struct HotkeyBinding: Codable, Equatable, Sendable {
    var keyCode: UInt32
    var modifiers: UInt32
    var display: String
}

/// Behaviors implemented in Super Goose 2.0.
enum GooseBehavior: String, CaseIterable, Identifiable, Sendable {
    case mouseTheft, mouseDragging, mouseChase, windowPranks, footprints
    case stickyNotes, fakeErrors, desktopMess, gooseTheft, windowPeek
    case honking, sleepMode, angryMode, spotifyChill
    var id: String { rawValue }

    /// Counts as a "prank" for the Disable-All-Pranks master switch.
    var isPrank: Bool {
        switch self {
        case .mouseTheft, .mouseDragging, .mouseChase, .windowPranks,
             .stickyNotes, .fakeErrors, .desktopMess, .gooseTheft, .windowPeek,
             .angryMode, .spotifyChill:
            return true
        case .footprints, .honking, .sleepMode:
            return false
        }
    }
}

// MARK: - Settings

/// Single source of truth for every user-tunable value. UserDefaults-backed;
/// every `@Published` property writes through immediately, and every consumer
/// reads from `GooseSettings.shared` at the moment it needs the value, so
/// changes take effect live.
@MainActor
final class GooseSettings: ObservableObject {
    static let shared = GooseSettings()

    static let schemaVersion = 6
    private let defaults: UserDefaults
    private let prefix = "settings."

    // General
    @Published var launchAtLogin: Bool { didSet { applyLaunchAtLogin() } }
    @Published var startGooseOnLaunch: Bool { didSet { save("startGooseOnLaunch", startGooseOnLaunch) } }
    @Published var showMenuBarIcon: Bool { didSet { save("showMenuBarIcon", showMenuBarIcon) } }
    @Published var gooseSize: Double { didSet { save("gooseSize", gooseSize) } }
    @Published var language: AppLanguage { didSet { save("language", language.rawValue) } }
    @Published var pauseOnLaunch: Bool { didSet { save("pauseOnLaunch", pauseOnLaunch) } }

    // Goose
    @Published var movementSpeed: Double { didSet { save("movementSpeed", movementSpeed) } }
    @Published var animationSpeed: Double { didSet { save("animationSpeed", animationSpeed) } }
    @Published var activityFrequency: Double { didSet { save("activityFrequency", activityFrequency) } }
    @Published var maxGooseCount: Int { didSet { save("maxGooseCount", maxGooseCount) } }

    // Chaos
    @Published var chaosLevel: ChaosLevel { didSet { save("chaosLevel", chaosLevel.rawValue) } }
    @Published var mouseTheftProbability: Double { didSet { save("mouseTheftProbability", mouseTheftProbability) } }
    @Published var prankFrequency: Double { didSet { save("prankFrequency", prankFrequency) } }
    @Published var mouseChaseDuration: Double { didSet { save("mouseChaseDuration", mouseChaseDuration) } }
    @Published var behaviorCooldown: Double { didSet { save("behaviorCooldown", behaviorCooldown) } }
    @Published var randomBehavior: Bool { didSet { save("randomBehavior", randomBehavior) } }

    // Behaviors
    @Published private(set) var behaviorFlags: [String: Bool]
    @Published var allPranksDisabled: Bool { didSet { save("allPranksDisabled", allPranksDisabled) } }

    // Phase 2 Prank Tunables
    @Published var mouseDragDuration: Double { didSet { save("mouseDragDuration", mouseDragDuration) } }
    @Published var mouseChaseRange: Double { didSet { save("mouseChaseRange", mouseChaseRange) } }
    @Published var footprintMaxCount: Int { didSet { save("footprintMaxCount", footprintMaxCount) } }
    @Published var footprintOpacity: Double { didSet { save("footprintOpacity", footprintOpacity) } }
    @Published var footprintLifetime: Double { didSet { save("footprintLifetime", footprintLifetime) } }
    @Published var stickyNoteLifetime: Double { didSet { save("stickyNoteLifetime", stickyNoteLifetime) } }
    @Published var windowNudgeAmplitude: Double { didSet { save("windowNudgeAmplitude", windowNudgeAmplitude) } }
    @Published var fakeErrorCustomText: String { didSet { save("fakeErrorCustomText", fakeErrorCustomText) } }

    // Sounds
    @Published var masterVolume: Double { didSet { save("masterVolume", masterVolume) } }
    @Published var honkVolume: Double { didSet { save("honkVolume", honkVolume) } }
    @Published var soundEffects: Bool { didSet { save("soundEffects", soundEffects) } }
    @Published var muteGoose: Bool {
        didSet {
            save("muteGoose", muteGoose)
            if muteGoose {
                SoundEffectEngine.shared.stopAll()
                GooseController.shared.scene?.stopAudio()
            }
        }
    }
    @Published var randomHonking: Bool { didSet { save("randomHonking", randomHonking) } }
    @Published var randomHonkFrequency: RandomHonkFrequency { didSet { save("randomHonkFrequency", randomHonkFrequency.rawValue) } }
    @Published var honkCooldown: Double { didSet { save("honkCooldown", honkCooldown) } }
    @Published var soundFrequency: Double { didSet { save("soundFrequency", soundFrequency) } }

    // Personality (0...1)
    @Published var naughty: Double { didSet { save("naughty", naughty) } }
    @Published var aggressive: Double { didSet { save("aggressive", aggressive) } }
    @Published var laziness: Double { didSet { save("lazy", laziness) } }
    @Published var curious: Double { didSet { save("curious", curious) } }
    @Published var affectionate: Double { didSet { save("affectionate", affectionate) } }
    @Published var personalityEvolution: Bool { didSet { save("personalityEvolution", personalityEvolution) } }
    @Published var interactionMemory: Bool { didSet { save("interactionMemory", interactionMemory) } }

    // AI
    @Published var aiEnabled: Bool { didSet { save("aiEnabled", aiEnabled) } }
    @Published var aiProvider: AIProviderChoice { didSet { save("aiProvider", aiProvider.rawValue) } }
    @Published var aiModel: String { didSet { save("aiModel", aiModel) } }
    @Published var aiPersonality: AIPersonalityStyle { didSet { save("aiPersonality", aiPersonality.rawValue) } }
    @Published var aiPrankText: Bool { didSet { save("aiPrankText", aiPrankText) } }
    /// Minimum seconds between two AI requests.
    @Published var aiRequestInterval: Double { didSet { save("aiRequestInterval", aiRequestInterval) } }

    // Privacy
    @Published var screenRecognition: Bool { didSet { save("screenRecognition", screenRecognition) } }
    @Published var externalAIOptIn: Bool { didSet { save("externalAIOptIn", externalAIOptIn) } }
    @Published var sendAppNameToExternalAI: Bool { didSet { save("sendAppNameToExternalAI", sendAppNameToExternalAI) } }
    @Published var allowWebBrowsing: Bool { didSet { save("allowWebBrowsing", allowWebBrowsing) } }

    // Phase 4: macOS Integration (Fullscreen Awareness, Notifications, Global Hotkeys)
    @Published var fullscreenAwareness: Bool { didSet { save("fullscreenAwareness", fullscreenAwareness) } }
    @Published var fullscreenExceptionApps: String { didSet { save("fullscreenExceptionApps", fullscreenExceptionApps) } }

    @Published var notificationsEnabled: Bool { didSet { save("notificationsEnabled", notificationsEnabled) } }
    @Published var notifyPrank: Bool { didSet { save("notifyPrank", notifyPrank) } }
    @Published var notifyNewGoose: Bool { didSet { save("notifyNewGoose", notifyNewGoose) } }
    @Published var notifyAIMessage: Bool { didSet { save("notifyAIMessage", notifyAIMessage) } }
    @Published var notifyPersonalityChange: Bool { didSet { save("notifyPersonalityChange", notifyPersonalityChange) } }
    @Published var notifyGooseSleeping: Bool { didSet { save("notifyGooseSleeping", notifyGooseSleeping) } }

    @Published var hotkeysEnabled: Bool { didSet { save("hotkeysEnabled", hotkeysEnabled); onHotkeysChanged?() } }
    @Published private(set) var hotkeyBindings: [String: HotkeyBinding]
    var onHotkeysChanged: (() -> Void)?

    // Ultimate Desktop Goose (v2.1): Audio, Memes, Notepads, Personality Packs, Screen Observation
    @Published var masterSoundEnabled: Bool {
        didSet {
            save("masterSoundEnabled", masterSoundEnabled)
            if !masterSoundEnabled {
                SoundEffectEngine.shared.stopAll()
                GooseController.shared.scene?.stopAudio()
            }
        }
    }
    @Published var duckSoundsEnabled: Bool { didSet { save("duckSoundsEnabled", duckSoundsEnabled) } }
    @Published var gooseSoundsEnabled: Bool { didSet { save("gooseSoundsEnabled", gooseSoundsEnabled) } }
    @Published var footstepsEnabled: Bool { didSet { save("footstepsEnabled", footstepsEnabled) } }
    @Published var memeSoundsEnabled: Bool { didSet { save("memeSoundsEnabled", memeSoundsEnabled) } }
    @Published var notepadSoundsEnabled: Bool { didSet { save("notepadSoundsEnabled", notepadSoundsEnabled) } }
    @Published var randomPitchVariation: Bool { didSet { save("randomPitchVariation", randomPitchVariation) } }
    @Published var ambientSoundFrequency: Double { didSet { save("ambientSoundFrequency", ambientSoundFrequency) } }

    @Published var memesEnabled: Bool { didSet { save("memesEnabled", memesEnabled) } }
    @Published var maxVisibleMemes: Int { didSet { save("maxVisibleMemes", maxVisibleMemes) } }
    @Published var memeLifetime: Double { didSet { save("memeLifetime", memeLifetime) } }

    @Published var notepadDeliveriesEnabled: Bool { didSet { save("notepadDeliveriesEnabled", notepadDeliveriesEnabled) } }
    @Published var notepadMinInterval: Double { didSet { save("notepadMinInterval", notepadMinInterval) } }
    @Published var notepadMaxInterval: Double { didSet { save("notepadMaxInterval", notepadMaxInterval) } }
    @Published var maxVisibleNotepads: Int { didSet { save("maxVisibleNotepads", maxVisibleNotepads) } }
    @Published var notepadLifetime: Double { didSet { save("notepadLifetime", notepadLifetime) } }
    @Published var preventRepeatedMessages: Bool { didSet { save("preventRepeatedMessages", preventRepeatedMessages) } }
    @Published var deliveryAnimationSpeed: Double { didSet { save("deliveryAnimationSpeed", deliveryAnimationSpeed) } }
    @Published var memoAlwaysOnTop: Bool { didSet { save("memoAlwaysOnTop", memoAlwaysOnTop) } }

    @Published var personalityCategory: GoosePersonalityCategory { didSet { save("personalityCategory", personalityCategory.rawValue) } }
    @Published var disabledPhrasePacks: [String] { didSet { save("disabledPhrasePacks", disabledPhrasePacks) } }

    @Published var screenObservationMode: ScreenObservationMode { didSet { save("screenObservationMode", screenObservationMode.rawValue) } }
    @Published var dontAskScreenPermissionAutomatically: Bool { didSet { save("dontAskScreenPermissionAutomatically", dontAskScreenPermissionAutomatically) } }

    @Published var wanderingEnabled: Bool { didSet { save("wanderingEnabled", wanderingEnabled) } }
    @Published var quietMode: Bool { didSet { save("quietMode", quietMode) } }
    @Published var nighttimeQuietHours: Bool { didSet { save("nighttimeQuietHours", nighttimeQuietHours) } }
    @Published var quietStartHour: Int { didSet { save("quietStartHour", quietStartHour) } }
    @Published var quietEndHour: Int { didSet { save("quietEndHour", quietEndHour) } }

    /// Last error from the Login Item registration, surfaced in the UI.
    @Published private(set) var launchAtLoginError: String?

    // MARK: Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let p = "settings."
        func get<T>(_ key: String, _ fallback: T) -> T { defaults.object(forKey: p + key) as? T ?? fallback }

        Self.migrate(defaults: defaults)

        launchAtLogin = SMAppService.mainApp.status == .enabled
        startGooseOnLaunch = get("startGooseOnLaunch", true)
        showMenuBarIcon = get("showMenuBarIcon", true)
        gooseSize = get("gooseSize", 1.0)
        language = AppLanguage(rawValue: get("language", AppLanguage.system.rawValue)) ?? .system
        pauseOnLaunch = get("pauseOnLaunch", false)

        movementSpeed = get("movementSpeed", 1.0)
        animationSpeed = get("animationSpeed", 1.0)
        activityFrequency = get("activityFrequency", 1.0)
        maxGooseCount = get("maxGooseCount", 1)

        chaosLevel = ChaosLevel(rawValue: get("chaosLevel", ChaosLevel.normal.rawValue)) ?? .normal
        let normal = ChaosLevel.normal.preset
        mouseTheftProbability = get("mouseTheftProbability", normal.theft)
        prankFrequency = get("prankFrequency", normal.prank)
        mouseChaseDuration = get("mouseChaseDuration", normal.chase)
        behaviorCooldown = get("behaviorCooldown", normal.cooldown)
        randomBehavior = get("randomBehavior", true)

        var flags: [String: Bool] = [:]
        for b in GooseBehavior.allCases { flags[b.rawValue] = get("behavior." + b.rawValue, true) }
        behaviorFlags = flags
        allPranksDisabled = get("allPranksDisabled", false)

        mouseDragDuration = get("mouseDragDuration", 6.0)
        mouseChaseRange = get("mouseChaseRange", 220.0)
        footprintMaxCount = get("footprintMaxCount", 64)
        footprintOpacity = get("footprintOpacity", 0.85)
        footprintLifetime = get("footprintLifetime", 8.5)
        stickyNoteLifetime = get("stickyNoteLifetime", 25.0)
        windowNudgeAmplitude = get("windowNudgeAmplitude", 40.0)
        fakeErrorCustomText = get("fakeErrorCustomText", "")

        masterVolume = get("masterVolume", 1.0)
        honkVolume = get("honkVolume", 0.8)
        soundEffects = get("soundEffects", true)
        muteGoose = get("muteGoose", false)
        randomHonking = get("randomHonking", true)
        randomHonkFrequency = RandomHonkFrequency(rawValue: get("randomHonkFrequency", RandomHonkFrequency.low.rawValue)) ?? .low
        honkCooldown = get("honkCooldown", 20.0)
        soundFrequency = get("soundFrequency", 1.0)

        naughty = get("naughty", 0.5)
        aggressive = get("aggressive", 0.5)
        laziness = get("lazy", 0.5)
        curious = get("curious", 0.5)
        affectionate = get("affectionate", 0.5)
        personalityEvolution = get("personalityEvolution", false)
        interactionMemory = get("interactionMemory", true)

        aiEnabled = get("aiEnabled", true)
        aiProvider = AIProviderChoice(rawValue: get("aiProvider", AIProviderChoice.auto.rawValue)) ?? .auto
        aiModel = get("aiModel", "gpt-5-mini")
        aiPersonality = AIPersonalityStyle(rawValue: get("aiPersonality", AIPersonalityStyle.sarcastic.rawValue)) ?? .sarcastic
        aiPrankText = get("aiPrankText", true)
        aiRequestInterval = get("aiRequestInterval", 10)

        screenRecognition = get("screenRecognition", true)
        // External AI is ALWAYS opt-in. Earlier builds used OpenAI whenever a
        // key file existed; that is deliberately not carried over.
        externalAIOptIn = get("externalAIOptIn", false)
        sendAppNameToExternalAI = get("sendAppNameToExternalAI", true)
        allowWebBrowsing = get("allowWebBrowsing", true)

        fullscreenAwareness = get("fullscreenAwareness", true)
        fullscreenExceptionApps = get("fullscreenExceptionApps", "")

        notificationsEnabled = get("notificationsEnabled", false)
        notifyPrank = get("notifyPrank", true)
        notifyNewGoose = get("notifyNewGoose", true)
        notifyAIMessage = get("notifyAIMessage", true)
        notifyPersonalityChange = get("notifyPersonalityChange", true)
        notifyGooseSleeping = get("notifyGooseSleeping", true)

        hotkeysEnabled = get("hotkeysEnabled", true)
        var loadedHotkeys: [String: HotkeyBinding] = [:]
        for action in HotkeyAction.allCases {
            if let data = defaults.data(forKey: p + "hotkey." + action.rawValue),
               let decoded = try? JSONDecoder().decode(HotkeyBinding.self, from: data) {
                loadedHotkeys[action.rawValue] = decoded
            } else {
                loadedHotkeys[action.rawValue] = action.defaultBinding
            }
        }
        hotkeyBindings = loadedHotkeys

        masterSoundEnabled = get("masterSoundEnabled", true)
        duckSoundsEnabled = get("duckSoundsEnabled", true)
        gooseSoundsEnabled = get("gooseSoundsEnabled", true)
        footstepsEnabled = get("footstepsEnabled", true)
        memeSoundsEnabled = get("memeSoundsEnabled", true)
        notepadSoundsEnabled = get("notepadSoundsEnabled", true)
        randomPitchVariation = get("randomPitchVariation", true)
        ambientSoundFrequency = get("ambientSoundFrequency", 1.0)

        memesEnabled = get("memesEnabled", true)
        maxVisibleMemes = get("maxVisibleMemes", 3)
        memeLifetime = get("memeLifetime", 30.0)

        notepadDeliveriesEnabled = get("notepadDeliveriesEnabled", true)
        notepadMinInterval = get("notepadMinInterval", 25.0)
        notepadMaxInterval = get("notepadMaxInterval", 75.0)
        maxVisibleNotepads = get("maxVisibleNotepads", 4)
        notepadLifetime = get("notepadLifetime", 35.0)
        preventRepeatedMessages = get("preventRepeatedMessages", true)
        deliveryAnimationSpeed = get("deliveryAnimationSpeed", 1.0)
        memoAlwaysOnTop = get("memoAlwaysOnTop", true)

        personalityCategory = GoosePersonalityCategory(rawValue: get("personalityCategory", GoosePersonalityCategory.sarcastic.rawValue)) ?? .sarcastic
        disabledPhrasePacks = (defaults.stringArray(forKey: p + "disabledPhrasePacks")) ?? []

        screenObservationMode = ScreenObservationMode(rawValue: get("screenObservationMode", ScreenObservationMode.automaticBackground.rawValue)) ?? .automaticBackground
        dontAskScreenPermissionAutomatically = get("dontAskScreenPermissionAutomatically", false)

        wanderingEnabled = get("wanderingEnabled", true)
        quietMode = get("quietMode", false)
        nighttimeQuietHours = get("nighttimeQuietHours", false)
        quietStartHour = get("quietStartHour", 23)
        quietEndHour = get("quietEndHour", 7)
    }

    func isQuietHoursActive(at date: Date = Date()) -> Bool {
        if AudioPackManager.shared.quietHours.enabled {
            return AudioPackManager.shared.quietHours.isActive(at: date)
        }
        guard nighttimeQuietHours else { return false }
        let hour = Calendar.current.component(.hour, from: date)
        if quietStartHour == quietEndHour { return true }
        if quietStartHour < quietEndHour {
            return hour >= quietStartHour && hour < quietEndHour
        } else {
            return hour >= quietStartHour || hour < quietEndHour
        }
    }

    // MARK: Persistence helpers

    private func save(_ key: String, _ value: Any) {
        defaults.set(value, forKey: prefix + key)
    }

    /// Versioned migration hook. v0 = no settings stored; v1 = Phase 1;
    /// v2 = Phase 2 (prank tunables); v3 = Phase 4 (macOS integration).
    private static func migrate(defaults: UserDefaults) {
        let key = "settings.schemaVersion"
        let stored = defaults.integer(forKey: key)
        if stored < 1 {
            // v0 -> v1: legacy builds had no UserDefaults state.
        }
        if stored < 2 {
            // v1 -> v2: preserve all v1 keys; new keys fall back to defaults.
        }
        if stored < 3 {
            // v2 -> v3: preserve all v2 keys; Phase 4 keys fall back to defaults.
        }
        if stored < 4 {
            // v3 -> v4: preserve all v3 keys; v2.1 audio/meme/notepad/observation keys fall back to defaults.
        }
        if stored < 5 {
            // v4 -> v5: preserve all v4 keys; randomHonkFrequency & honkCooldown fall back to defaults.
        }
        if stored < 6 {
            // v5 -> v6: preserve all v5 keys; memoAlwaysOnTop falls back to true.
        }
        if stored != schemaVersion { defaults.set(schemaVersion, forKey: key) }
    }

    // MARK: Hotkeys

    func binding(for action: HotkeyAction) -> HotkeyBinding {
        hotkeyBindings[action.rawValue] ?? action.defaultBinding
    }

    func setBinding(_ binding: HotkeyBinding, for action: HotkeyAction) {
        hotkeyBindings[action.rawValue] = binding
        if let data = try? JSONEncoder().encode(binding) {
            save("hotkey." + action.rawValue, data)
        }
        onHotkeysChanged?()
    }

    func resetHotkeys() {
        for action in HotkeyAction.allCases {
            setBinding(action.defaultBinding, for: action)
        }
    }

    // MARK: Behaviors

    func isEnabled(_ behavior: GooseBehavior) -> Bool {
        behaviorFlags[behavior.rawValue] ?? true
    }

    func setEnabled(_ behavior: GooseBehavior, _ on: Bool) {
        behaviorFlags[behavior.rawValue] = on
        save("behavior." + behavior.rawValue, on)
    }

    /// Behavior switch AND the global prank master switch.
    func allows(_ behavior: GooseBehavior) -> Bool {
        guard isEnabled(behavior) else { return false }
        if behavior.isPrank && allPranksDisabled { return false }
        return true
    }

    /// Theft needs the goose to reach the cursor, so it requires chase.
    var effectiveMouseTheft: Bool { allows(.mouseTheft) && allows(.mouseChase) }

    // MARK: Chaos

    func applyChaosLevel(_ level: ChaosLevel) {
        chaosLevel = level
        let p = level.preset
        mouseTheftProbability = p.theft
        prankFrequency = p.prank
        mouseChaseDuration = p.chase
        behaviorCooldown = p.cooldown
    }

    var isChaosCustomized: Bool {
        let p = chaosLevel.preset
        return abs(p.theft - mouseTheftProbability) > 0.001
            || abs(p.prank - prankFrequency) > 0.001
            || abs(p.chase - mouseChaseDuration) > 0.001
            || abs(p.cooldown - behaviorCooldown) > 0.001
    }

    // MARK: Personality

    /// Multiplier in 0.5...1.5 for a trait value of 0...1.
    static func traitFactor(_ v: Double) -> Double { 0.5 + min(1, max(0, v)) }

    func nudge(_ keyPath: ReferenceWritableKeyPath<GooseSettings, Double>, by delta: Double) {
        guard personalityEvolution else { return }
        self[keyPath: keyPath] = min(1, max(0, self[keyPath: keyPath] + delta))
    }

    // MARK: Defaults

    func restoreDefaults() {
        let launchState = launchAtLogin
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) && key != prefix + "schemaVersion" {
            defaults.removeObject(forKey: key)
        }
        startGooseOnLaunch = true
        showMenuBarIcon = true
        gooseSize = 1
        language = .system
        pauseOnLaunch = false
        movementSpeed = 1
        animationSpeed = 1
        activityFrequency = 1
        maxGooseCount = 1
        applyChaosLevel(.normal)
        randomBehavior = true
        for b in GooseBehavior.allCases { setEnabled(b, true) }
        allPranksDisabled = false
        mouseDragDuration = 6.0
        mouseChaseRange = 220.0
        footprintMaxCount = 64
        footprintOpacity = 0.85
        footprintLifetime = 8.5
        stickyNoteLifetime = 25.0
        windowNudgeAmplitude = 40.0
        fakeErrorCustomText = ""
        masterVolume = 1
        honkVolume = 0.8
        soundEffects = true
        muteGoose = false
        randomHonking = true
        randomHonkFrequency = .low
        honkCooldown = 20.0
        soundFrequency = 1
        naughty = 0.5; aggressive = 0.5; laziness = 0.5; curious = 0.5; affectionate = 0.5
        personalityEvolution = false
        interactionMemory = true
        aiEnabled = true
        aiProvider = .auto
        aiModel = "gpt-5-mini"
        aiPersonality = .sarcastic
        aiPrankText = true
        aiRequestInterval = 10
        screenRecognition = true
        externalAIOptIn = false
        sendAppNameToExternalAI = true
        allowWebBrowsing = true
        fullscreenAwareness = true
        fullscreenExceptionApps = ""
        notificationsEnabled = false
        notifyPrank = true
        notifyNewGoose = true
        notifyAIMessage = true
        notifyPersonalityChange = true
        notifyGooseSleeping = true
        hotkeysEnabled = true
        resetHotkeys()
        masterSoundEnabled = true
        duckSoundsEnabled = true
        gooseSoundsEnabled = true
        footstepsEnabled = true
        memeSoundsEnabled = true
        notepadSoundsEnabled = true
        randomPitchVariation = true
        ambientSoundFrequency = 1.0
        memesEnabled = true
        maxVisibleMemes = 3
        memeLifetime = 30.0
        notepadDeliveriesEnabled = true
        notepadMinInterval = 25.0
        notepadMaxInterval = 75.0
        maxVisibleNotepads = 4
        notepadLifetime = 35.0
        preventRepeatedMessages = true
        deliveryAnimationSpeed = 1.0
        memoAlwaysOnTop = true
        personalityCategory = .sarcastic
        disabledPhrasePacks = []
        screenObservationMode = .automaticBackground
        dontAskScreenPermissionAutomatically = false
        wanderingEnabled = true
        quietMode = false
        nighttimeQuietHours = false
        quietStartHour = 23
        quietEndHour = 7
        launchAtLogin = launchState   // login item is a system registration; leave as is
    }

    // MARK: Login item

    func refreshLaunchAtLoginStatus() {
        let actual = SMAppService.mainApp.status == .enabled
        if launchAtLogin != actual {
            launchAtLogin = actual
        }
    }

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            let actual = SMAppService.mainApp.status == .enabled
            if actual != launchAtLogin { launchAtLogin = actual }
            launchAtLoginError = error.localizedDescription
        }
    }
}
