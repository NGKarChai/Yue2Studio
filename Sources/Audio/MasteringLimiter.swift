import Foundation
import Accelerate
import AVFoundation

/// Professional mastering loudness normalizer and transparent soft-knee peak limiter.
///
/// Rather than dividing the entire audio by a single transient spike (which crushes
/// the entire 3-minute song down to -35 dBFS), MasteringLimiter:
/// 1. Measures integrated active loudness (excluding silence) and applies smooth
///    makeup gain towards the target studio standard (-14 LUFS / RMS ~ 0.18).
/// 2. Passes the signal through a smooth, mathematically continuous soft-knee
///    peak limiter that transparently catches fast transient spikes at the ceiling
///    (-1.0 dBFS / 0.891) without clipping or distortion.
public struct MasteringLimiter: Sendable {
    public struct Settings: Sendable {
        /// Target linear RMS level for active audio passages (0.18 ~ -14.9 dBFS / -14 LUFS standard)
        public var targetRMS: Float
        /// Maximum true-peak ceiling (0.891 ~ -1.0 dBFS)
        public var ceiling: Float
        /// Soft-knee transition threshold (0.72 ~ -2.8 dBFS)
        public var knee: Float
        /// Maximum auto-gain boost allowed
        public var maxGain: Float
        /// Minimum auto-gain cut allowed
        public var minGain: Float

        public init(
            targetRMS: Float = 0.18,
            ceiling: Float = 0.891,
            knee: Float = 0.72,
            maxGain: Float = 12.0,
            minGain: Float = 0.5
        ) {
            self.targetRMS = targetRMS
            self.ceiling = ceiling
            self.knee = knee
            self.maxGain = maxGain
            self.minGain = minGain
        }
    }

    public let settings: Settings

    public init(settings: Settings = Settings()) {
        self.settings = settings
    }

    /// Process per-channel float arrays in place. Stereo balance is strictly preserved.
    public func process(_ channels: inout [[Float]]) {
        guard let first = channels.first, !first.isEmpty else { return }
        let n = first.count
        let chCount = channels.count

        // 1. Calculate active RMS across all channels (ignoring lead-in / tail silence)
        var sumSquares: Double = 0.0
        var activeCount: Int = 0

        for ch in channels {
            let count = min(n, ch.count)
            for i in 0..<count {
                let val = ch[i]
                if abs(val) > 0.002 {
                    sumSquares += Double(val) * Double(val)
                    activeCount += 1
                }
            }
        }

        let activeRMS: Float
        if activeCount > 100 {
            activeRMS = Float(sqrt(sumSquares / Double(activeCount)))
        } else {
            // Fallback to global RMS if mostly silent
            var globalSquares: Double = 0.0
            var totalCount: Int = 0
            for ch in channels {
                let count = min(n, ch.count)
                for i in 0..<count {
                    let val = ch[i]
                    globalSquares += Double(val) * Double(val)
                    totalCount += 1
                }
            }
            activeRMS = totalCount > 0 ? Float(sqrt(globalSquares / Double(totalCount))) : 0.0
        }

        // 2. Compute unified makeup gain
        let autoGain: Float
        if activeRMS > 0.001 {
            let rawGain = settings.targetRMS / activeRMS
            autoGain = min(settings.maxGain, max(settings.minGain, rawGain))
        } else {
            autoGain = 1.0
        }

        // 3. Apply unified gain and smooth soft-knee peak limiting
        let ceil = settings.ceiling
        let kn = min(settings.knee, ceil * 0.95)
        let headroom = ceil - kn

        for c in 0..<chCount {
            let count = min(n, channels[c].count)
            for i in 0..<count {
                let amplified = channels[c][i] * autoGain
                let mag = abs(amplified)

                if mag <= kn {
                    channels[c][i] = amplified
                } else {
                    let excess = mag - kn
                    let compressed = headroom * tanhf(excess / headroom)
                    let limitedMag = kn + compressed
                    channels[c][i] = (amplified >= 0 ? 1.0 : -1.0) * limitedMag
                }
            }
        }
    }

    /// Process an AVAudioPCMBuffer in place or return a newly normalized buffer.
    public func processBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        var channels = AudioBufferUtils.channelArrays(from: buffer)
        guard !channels.isEmpty else { return buffer }

        process(&channels)

        if let mastered = AudioBufferUtils.makeBuffer(
            channels: channels,
            sampleRate: buffer.format.sampleRate,
            targetPeak: nil
        ) {
            return mastered
        }
        return buffer
    }
}
