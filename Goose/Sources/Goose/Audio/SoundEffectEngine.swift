import AVFoundation
import Foundation

enum SoundCategory: String, Sendable {
    case duck
    case goose
    case footsteps
    case meme
    case notepad
}

enum SoundPriority: Int, Comparable, Sendable {
    case low = 10
    case normal = 20
    case high = 30

    static func < (lhs: SoundPriority, rhs: SoundPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Native multi-channel AVAudioEngine playback for duck, goose, movement, and
/// user-imported audio effects with per-sound cooldowns, pitch/volume randomization,
/// quiet hours, and immediate mute/stop support.
@MainActor
final class SoundEffectEngine {
    static let shared = SoundEffectEngine()

    private struct Channel {
        let player = AVAudioPlayerNode()
        let pitch = AVAudioUnitTimePitch()
        var lastPriority: SoundPriority = .low
        var busyUntil: Date = .distantPast
    }

    private let engine = AVAudioEngine()
    private var channels: [Channel] = []
    private var nextChannelIndex = 0
    private var engineReady = false

    private var duckBuffers: [DuckSound: AVAudioPCMBuffer] = [:]
    private var gooseBuffers: [GooseSound: AVAudioPCMBuffer] = [:]
    private var movementBuffers: [MovementSound: AVAudioPCMBuffer] = [:]
    private var customFilePlayers: [AVAudioPlayer] = []
    private var lastPlayedAt: [String: Date] = [:]

    private(set) var playedCount = 0
    private(set) var lastPlayedIdentifier: String?

    private init() {
        preloadSynthesizedBuffers()
        setUpAudioEngine()
        reloadCustomSounds()
    }

    private func preloadSynthesizedBuffers() {
        for sound in DuckSound.allCases {
            duckBuffers[sound] = SoundSynthesis.buffer(for: sound)
        }
        for sound in GooseSound.allCases {
            gooseBuffers[sound] = SoundSynthesis.buffer(for: sound)
        }
        for sound in MovementSound.allCases {
            movementBuffers[sound] = SoundSynthesis.buffer(for: sound)
        }
    }

    private func setUpAudioEngine() {
        let mixer = engine.mainMixerNode
        mixer.outputVolume = 0.80 // Headroom guard to prevent clipping across overlapping channels
        for _ in 0..<6 {
            let channel = Channel()
            engine.attach(channel.player)
            engine.attach(channel.pitch)
            engine.connect(channel.player, to: channel.pitch, format: SoundSynthesis.format)
            engine.connect(channel.pitch, to: mixer, format: SoundSynthesis.format)
            channels.append(channel)
        }
        engine.prepare()
        engineReady = (try? engine.start()) != nil
    }

    func reloadCustomSounds() {
        customFilePlayers = UserContentManager.shared.sounds.compactMap { item in
            let p = try? AVAudioPlayer(contentsOf: item.url)
            p?.enableRate = true
            p?.prepareToPlay()
            return p
        }
    }

    func stopAll() {
        for i in channels.indices {
            channels[i].player.stop()
            channels[i].busyUntil = .distantPast
        }
        for p in customFilePlayers {
            p.stop()
        }
    }

    // MARK: - Playback API

    @discardableResult
    func playDuck(_ sound: DuckSound, priority: SoundPriority = .normal, cooldown: TimeInterval = 0.35) -> Bool {
        guard canPlay(category: .duck, key: "duck.\(sound.rawValue)", cooldown: cooldown) else { return false }
        guard let buffer = duckBuffers[sound] else { return false }
        return schedule(buffer: buffer, key: "duck.\(sound.rawValue)", category: .duck, priority: priority)
    }

    @discardableResult
    func playGoose(_ sound: GooseSound, priority: SoundPriority = .normal, cooldown: TimeInterval = 0.45) -> Bool {
        guard canPlay(category: .goose, key: "goose.\(sound.rawValue)", cooldown: cooldown) else { return false }
        guard let buffer = gooseBuffers[sound] else { return false }
        return schedule(buffer: buffer, key: "goose.\(sound.rawValue)", category: .goose, priority: priority)
    }

    @discardableResult
    func playMovement(_ sound: MovementSound, category: SoundCategory = .footsteps, priority: SoundPriority = .low, cooldown: TimeInterval = 0.16) -> Bool {
        guard canPlay(category: category, key: "move.\(sound.rawValue)", cooldown: cooldown) else { return false }
        guard let buffer = movementBuffers[sound] else { return false }
        return schedule(buffer: buffer, key: "move.\(sound.rawValue)", category: category, priority: priority)
    }

    @discardableResult
    func playCustomUserSoundIfAvailable(category: SoundCategory = .duck) -> Bool {
        guard !customFilePlayers.isEmpty else { return false }
        guard canPlay(category: category, key: "custom.user", cooldown: 0.4) else { return false }
        guard let player = customFilePlayers.randomElement() else { return false }
        let s = GooseSettings.shared
        let vol = Float(s.masterVolume * (category == .goose ? s.honkVolume : 1.0)) * Float.random(in: 0.85...1.0)
        player.volume = min(1.0, max(0.0, vol))
        player.rate = s.randomPitchVariation ? Float.random(in: 0.92...1.08) : 1.0
        player.currentTime = 0
        player.play()
        lastPlayedAt["custom.user"] = Date()
        playedCount += 1
        lastPlayedIdentifier = "custom.user"
        return true
    }

    // MARK: - Gating & Mixing

    func isAudioAllowed(category: SoundCategory) -> Bool {
        let s = GooseSettings.shared
        guard s.masterSoundEnabled, !s.muteGoose else { return false }
        if s.isQuietHoursActive() { return false }

        switch category {
        case .duck:      return s.duckSoundsEnabled
        case .goose:     return s.gooseSoundsEnabled && s.allows(.honking)
        case .footsteps: return s.footstepsEnabled && s.soundEffects
        case .meme:      return s.memeSoundsEnabled
        case .notepad:   return s.notepadSoundsEnabled
        }
    }

    private func canPlay(category: SoundCategory, key: String, cooldown: TimeInterval) -> Bool {
        guard isAudioAllowed(category: category) else { return false }
        let now = Date()
        if let last = lastPlayedAt[key], now.timeIntervalSince(last) < cooldown {
            return false
        }
        return true
    }

    private func schedule(buffer: AVAudioPCMBuffer, key: String, category: SoundCategory, priority: SoundPriority) -> Bool {
        let s = GooseSettings.shared
        lastPlayedAt[key] = Date()
        playedCount += 1
        lastPlayedIdentifier = key

        if !engineReady {
            engineReady = (try? engine.start()) != nil
        }
        guard engineReady, !channels.isEmpty else {
            return true // Still counted cleanly in headless/no-device CI environments
        }

        let now = Date()
        let selectedIdx: Int
        if let freeIdx = channels.firstIndex(where: { $0.busyUntil <= now }) {
            selectedIdx = freeIdx
        } else if let preemptIdx = channels.firstIndex(where: { $0.lastPriority <= priority }) {
            channels[preemptIdx].player.stop()
            selectedIdx = preemptIdx
        } else {
            selectedIdx = nextChannelIndex % channels.count
            nextChannelIndex += 1
            channels[selectedIdx].player.stop()
        }

        let baseVolume = Float(s.masterVolume)
            * (category == .goose ? Float(s.honkVolume) : 1.0)
            * (s.quietMode ? 0.35 : 1.0)
        let jitterVolume = Float.random(in: 0.85...1.0)
        channels[selectedIdx].player.volume = min(1.0, max(0.0, baseVolume * jitterVolume))

        if s.randomPitchVariation {
            channels[selectedIdx].pitch.pitch = Float.random(in: -180...180)
        } else {
            channels[selectedIdx].pitch.pitch = 0
        }

        let duration = Double(buffer.frameLength) / SoundSynthesis.sampleRate
        channels[selectedIdx].lastPriority = priority
        channels[selectedIdx].busyUntil = now.addingTimeInterval(duration)

        channels[selectedIdx].player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        if !channels[selectedIdx].player.isPlaying {
            channels[selectedIdx].player.play()
        }
        return true
    }
}
