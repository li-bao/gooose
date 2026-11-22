import AVFoundation
import Foundation

enum DuckSound: String, CaseIterable, Sendable {
    case shortQuack
    case longQuack
    case angryQuack
    case happyQuack
    case surprisedQuack
    case quietMutter
    case repeatedQuacking
}

enum GooseSound: String, CaseIterable, Sendable {
    case classicHonk
    case aggressiveHonk
    case excitedHonk
    case warningHonk
    case sleepingSound
}

enum MovementSound: String, CaseIterable, Sendable {
    case tinyFootstep
    case runningFootstep
    case wingFlap
    case beakPeck
    case draggingObject
    case paperSlide
    case notepadLand
    case memeDrag
}

/// 100% original procedural DSP synthesizer producing duck, goose, and movement
/// sound buffers in memory (no copyrighted external audio samples required).
enum SoundSynthesis {
    static let sampleRate: Double = 44_100
    static let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!

    static func buffer(for duck: DuckSound) -> AVAudioPCMBuffer {
        switch duck {
        case .shortQuack:
            return quackBuffer(duration: 0.14, baseFreq: 380, sweep: -95, nasalGain: 1.0, pulses: 1, amp: 0.50)
        case .longQuack:
            return quackBuffer(duration: 0.34, baseFreq: 355, sweep: -115, nasalGain: 1.15, pulses: 1, amp: 0.48)
        case .angryQuack:
            return quackBuffer(duration: 0.24, baseFreq: 440, sweep: -140, nasalGain: 1.4, pulses: 2, amp: 0.56)
        case .happyQuack:
            return quackBuffer(duration: 0.18, baseFreq: 420, sweep: 65, nasalGain: 0.9, pulses: 2, amp: 0.45)
        case .surprisedQuack:
            return quackBuffer(duration: 0.16, baseFreq: 490, sweep: 130, nasalGain: 1.0, pulses: 1, amp: 0.52)
        case .quietMutter:
            return quackBuffer(duration: 0.22, baseFreq: 260, sweep: -35, nasalGain: 0.65, pulses: 3, amp: 0.24)
        case .repeatedQuacking:
            return quackBuffer(duration: 0.46, baseFreq: 390, sweep: -80, nasalGain: 1.05, pulses: 4, amp: 0.44)
        }
    }

    static func buffer(for goose: GooseSound) -> AVAudioPCMBuffer {
        switch goose {
        case .classicHonk:
            return honkBuffer(duration: 0.26, baseFreq: 245, sweep: -35, grit: 0.35, amp: 0.55)
        case .aggressiveHonk:
            return honkBuffer(duration: 0.34, baseFreq: 295, sweep: -55, grit: 0.60, amp: 0.62)
        case .excitedHonk:
            return honkBuffer(duration: 0.22, baseFreq: 315, sweep: 45, grit: 0.40, amp: 0.54)
        case .warningHonk:
            return honkBuffer(duration: 0.30, baseFreq: 215, sweep: -20, grit: 0.55, amp: 0.58)
        case .sleepingSound:
            return noiseEnvelopeBuffer(duration: 0.45, lowFreq: 130, amp: 0.18, softBreath: true)
        }
    }

    static func buffer(for movement: MovementSound) -> AVAudioPCMBuffer {
        switch movement {
        case .tinyFootstep:
            return tapBuffer(duration: 0.045, freq: 210, noiseMix: 0.55, amp: 0.22)
        case .runningFootstep:
            return tapBuffer(duration: 0.055, freq: 250, noiseMix: 0.65, amp: 0.30)
        case .wingFlap:
            return noiseEnvelopeBuffer(duration: 0.18, lowFreq: 320, amp: 0.32, softBreath: false)
        case .beakPeck:
            return tapBuffer(duration: 0.038, freq: 720, noiseMix: 0.25, amp: 0.35)
        case .draggingObject:
            return slideBuffer(duration: 0.28, centerFreq: 290, amp: 0.26)
        case .paperSlide:
            return slideBuffer(duration: 0.24, centerFreq: 680, amp: 0.25)
        case .notepadLand:
            return tapBuffer(duration: 0.09, freq: 185, noiseMix: 0.45, amp: 0.36)
        case .memeDrag:
            return slideBuffer(duration: 0.26, centerFreq: 420, amp: 0.26)
        }
    }

    // MARK: - DSP Generators

    private static func quackBuffer(
        duration: Double,
        baseFreq: Double,
        sweep: Double,
        nasalGain: Double,
        pulses: Int,
        amp: Float
    ) -> AVAudioPCMBuffer {
        let count = AVAudioFrameCount(duration * sampleRate)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count)!
        buf.frameLength = count
        let ptr = buf.floatChannelData![0]

