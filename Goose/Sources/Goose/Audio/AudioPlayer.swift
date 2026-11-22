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

/// Plays goose sound effects from a user-provided Desktop Goose installation.
/// Audio files are never bundled in this project — they live in the user's
/// legitimately installed `Desktop Goose.app/Contents/Resources/`.
/// Configure the path via the `GOOSE_AUDIO_PATH` environment variable.
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
    }

    /// Plays an event-tailored sound effect with distinct volume and pitch rate.
    func playEvent(_ event: HonkEvent) {
        switch event {
        case .pat:
            playPat()
        case .random:
            playHonk(volume: 0.75, rate: Float.random(in: 0.95...1.05))
        case .appSwitch:
            playHonk(volume: 0.65, rate: 1.08)
        case .theft:
            playHonk(volume: 0.9, rate: 1.15)
        case .rage, .sleepWake:
            playHonk(volume: 1.0, rate: 1.22)
        case .peek:
            playHonk(volume: 0.45, rate: 0.90)
        case .prank:
            playHonk(volume: 0.8, rate: 1.0)
        }
    }

    /// Honk volume is relative: the call-site default (0.8) maps to the
    /// user's Honk Volume slider.
    func playHonk(volume: Float = 0.8, rate: Float = 1.0) {
        let s = GooseSettings.shared
        guard s.allows(.honking), !s.muteGoose else { return }
        let level = Float(s.masterVolume * s.honkVolume) * (volume / 0.8)
        playRandom(from: honks, volume: min(1, level), rate: rate)
    }

    func playPat(volume: Float = 0.4) {
        let s = GooseSettings.shared
        guard s.soundEffects, !s.muteGoose else { return }
        playRandom(from: pats, volume: min(1, volume * Float(s.masterVolume)), rate: 1.0)
    }

    func playBite(volume: Float = 0.07) {
        let s = GooseSettings.shared
        guard s.soundEffects, !s.muteGoose, let player = bite else { return }
        let volume = min(1, volume * Float(s.masterVolume))
        player.volume = volume
        player.currentTime = 0
        player.play()
    }

    private func load() {
        honks = ["Honk1.mp3", "Honk2.mp3", "Honk3.mp3", "Honk4.mp3"].compactMap(makePlayer)
        pats = ["Pat1.wav", "Pat2.wav", "Pat3.wav"].compactMap(makePlayer)
        bite = makePlayer(filename: "BITE.mp3")
        didLoadAnything = !honks.isEmpty || !pats.isEmpty || bite != nil
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
