import Foundation
import AVFoundation

@Observable
public final class AudioPlaybackEngine: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()

    public private(set) var isPlaying: Bool = false
    public private(set) var currentTime: Double = 0.0
    public private(set) var duration: Double = 0.0
    public var volume: Float = 1.0 {
        didSet { playerNode.volume = volume }
    }
    public var stereoWidth: Double = 0.5 {
        didSet {
            if oldValue != stereoWidth {
                applyStereoWidth()
            }
        }
    }

    private var currentBuffer: AVAudioPCMBuffer?
    private var masterOriginalBuffer: AVAudioPCMBuffer?
    private var timer: Timer?

    public init() {
        engine.attach(playerNode)
        let format = engine.outputNode.outputFormat(forBus: 0)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        try? engine.start()
    }

    deinit {
        stop()
        engine.stop()
    }

    public func load(buffer: AVAudioPCMBuffer, preserveMaster: Bool = false) {
        stop()
        if !preserveMaster {
            self.masterOriginalBuffer = buffer
        }
        let activeBuffer = preserveMaster ? buffer : AudioPlaybackEngine.processStereoWidth(buffer: buffer, width: stereoWidth)
        self.currentBuffer = activeBuffer
        self.duration = Double(activeBuffer.frameLength) / activeBuffer.format.sampleRate
        self.currentTime = 0.0

        // Reconnect playerNode with the buffer's native format so AVAudioEngine resamples cleanly
        engine.disconnectNodeOutput(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: activeBuffer.format)

        if !engine.isRunning {
            try? engine.start()
        }

        playerNode.scheduleBuffer(activeBuffer, at: nil, options: .loops, completionHandler: nil)
    }

    public func applyStereoWidth() {
        guard let master = masterOriginalBuffer else { return }
        let wasPlaying = self.isPlaying
        let savedTime = self.currentTime
        let processed = AudioPlaybackEngine.processStereoWidth(buffer: master, width: stereoWidth)
        load(buffer: processed, preserveMaster: true)
        seek(to: savedTime)
        if wasPlaying {
            play()
        }
    }

    public static func processStereoWidth(buffer: AVAudioPCMBuffer, width: Double) -> AVAudioPCMBuffer {
        guard buffer.format.channelCount == 2,
              let ch0 = buffer.floatChannelData?[0],
              let ch1 = buffer.floatChannelData?[1],
              let output = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameCapacity) else {
            return buffer
        }
        output.frameLength = buffer.frameLength
        guard let out0 = output.floatChannelData?[0],
              let out1 = output.floatChannelData?[1] else {
            return buffer
        }
        let total = Int(buffer.frameLength)
        let w = Float(max(0.0, min(1.0, width)))

        // Mid-Side Stereo width:
        // When width = 0.0: pure solid center mono (identical channels, zero artificial widening)
        // When width = 0.5: focused, natural acoustic mix
        // When width = 1.0: full stereo
        for i in 0..<total {
            let l = ch0[i]
            let r = ch1[i]
            let mid = (l + r) * 0.5
            let side = (l - r) * 0.5
            out0[i] = mid + w * side
            out1[i] = mid - w * side
        }
        return output
    }

    public func play() {
        guard let _ = currentBuffer else { return }
        if !engine.isRunning {
            try? engine.start()
        }
        playerNode.play()
        isPlaying = true
        startTimer()
    }

    public func pause() {
        playerNode.pause()
        isPlaying = false
        stopTimer()
    }

    public func stop() {
        playerNode.stop()
        isPlaying = false
        stopTimer()
        currentTime = 0.0
    }

    public func seek(to time: Double) {
        guard let buffer = currentBuffer else { return }
        let sampleRate = buffer.format.sampleRate
        let targetFrame = AVAudioFramePosition(max(0, min(time, duration)) * sampleRate)
        let remainingFrames = AVAudioFrameCount(max(0, Int64(buffer.frameLength) - targetFrame))

        guard remainingFrames > 0 else { return }

        playerNode.stop()

        guard let segment = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: remainingFrames) else { return }
        segment.frameLength = remainingFrames

        for ch in 0..<Int(buffer.format.channelCount) {
            guard let src = buffer.floatChannelData?[ch], let dst = segment.floatChannelData?[ch] else { continue }
            dst.update(from: src.advanced(by: Int(targetFrame)), count: Int(remainingFrames))
        }

        currentTime = time
        playerNode.scheduleBuffer(segment, at: nil, options: [], completionHandler: nil)
        if isPlaying {
            playerNode.play()
        }
    }

    private func startTimer() {
        stopTimer()
        DispatchQueue.main.async {
            self.timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                guard let self = self, self.isPlaying else { return }
                self.currentTime = min(self.currentTime + 0.05, self.duration)
                if self.currentTime >= self.duration {
                    self.currentTime = 0.0
                }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