        var phase: Double = 0
        for i in 0..<Int(count) {
            let t = Double(i) / sampleRate
            let u = t / duration
            let pulsePhase = (u * Double(pulses)).truncatingRemainder(dividingBy: 1.0)
            let env = sin(min(1.0, pulsePhase / 0.15) * .pi * 0.5) * pow(max(0, 1.0 - pulsePhase), 0.7)
            let freq = max(120, baseFreq + sweep * pulsePhase)
            phase += 2.0 * .pi * freq / sampleRate

            // Nasal reed harmonics (strong 2nd/3rd/5th formants)
            let raw = sin(phase)
                + 0.72 * nasalGain * sin(phase * 2.0)
                + 0.45 * nasalGain * sin(phase * 3.0)
                + 0.25 * sin(phase * 5.0)
            let shaped = tanh(raw * 0.85)
            ptr[i] = Float(shaped * env) * amp
        }
        return buf
    }

    private static func honkBuffer(
        duration: Double,
        baseFreq: Double,
        sweep: Double,
        grit: Double,
        amp: Float
    ) -> AVAudioPCMBuffer {
        let count = AVAudioFrameCount(duration * sampleRate)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count)!
        buf.frameLength = count
        let ptr = buf.floatChannelData![0]

        var phase: Double = 0
        for i in 0..<Int(count) {
            let t = Double(i) / sampleRate
            let u = t / duration
            let attack = min(1.0, u / 0.08)
            let release = min(1.0, max(0.0, (1.0 - u) / 0.22))
            let env = attack * release
            let freq = max(110, baseFreq + sweep * u)
            phase += 2.0 * .pi * freq / sampleRate

            let brass = sin(phase)
                + 0.8 * sin(phase * 2.0)
                + 0.55 * sin(phase * 3.0)
                + 0.35 * grit * sin(phase * 4.0)
                + 0.20 * grit * sin(phase * 6.0)
            let saturated = tanh(brass * (1.0 + grit))
            ptr[i] = Float(saturated * env) * amp
        }
        return buf
    }

    private static func tapBuffer(duration: Double, freq: Double, noiseMix: Double, amp: Float) -> AVAudioPCMBuffer {
        let count = AVAudioFrameCount(duration * sampleRate)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count)!
        buf.frameLength = count
        let ptr = buf.floatChannelData![0]

        var seed: UInt32 = 0x1357_2468
        for i in 0..<Int(count) {
            let t = Double(i) / sampleRate
            let u = t / duration
            let env = exp(-u * 6.5)
            seed = seed &* 1664525 &+ 1013904223
            let noise = Double(Int32(bitPattern: seed)) / Double(Int32.max)
            let tone = sin(2.0 * .pi * freq * (1.0 - 0.4 * u) * t)
            let sample = ((1.0 - noiseMix) * tone + noiseMix * noise) * env
            ptr[i] = Float(sample) * amp
        }
        return buf
    }

    private static func slideBuffer(duration: Double, centerFreq: Double, amp: Float) -> AVAudioPCMBuffer {
        let count = AVAudioFrameCount(duration * sampleRate)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count)!
        buf.frameLength = count
        let ptr = buf.floatChannelData![0]

        var seed: UInt32 = 0x2468_1357
        var lp: Double = 0
        let alpha = min(0.6, (2.0 * .pi * centerFreq) / sampleRate)
        for i in 0..<Int(count) {
            let u = Double(i) / Double(count)
            let env = sin(u * .pi)
            seed = seed &* 1664525 &+ 1013904223
            let noise = Double(Int32(bitPattern: seed)) / Double(Int32.max)
            lp += alpha * (noise - lp)
            let rustle = noise - lp * 0.5
            ptr[i] = Float(rustle * env) * amp
        }
        return buf
    }

    private static func noiseEnvelopeBuffer(duration: Double, lowFreq: Double, amp: Float, softBreath: Bool) -> AVAudioPCMBuffer {
        let count = AVAudioFrameCount(duration * sampleRate)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count)!
        buf.frameLength = count
        let ptr = buf.floatChannelData![0]

        var seed: UInt32 = 0x9876_5432
        var lp: Double = 0
        let alpha = min(0.5, (2.0 * .pi * lowFreq) / sampleRate)
        for i in 0..<Int(count) {
            let u = Double(i) / Double(count)
            let env = softBreath ? sin(u * .pi) : pow(sin(u * .pi), 1.4)
            seed = seed &* 1664525 &+ 1013904223
            let noise = Double(Int32(bitPattern: seed)) / Double(Int32.max)
            lp += alpha * (noise - lp)
            ptr[i] = Float(lp * env) * amp
        }
        return buf
    }
}
