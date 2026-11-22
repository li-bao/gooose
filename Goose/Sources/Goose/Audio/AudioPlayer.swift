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

    /// Plays an event-tailored sound effect matching the goose/duck's mood.
    func playEvent(_ event: HonkEvent) {
        let s = GooseSettings.shared
        guard s.masterSoundEnabled, !s.muteGoose else { return }

        switch event {
        case .pat:
            if !pats.isEmpty && s.soundEffects {
                playPat()
            } else {
                _ = SoundEffectEngine.shared.playDuck(.happyQuack, priority: .normal)
            }
        case .random:
            if s.duckSoundsEnabled && (!s.gooseSoundsEnabled || Bool.random()) {
                let duckPicks: [DuckSound] = [.shortQuack, .longQuack, .happyQuack, .quietMutter, .repeatedQuacking]
                _ = SoundEffectEngine.shared.playDuck(duckPicks.randomElement() ?? .shortQuack, priority: .normal)
            } else {
                playHonk(volume: 0.75, rate: Float.random(in: 0.95...1.05))
            }
        case .appSwitch:
            if s.duckSoundsEnabled && Bool.random() {
                _ = SoundEffectEngine.shared.playDuck(.surprisedQuack, priority: .normal)
            } else {
                playHonk(volume: 0.65, rate: 1.08)
            }
        case .theft:
            if !SoundEffectEngine.shared.playGoose(.excitedHonk, priority: .high) {
                _ = SoundEffectEngine.shared.playDuck(.angryQuack, priority: .high)
            }
        case .rage, .sleepWake:
            if !SoundEffectEngine.shared.playGoose(.aggressiveHonk, priority: .high) {
                _ = SoundEffectEngine.shared.playDuck(.angryQuack, priority: .high)
            }
        case .peek:
            _ = SoundEffectEngine.shared.playDuck(.quietMutter, priority: .low)
        case .prank:
            if Bool.random() {
                _ = SoundEffectEngine.shared.playGoose(.warningHonk, priority: .normal)
            } else {
                _ = SoundEffectEngine.shared.playDuck(.shortQuack, priority: .normal)
            }
        }
    }

    func playHonk(volume: Float = 0.8, rate: Float = 1.0) {
        let s = GooseSettings.shared
        guard s.masterSoundEnabled, !s.muteGoose, s.gooseSoundsEnabled, s.allows(.honking) else { return }
        if !honks.isEmpty {
            let level = Float(s.masterVolume * s.honkVolume) * (volume / 0.8)
            playRandom(from: honks, volume: min(1, level), rate: rate)
        } else if !SoundEffectEngine.shared.playCustomUserSoundIfAvailable(category: .goose) {
            _ = SoundEffectEngine.shared.playGoose(.classicHonk, priority: .normal)
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
