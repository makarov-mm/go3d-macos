import AVFoundation

/// Short sounds made up at start: the click of a stone set on the board, the clatter of stones taken dropping into a
/// lid, a softer knock for a stone put back in its bowl, a bell for a pass, a chord at the end. They play on a few
/// voices, so that one does not cut off another.
@MainActor
final class SoundBank {
    enum Effect: CaseIterable {
        case place, capture, returnToBowl, pass, gameOver, click
    }

    var enabled = true

    private static let rate = 44100.0
    private let engine = AVAudioEngine()
    private let format: AVAudioFormat
    private var voices: [AVAudioPlayerNode] = []
    private var nextVoice = 0
    private var buffers: [Effect: AVAudioPCMBuffer] = [:]
    private var available = true

    init() {
        format = AVAudioFormat(standardFormatWithSampleRate: Self.rate, channels: 1)!
        for effect in Effect.allCases {
            let (samples, volume) = Self.synthesize(effect)
            buffers[effect] = makeBuffer(samples, volume: volume)
        }
        for _ in 0..<6 {
            let voice = AVAudioPlayerNode()
            engine.attach(voice)
            engine.connect(voice, to: engine.mainMixerNode, format: format)
            voices.append(voice)
        }
    }

    func play(_ effect: Effect) {
        guard enabled, available, let buffer = buffers[effect] else { return }
        // The engine is started on first use, and again after the output device changed, which stops it.
        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                available = false
                return
            }
        }
        let voice = voices[nextVoice]
        nextVoice = (nextVoice + 1) % voices.count
        voice.stop()
        voice.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        voice.play()
    }

    /// The samples scaled so that the loudest is `volume`.
    private func makeBuffer(_ samples: [Float], volume: Float) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        let peak = max(samples.map(abs).max() ?? 0, 1e-6)
        for (i, sample) in samples.enumerated() {
            channel[i] = min(max(sample / peak * volume, -1), 1)
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        return buffer
    }

    // MARK: Synthesis

    private static func synthesize(_ effect: Effect) -> (samples: [Float], volume: Float) {
        switch effect {
        case .place:
            return (knock(pitch: 1, seed: 1), 0.62)
        case .capture:
            // Stones taken dropping into a lid: a few light knocks close together.
            var clatter = silence(0.3)
            add(&clatter, knock(pitch: 1.7, seed: 4, length: 0.5, brightness: 0.8), at: 0, gain: 1)
            add(&clatter, knock(pitch: 2.05, seed: 5, length: 0.4, brightness: 0.7), at: 0.042, gain: 0.6)
            add(&clatter, knock(pitch: 1.85, seed: 7, length: 0.35, brightness: 0.6), at: 0.075, gain: 0.35)
            return (clatter, 0.36)
        case .returnToBowl:
            return (knock(pitch: 1.45, seed: 6, length: 0.6, brightness: 0.5), 0.26)
        case .pass:
            return (bell(frequency: 659.25, length: 0.8), 0.22)
        case .gameOver:
            var chord = silence(1.8)
            for (i, note) in [523.25, 659.25, 783.99, 1046.5].enumerated() {
                add(&chord, bell(frequency: note, length: 1.5), at: Double(i) * 0.11, gain: 0.8)
            }
            return (chord, 0.35)
        case .click:
            var click = silence(0.03)
            for i in click.indices {
                let t = Double(i) / rate
                click[i] = Float(sin(2 * .pi * 2600 * t) * exp(-t / 0.004))
            }
            return (click, 0.18)
        }
    }

    private static func silence(_ seconds: Double) -> [Float] { [Float](repeating: 0, count: Int(seconds * rate)) }

    private static func add(_ target: inout [Float], _ source: [Float], at time: Double, gain: Float) {
        let offset = Int(time * rate)
        if target.count < offset + source.count {
            target += [Float](repeating: 0, count: offset + source.count - target.count)
        }
        for (i, sample) in source.enumerated() {
            target[offset + i] += sample * gain
        }
    }

    /// A stone on wood: a sharp burst of filtered noise and quickly damped resonances of the board; `length`
    /// shortens or lengthens how it rings, `brightness` how much of the click there is.
    private static func knock(pitch: Double, seed: UInt32, length: Double = 1, brightness: Double = 1) -> [Float] {
        var samples = silence(0.18 * length)
        var state = seed &* 747_796_405 &+ 2_891_336_453
        var filtered: Float = 0, previous: Float = 0
        for i in samples.indices {
            let t = Double(i) / rate
            // The click: noise with the low end taken out, very short.
            state = state &* 1_664_525 &+ 1_013_904_223
            let white = Float(state >> 8) / Float(1 << 23) - 1
            filtered += (white - filtered) * 0.6
            let high = filtered - previous
            previous = filtered
            let click = Double(high) * exp(-t / 0.0025) * 2.2 * brightness
            let body = 0.6 * sin(2 * .pi * 880 * pitch * t) * exp(-t / (0.02 * length)) +
                0.35 * sin(2 * .pi * 2150 * pitch * t) * exp(-t / (0.008 * length)) +
                0.5 * sin(2 * .pi * 210 * pitch * t) * exp(-t / (0.05 * length))
            let attack = min(1, t / 0.0004)
            samples[i] = Float((click + body) * attack)
        }
        return samples
    }

    /// A small bell: inharmonic partials dying away at their own rates.
    private static func bell(frequency: Double, length: Double) -> [Float] {
        var samples = silence(length)
        let partials: [(ratio: Double, gain: Double, decay: Double)] = [(1, 1, 1), (2, 0.45, 0.6), (2.76, 0.3, 0.4), (5.4, 0.12, 0.25)]
        for i in samples.indices {
            let t = Double(i) / rate
            var value = 0.0
            for partial in partials {
                value += partial.gain * sin(2 * .pi * frequency * partial.ratio * t) * exp(-t / (length * 0.35 * partial.decay))
            }
            samples[i] = Float(value * min(1, t / 0.004))
        }
        return samples
    }
}
