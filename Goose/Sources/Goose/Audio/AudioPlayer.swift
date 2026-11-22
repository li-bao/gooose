import AVFoundation
import Foundation

enum HonkEvent: Sendable {
    case random
    case appSwitch
    case theft
    case rage
    case sleepWake
    case peek
    case prank
    case pat
    case delivery
}

/// Event-driven audio facade that plays user-provided audio when available and
/// delegates synthesized duck, goose, and movement sounds to `SoundEffectEngine`.
@MainActor
final class AudioPlayer {
    static let defaultInstallPath = "/Users/kruta/testes/desktop-goose-source/Desktop Goose v0.22/Desktop Goose.app/Contents/Resources"

    private let installRoot: String
    private var honks: [AVAudioPlayer] = []
    private var pats: [AVAudioPlayer] = []
    private var bite: AVAudioPlayer?
    private(set) var didLoadAnything = false

    init(installRoot: String? = nil) {
        let envPath = ProcessInfo.processInfo.environment["GOOSE_AUDIO_PATH"]
        let bundlePath = Bundle.main.resourcePath
        self.installRoot = installRoot ?? envPath ?? bundlePath ?? Self.defaultInstallPath
        load()
        didLoadAnything = true // Synthesized engine is always available locally
    }

    func stopAll() {
        for p in honks { p.stop() }
        for p in pats { p.stop() }
        bite?.stop()
        AudioPackManager.shared.stopAll()
        SoundEffectEngine.shared.stopAll()
    }

    /// Plays an event-tailored sound effect matching the goose/duck's mood.
    func playEvent(_ event: HonkEvent, gooseID: UUID? = nil, isSleeping: Bool = false) {
        let s = GooseSettings.shared
        let ctrl = GooseController.shared
        guard s.masterSoundEnabled, !s.muteGoose, !s.isQuietHoursActive(),
              ctrl.state != .paused, ctrl.state != .hidden else { return }

        if event == .pat {
            guard s.soundEffects else { return }
            if !pats.isEmpty {
                playPat()
            } else {
                _ = SoundEffectEngine.shared.playDuck(.happyQuack, priority: .low, cooldown: 1.2)
            }
            return
        }

        let isMajor: Bool
        switch event {
        case .theft, .rage, .sleepWake, .delivery:
            isMajor = true
        default:
            isMajor = false
        }

        guard SoundEffectEngine.shared.canPlayVocal(gooseID: gooseID, isMajorEvent: isMajor, isSleeping: isSleeping) else {
            return
        }

        var played = false
        switch event {
        case .pat:
            break
        case .random:
            if AudioPackManager.shared.playEventSound(.gooseHonk) {
                played = true
            } else if s.duckSoundsEnabled && (!s.gooseSoundsEnabled || Bool.random()) {
                let duckPicks: [DuckSound] = [.shortQuack, .quietMutter, .happyQuack]
                played = SoundEffectEngine.shared.playDuck(duckPicks.randomElement() ?? .shortQuack, priority: .low, cooldown: 1.0)
            } else {
                played = playHonk(volume: 0.72, rate: Float.random(in: 0.95...1.05))
            }
        case .appSwitch:
            if AudioPackManager.shared.playEventSound(.interaction) {
                played = true
            } else if s.duckSoundsEnabled && Bool.random() {
                played = SoundEffectEngine.shared.playDuck(.surprisedQuack, priority: .normal, cooldown: 1.0)
            } else {
                played = playHonk(volume: 0.65, rate: 1.08)
            }
        case .theft:
            played = AudioPackManager.shared.playEventSound(.gooseAngry)
                || SoundEffectEngine.shared.playGoose(.excitedHonk, priority: .high)
                || SoundEffectEngine.shared.playDuck(.angryQuack, priority: .high)
        case .rage, .sleepWake:
            played = AudioPackManager.shared.playEventSound(.gooseAngry)
                || SoundEffectEngine.shared.playGoose(.aggressiveHonk, priority: .high)
                || SoundEffectEngine.shared.playDuck(.angryQuack, priority: .high)
        case .peek:
            played = AudioPackManager.shared.playEventSound(.gooseLaugh)
                || SoundEffectEngine.shared.playDuck(.quietMutter, priority: .low, cooldown: 1.0)
        case .prank, .delivery:
            if AudioPackManager.shared.playEventSound(.gooseHonk) {
                played = true
            } else if s.gooseSoundsEnabled && s.allows(.honking) && (!s.duckSoundsEnabled || Bool.random()) {
                played = SoundEffectEngine.shared.playGoose(.warningHonk, priority: .normal)
            } else {
                played = SoundEffectEngine.shared.playDuck(.shortQuack, priority: .normal)
            }
        }

        if played {
            SoundEffectEngine.shared.recordVocalPlayed(gooseID: gooseID, duration: 0.35)
        }
    }

