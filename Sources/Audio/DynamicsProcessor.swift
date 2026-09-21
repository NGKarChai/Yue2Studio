import Foundation
import Accelerate

/// Leveling and compression for generated audio.
///
/// YuE renders each lyric section as its own Stage 1 block with no knowledge of
/// how loud the previous one came out, so sections drift badly against each
/// other — measured on a real render, one section sat 12 dB below the song's
/// median while a later one sat 5 dB above it. Within a section the model also
/// surges, with second-to-second changes reaching 30 dB. Both read as an
/// untrained singer wandering toward and away from a microphone.
///
/// Two stages address the two timescales:
///  - the leveler works on a multi-second window and removes the slow drift
///    between sections, without touching musical phrasing;
///  - the compressor works in milliseconds and tames the fast surges.
public struct DynamicsProcessor: Sendable {
    public struct Settings: Sendable {
        /// Seconds of audio the leveler averages over. Long enough to ignore
        /// individual notes, short enough to follow a section change.
        public var levelerWindowSeconds: Double
        /// RMS the leveler aims for.
        public var levelerTargetRMS: Float
        /// Largest boost and cut the leveler may apply, in dB. Bounded so it
        /// cannot haul up a deliberate quiet passage or pump on a loud one.
        public var levelerMaxBoostDB: Float
        public var levelerMaxCutDB: Float
        /// Seconds for the leveler's gain to travel most of the way to a new
        /// value. Slow, so it reads as consistency rather than as an effect.
        public var levelerSmoothingSeconds: Double

        /// Compressor threshold as a linear amplitude, ratio, and envelope times.
        public var compressorThreshold: Float
        public var compressorRatio: Float
        public var compressorAttackSeconds: Double
        public var compressorReleaseSeconds: Double

        public init(
            levelerWindowSeconds: Double = 2.0,
            levelerTargetRMS: Float = 0.18,
            levelerMaxBoostDB: Float = 18.0,
            levelerMaxCutDB: Float = 8.0,
            levelerSmoothingSeconds: Double = 1.5,
            compressorThreshold: Float = 0.50,
            compressorRatio: Float = 2.5,
            compressorAttackSeconds: Double = 0.015,
            compressorReleaseSeconds: Double = 0.220
        ) {
            self.levelerWindowSeconds = levelerWindowSeconds
            self.levelerTargetRMS = levelerTargetRMS
            self.levelerMaxBoostDB = levelerMaxBoostDB
            self.levelerMaxCutDB = levelerMaxCutDB
            self.levelerSmoothingSeconds = levelerSmoothingSeconds
            self.compressorThreshold = compressorThreshold
            self.compressorRatio = compressorRatio
            self.compressorAttackSeconds = compressorAttackSeconds
            self.compressorReleaseSeconds = compressorReleaseSeconds
        }
    }

    public let settings: Settings

    public init(settings: Settings = Settings()) {
        self.settings = settings
    }

    /// Computes one gain curve from the summed channels and applies it to all of
    /// them, so stereo imaging is preserved rather than each side moving alone.
    public func process(_ channels: inout [[Float]], sampleRate: Double) {
        guard let first = channels.first, !first.isEmpty else { return }
        let n = first.count

        // Mono detector: the loudest channel at each instant.
        var detector = [Float](repeating: 0, count: n)
        for ch in channels {
            let count = min(n, ch.count)
            for i in 0..<count {
                let m = abs(ch[i])
                if m > detector[i] { detector[i] = m }
            }
        }

        let levelerGain = levelerCurve(detector: detector, sampleRate: sampleRate)
        for c in channels.indices {
            let count = min(n, channels[c].count)
            for i in 0..<count { channels[c][i] *= levelerGain[i] }
        }

        // Re-derive the detector after leveling so the compressor reacts to what
        // it will actually receive.
        for i in 0..<n { detector[i] = 0 }
        for ch in channels {
            let count = min(n, ch.count)
            for i in 0..<count {
                let m = abs(ch[i])
                if m > detector[i] { detector[i] = m }
            }
        }

        let compGain = compressorCurve(detector: detector, sampleRate: sampleRate)
        for c in channels.indices {
            let count = min(n, channels[c].count)
            for i in 0..<count { channels[c][i] *= compGain[i] }
        }

        // Soft-knee peak limiting to tame high transients without hard clipping
        let ceil: Float = 0.891
        let kn: Float = 0.72
        let headroom = ceil - kn
        for c in channels.indices {
            let count = min(n, channels[c].count)
            for i in 0..<count {
                let v = channels[c][i]
                let mag = abs(v)
                if mag > kn {
                    let excess = mag - kn
                    let comp = headroom * tanhf(excess / headroom)
                    channels[c][i] = (v >= 0 ? 1.0 : -1.0) * (kn + comp)
                }
            }
        }
    }

