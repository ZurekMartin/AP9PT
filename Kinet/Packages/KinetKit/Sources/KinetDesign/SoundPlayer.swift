import AVFoundation

@MainActor
final class SoundPlayer {
    private struct Tone {
        let frequency: Double
        let start: Double
        let duration: Double
        let amplitude: Double
        var glide = 0.0
        var overtone = 0.22
        var attack = 0.006
    }

    private struct Cue {
        var tones: [Tone] = []
        }

    private static let sampleRate = 44_100.0

    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: SoundPlayer.sampleRate, channels: 1)!
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private var isReady = false
    private var isActivating = false
    private var pending: [HapticEvent] = []
    private var buffers: [HapticEvent: AVAudioPCMBuffer] = [:]

    func play(_ event: HapticEvent) {
        guard let cue = cue(for: event) else { return }
        guard isReady else {
            if pending.count < 4 { pending.append(event) }
            activate()
            return
        }
        start(event, cue: cue)
    }

    private func activate() {
        guard !isActivating else { return }
        isActivating = true
        Task.detached(priority: .userInitiated) { [weak self] in
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try? session.setActive(true)
            await self?.didActivate()
        }
    }

    private func didActivate() {
        for _ in 0..<4 {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            try? engine.connectNode(node, to: engine.mainMixerNode, format: format)
            players.append(node)
        }
        engine.mainMixerNode.outputVolume = 0.8
        isReady = (try? engine.start()) != nil
        let queued = pending
        pending = []
        for event in queued { play(event) }
    }

    private func start(_ event: HapticEvent, cue: Cue) {
        if !engine.isRunning { try? engine.start() }
        guard engine.isRunning, let buffer = buffer(for: event, cue: cue) else { return }
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        try? player.playAudio()
    }

    private func buffer(for event: HapticEvent, cue: Cue) -> AVAudioPCMBuffer? {
        if let cached = buffers[event] { return cached }
        guard let created = render(cue) else { return nil }
        buffers[event] = created
        return created
    }

    private func cue(for event: HapticEvent) -> Cue? {
        switch event {
        case .sessionEnd:
            return Cue(tones: [Tone(frequency: 783.99, start: 0, duration: 1.0, amplitude: 0.2), Tone(frequency: 1174.66, start: 0.13, duration: 1.2, amplitude: 0.17)])
        case .breakEnd:
            return Cue(tones: [
                Tone(frequency: 587.33, start: 0, duration: 1.0, amplitude: 0.34, overtone: 0.16),
                Tone(frequency: 880, start: 0.16, duration: 1.3, amplitude: 0.3, overtone: 0.14)
            ])
        case .breathStart:
            return Cue(tones: [
                Tone(frequency: 880, start: 0, duration: 1.1, amplitude: 0.13, overtone: 0.1),
                Tone(frequency: 659.25, start: 0.2, duration: 1.4, amplitude: 0.12, overtone: 0.1)
            ])
        case .levelUp:
            return Cue(tones: [
                Tone(frequency: 523.25, start: 0, duration: 0.5, amplitude: 0.16),
                Tone(frequency: 659.25, start: 0.12, duration: 0.5, amplitude: 0.16),
                Tone(frequency: 783.99, start: 0.24, duration: 0.55, amplitude: 0.16),
                Tone(frequency: 1046.5, start: 0.38, duration: 1.4, amplitude: 0.2)
            ])
        case .purchase:
            return Cue(tones: [
                Tone(frequency: 440, start: 0, duration: 0.6, amplitude: 0.1, overtone: 0.12),
                Tone(frequency: 659.25, start: 0.08, duration: 0.6, amplitude: 0.08, overtone: 0.12),
                Tone(frequency: 880, start: 0.16, duration: 0.7, amplitude: 0.06, overtone: 0.1)
            ])
        default:
            return nil
        }
    }

    private func render(_ cue: Cue) -> AVAudioPCMBuffer? {
        let ends = cue.tones.map { $0.start + $0.duration }
        guard let end = ends.max() else { return nil }
        let frames = Int((end + 0.05) * Self.sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)), let samples = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(frames)
        var mix = [Double](repeating: 0, count: frames)
        for tone in cue.tones { add(tone, to: &mix) }
        for index in 0..<frames { samples[index] = Float(mix[index]) }
        return buffer
    }

    private func add(_ tone: Tone, to mix: inout [Double]) {
        let first = Int(tone.start * Self.sampleRate)
        let count = Int(tone.duration * Self.sampleRate)
        var phase = 0.0
        for offset in 0..<count where first + offset < mix.count {
            let time = Double(offset) / Self.sampleRate
            let progress = time / tone.duration
            phase += 2 * .pi * tone.frequency * (1 + tone.glide * progress) / Self.sampleRate
            let envelope = min(1, time / tone.attack) * min(1, (tone.duration - time) / 0.04) * exp(-4.2 * progress)
            mix[first + offset] += tone.amplitude * envelope * (sin(phase) + tone.overtone * sin(2 * phase))
        }
    }
}