    @discardableResult
    func playHonk(volume: Float = 0.8, rate: Float = 1.0) -> Bool {
        let s = GooseSettings.shared
        guard s.masterSoundEnabled, !s.muteGoose, !s.isQuietHoursActive(),
              s.gooseSoundsEnabled, s.allows(.honking) else { return false }
        if !honks.isEmpty {
            let level = Float(s.masterVolume * s.honkVolume) * (volume / 0.8)
            playRandom(from: honks, volume: min(1, level), rate: rate)
            return true
        } else if SoundEffectEngine.shared.playCustomUserSoundIfAvailable(category: .goose) {
            return true
        } else {
            return SoundEffectEngine.shared.playGoose(.classicHonk, priority: .normal)
        }
    }

    func playPat(volume: Float = 0.4) {
        let s = GooseSettings.shared
        guard s.masterSoundEnabled, s.soundEffects, !s.muteGoose else { return }
        if !pats.isEmpty {
            playRandom(from: pats, volume: min(1, volume * Float(s.masterVolume)), rate: 1.0)
        } else {
            _ = SoundEffectEngine.shared.playDuck(.happyQuack, priority: .low)
        }
    }

    func playBite(volume: Float = 0.07) {
        let s = GooseSettings.shared
        guard s.masterSoundEnabled, s.soundEffects, !s.muteGoose else { return }
        if let player = bite {
            player.volume = min(1, volume * Float(s.masterVolume))
            player.currentTime = 0
            player.play()
        } else {
            _ = SoundEffectEngine.shared.playMovement(.beakPeck, category: .footsteps, priority: .low)
        }
    }

    private func load() {
        honks = ["Honk1.mp3", "Honk2.mp3", "Honk3.mp3", "Honk4.mp3"].compactMap(makePlayer)
        pats = ["Pat1.wav", "Pat2.wav", "Pat3.wav"].compactMap(makePlayer)
        bite = makePlayer(filename: "BITE.mp3")
    }

    private func makePlayer(filename: String) -> AVAudioPlayer? {
        let url = URL(fileURLWithPath: installRoot).appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: url.path) {
            let player = try? AVAudioPlayer(contentsOf: url)
            player?.enableRate = true
            player?.prepareToPlay()
            return player
        }
        let nsFilename = filename as NSString
        let name = nsFilename.deletingPathExtension
        let ext = nsFilename.pathExtension
        if let bundleUrl = Bundle.main.url(forResource: name, withExtension: ext) {
            let player = try? AVAudioPlayer(contentsOf: bundleUrl)
            player?.enableRate = true
            player?.prepareToPlay()
            return player
        }
        if let moduleUrl = Bundle.module.url(forResource: name, withExtension: ext) {
            let player = try? AVAudioPlayer(contentsOf: moduleUrl)
            player?.enableRate = true
            player?.prepareToPlay()
            return player
        }
        return nil
    }

    private func playRandom(from pool: [AVAudioPlayer], volume: Float, rate: Float = 1.0) {
        guard let player = pool.randomElement() else { return }
        player.volume = volume
        player.rate = rate
        player.currentTime = 0
        player.play()
    }
}