    /// Slow gain curve that pulls each multi-second window toward the target RMS.
    func levelerCurve(detector: [Float], sampleRate: Double) -> [Float] {
        let n = detector.count
        let hop = max(1, Int(sampleRate * 0.05))            // 50 ms resolution
        let half = max(hop, Int(sampleRate * settings.levelerWindowSeconds / 2.0))

        let maxBoost = pow(10.0, settings.levelerMaxBoostDB / 20.0)
        let minGain = pow(10.0, -settings.levelerMaxCutDB / 20.0)

        // Running sum of squares for O(n) windowed RMS.
        var prefix = [Double](repeating: 0, count: n + 1)
        for i in 0..<n { prefix[i + 1] = prefix[i] + Double(detector[i]) * Double(detector[i]) }

        var targets: [Float] = []
        var positions: [Int] = []
        var i = 0
        while i < n {
            let lo = max(0, i - half), hi = min(n, i + half)
            let count = max(1, hi - lo)
            let rms = Float(sqrt((prefix[hi] - prefix[lo]) / Double(count)))
            // Silence is left alone: boosting it only raises the noise floor.
            var g: Float = 1.0
            if rms > 0.004 {
                g = min(maxBoost, max(minGain, settings.levelerTargetRMS / rms))
            }
            targets.append(g)
            positions.append(i)
            i += hop
        }

        // One-pole smoothing over the control signal, forward then backward, so
        // the gain neither jumps nor lags behind a section change.
        let alpha = Float(1.0 - exp(-Double(hop) / (sampleRate * settings.levelerSmoothingSeconds)))
        var smooth = targets
        for k in 1..<smooth.count { smooth[k] = smooth[k - 1] + alpha * (smooth[k] - smooth[k - 1]) }
        for k in stride(from: smooth.count - 2, through: 0, by: -1) {
            smooth[k] = smooth[k + 1] + alpha * (smooth[k] - smooth[k + 1])
        }

        // Linear interpolation back to sample rate.
        var gain = [Float](repeating: 1.0, count: n)
        for k in 0..<positions.count {
            let start = positions[k]
            let end = (k + 1 < positions.count) ? positions[k + 1] : n
            let g0 = smooth[k]
            let g1 = (k + 1 < smooth.count) ? smooth[k + 1] : smooth[k]
            let span = max(1, end - start)
            for j in start..<end {
                let t = Float(j - start) / Float(span)
                gain[j] = g0 + (g1 - g0) * t
            }
        }
        return gain
    }

    /// Fast gain curve: attack/release envelope follower feeding a soft ratio.
    func compressorCurve(detector: [Float], sampleRate: Double) -> [Float] {
        let n = detector.count
        let attack = Float(exp(-1.0 / (sampleRate * settings.compressorAttackSeconds)))
        let release = Float(exp(-1.0 / (sampleRate * settings.compressorReleaseSeconds)))
        let threshold = max(1e-6, settings.compressorThreshold)
        let slope = 1.0 / settings.compressorRatio - 1.0

        var gain = [Float](repeating: 1.0, count: n)
        var env: Float = 0
        for i in 0..<n {
            let x = detector[i]
            // Rise quickly, fall slowly.
            let coeff = (x > env) ? attack : release
            env = coeff * env + (1 - coeff) * x
            if env > threshold {
                gain[i] = pow(env / threshold, slope)
            }
        }
        return gain
    }
}
