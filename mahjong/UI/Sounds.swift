//
//  Sounds.swift
//  mahjong
//
//  Short sound effects, generated in code so the app ships no audio files.
//

import AVFoundation

nonisolated enum Sound: CaseIterable, Sendable {
    /// A tile set down hard: a discard.
    case clack
    /// A tile picked up or set in your rack: a draw.
    case click
    /// Two tiles knocked together: a call.
    case knock
    /// Tiles pushed across the table: a pass.
    case slide
    /// A button press.
    case tap
    /// A joker taken from an exposure.
    case joker
    /// A move that isn't allowed, or bad news.
    case warning
    /// Mahjong.
    case win
    /// Winning the whole game.
    case bigWin
}

/// Builds each sound as 16-bit mono WAV data.
nonisolated enum SoundSynth {
    static let sampleRate = 44_100.0

    /// A sine tone that fades in quickly and dies away. `decay` is the time to fall to about a third.
    static func tone(_ frequency: Double, seconds: Double, decay: Double, level: Double) -> [Double] {
        let count = Int(seconds * sampleRate)
        return (0..<count).map { index in
            let t = Double(index) / sampleRate
            let attack = min(t / 0.004, 1)
            return sin(2 * .pi * frequency * t) * attack * exp(-t / decay) * level
        }
    }

    /// A tone that glides from one pitch to another.
    static func sweep(from start: Double, to end: Double, seconds: Double, level: Double) -> [Double] {
        let count = Int(seconds * sampleRate)
        var phase = 0.0
        return (0..<count).map { index in
            let progress = Double(index) / Double(count)
            let t = Double(index) / sampleRate
            phase += 2 * .pi * (start + (end - start) * progress) / sampleRate
            return sin(phase) * min(t / 0.004, 1) * (1 - progress) * level
        }
    }

    /// A burst of filtered noise. Low smoothing gives a soft rush, high smoothing a sharp click.
    static func noise(seconds: Double, decay: Double, smoothing: Double, level: Double, seed: UInt64) -> [Double] {
        var generator = SeededGenerator(seed: seed)
        let count = Int(seconds * sampleRate)
        var previous = 0.0
        return (0..<count).map { index in
            let t = Double(index) / sampleRate
            let raw = Double.random(in: -1...1, using: &generator)
            previous += smoothing * (raw - previous)
            return previous * min(t / 0.002, 1) * exp(-t / decay) * level
        }
    }

    /// Adds two sounds together, sample by sample.
    static func mix(_ a: [Double], _ b: [Double]) -> [Double] {
        let count = max(a.count, b.count)
        return (0..<count).map { (index: Int) -> Double in
            (index < a.count ? a[index] : 0) + (index < b.count ? b[index] : 0)
        }
    }

    /// Quiet, to space out sounds that follow one another.
    static func silence(_ seconds: Double) -> [Double] {
        [Double](repeating: 0, count: Int(seconds * sampleRate))
    }

    /// A hard, bright click with a little body under it: bone or plastic on wood.
    static func hit(pitch: Double, level: Double, seed: UInt64) -> [Double] {
        mix(mix(noise(seconds: 0.05, decay: 0.004, smoothing: 0.9, level: 0.8 * level, seed: seed),
                tone(2300 * pitch, seconds: 0.04, decay: 0.006, level: 0.32 * level)),
            mix(tone(1150 * pitch, seconds: 0.05, decay: 0.012, level: 0.28 * level),
                tone(260 * pitch, seconds: 0.07, decay: 0.018, level: 0.3 * level)))
    }

    /// A soft rush of low noise that swells and fades: tiles sliding on felt.
    static func rustle(seconds: Double, level: Double, seed: UInt64) -> [Double] {
        let raw = noise(seconds: seconds, decay: 10, smoothing: 0.12, level: level, seed: seed)
        return raw.enumerated().map { index, sample in
            let progress = Double(index) / Double(raw.count)
            return sample * sin(.pi * progress)
        }
    }

    static func samples(for sound: Sound) -> [Double] {
        switch sound {
        case .clack:
            return hit(pitch: 1, level: 1, seed: 1)
        case .click:
            return hit(pitch: 1.25, level: 0.45, seed: 2)
        case .knock:
            return hit(pitch: 0.95, level: 0.9, seed: 3) + silence(0.035) + hit(pitch: 1.08, level: 0.9, seed: 4)
        case .slide:
            return rustle(seconds: 0.22, level: 0.55, seed: 5)
        case .tap:
            return tone(880, seconds: 0.035, decay: 0.009, level: 0.35)
        case .joker:
            return mix(sweep(from: 420, to: 940, seconds: 0.18, level: 0.4),
                       silence(0.1) + tone(1320, seconds: 0.14, decay: 0.05, level: 0.25))
        case .warning:
            return mix(tone(150, seconds: 0.2, decay: 0.06, level: 0.5),
                       tone(112, seconds: 0.2, decay: 0.06, level: 0.35))
        case .win:
            return hit(pitch: 1, level: 0.9, seed: 6) + silence(0.04)
                + tone(523, seconds: 0.11, decay: 0.07, level: 0.4)
                + tone(659, seconds: 0.11, decay: 0.07, level: 0.4)
                + tone(784, seconds: 0.30, decay: 0.12, level: 0.4)
        case .bigWin:
            let run = tone(523, seconds: 0.12, decay: 0.08, level: 0.38)
                + tone(659, seconds: 0.12, decay: 0.08, level: 0.38)
                + tone(784, seconds: 0.12, decay: 0.08, level: 0.38)
            let chord = mix(mix(tone(523, seconds: 0.7, decay: 0.25, level: 0.22),
                                tone(784, seconds: 0.7, decay: 0.25, level: 0.22)),
                            tone(1047, seconds: 0.7, decay: 0.25, level: 0.26))
            return run + chord
        }
    }

    /// Wraps samples in a WAV file header.
    static func wav(for sound: Sound) -> Data {
        let pcm = samples(for: sound).map { Int16(max(-1, min(1, $0)) * 32_000) }
        let byteCount = pcm.count * 2
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + byteCount))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append(UInt32(16))                    // size of the format block
        append(UInt16(1))                     // PCM
        append(UInt16(1))                     // mono
        append(UInt32(sampleRate))
        append(UInt32(sampleRate) * 2)        // bytes per second
        append(UInt16(2))                     // bytes per sample
        append(UInt16(16))                    // bits per sample
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(byteCount))
        for sample in pcm { append(sample) }
        return data
    }
}

/// Plays the sound effects. Muting is remembered between launches.
final class Sounds {
    static let shared = Sounds()
    private static let mutedKey = "soundMuted"

    private var players: [Sound: AVAudioPlayer] = [:]

    var isMuted: Bool {
        didSet { UserDefaults.standard.set(isMuted, forKey: Sounds.mutedKey) }
    }

    private init() {
        isMuted = UserDefaults.standard.bool(forKey: Sounds.mutedKey)
        // Ambient: the silent switch mutes the game, and the player's own music keeps playing.
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        for sound in Sound.allCases {
            guard let player = try? AVAudioPlayer(data: SoundSynth.wav(for: sound)) else { continue }
            player.volume = 0.7
            player.prepareToPlay()
            players[sound] = player
        }
    }

    func play(_ sound: Sound) {
        guard !isMuted, let player = players[sound] else { return }
        player.currentTime = 0
        player.play()
    }
}
