import XCTest
import Accelerate
@testable import Yue2Studio

final class LimiterTests: XCTestCase {

    /// Transients exceeding the threshold must be smoothly limited and never breach the ceiling.
    func testPeakLimiterPreventsOvers() {
        let limiter = MasteringLimiter(settings: MasteringLimiter.Settings(
            targetRMS: 0.18,
            ceiling: 0.891,
            knee: 0.72
        ))

        // Create an audio track with 1 kHz sine wave plus massive transient spikes up to 4.0
        let sr: Double = 44100.0
        let count = 44100
        var channel = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let phase = 2.0 * Double.pi * 1000.0 * Double(i) / sr
            channel[i] = 0.25 * Float(sin(phase))
        }
        // Insert aggressive transients
        channel[1000] = 3.5
        channel[1001] = -4.0
        channel[20000] = 2.8

        var channels = [channel, channel]
        limiter.process(&channels)

        var peakLeft: Float = 0
        var peakRight: Float = 0
        vDSP_maxmgv(channels[0], 1, &peakLeft, vDSP_Length(count))
        vDSP_maxmgv(channels[1], 1, &peakRight, vDSP_Length(count))

        print("[LIMITER] peak after limiting: Left=\(peakLeft), Right=\(peakRight)")
        XCTAssertLessThanOrEqual(peakLeft, 0.891 + 1e-4, "left channel exceeded true-peak ceiling")
        XCTAssertLessThanOrEqual(peakRight, 0.891 + 1e-4, "right channel exceeded true-peak ceiling")
        XCTAssertFalse(channels[0].contains { $0.isNaN || $0.isInfinite })
    }

    /// Quiet audio (e.g. RMS = 0.02) must be normalized towards standard studio loudness (RMS ~ 0.18).
    func testLoudnessNormalizationBoostsQuietAudio() {
        let limiter = MasteringLimiter()

        let sr: Double = 44100.0
        let count = 44100 * 2
        var channel = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let phase = 2.0 * Double.pi * 440.0 * Double(i) / sr
            channel[i] = 0.025 * Float(sin(phase)) // ~0.0177 RMS
        }

        var rmsBefore: Float = 0
        vDSP_rmsqv(channel, 1, &rmsBefore, vDSP_Length(count))

        var channels = [channel, channel]
        limiter.process(&channels)

        var rmsAfter: Float = 0
        vDSP_rmsqv(channels[0], 1, &rmsAfter, vDSP_Length(count))

        print(String(format: "[LIMITER] RMS before: %.4f (%.1f dBFS) -> after: %.4f (%.1f dBFS)",
                     rmsBefore, 20 * log10(rmsBefore), rmsAfter, 20 * log10(rmsAfter)))

        XCTAssertGreaterThan(rmsAfter, 0.14, "audio loudness should be brought up to studio standard")
        XCTAssertLessThanOrEqual(rmsAfter, 0.22, "audio loudness should not excessively overshoot")
    }

    /// Pure silence or near-silence should not be wildly amplified into a hiss.
    func testSilenceIsNotBlownUp() {
        let limiter = MasteringLimiter()

        let count = 44100
        var silentChannel = [Float](repeating: 0, count: count)
        var channels = [silentChannel, silentChannel]

        limiter.process(&channels)

        var peak: Float = 0
        vDSP_maxmgv(channels[0], 1, &peak, vDSP_Length(count))
        XCTAssertEqual(peak, 0.0, accuracy: 1e-6)
    }

    /// Left and right channels must receive identical gain multipliers to protect imaging.
    func testPreservesStereoImaging() {
        let limiter = MasteringLimiter()

        let count = 44100
        var left = [Float](repeating: 0, count: count)
        var right = [Float](repeating: 0, count: count)

        for i in 0..<count {
            let s = Float(sin(2.0 * Double.pi * 300.0 * Double(i) / 44100.0))
            left[i] = 0.04 * s
            right[i] = 0.02 * s // exactly 6 dB down
        }

        var channels = [left, right]
        limiter.process(&channels)

        for i in stride(from: 100, to: count - 100, by: 500) {
            if abs(channels[0][i]) > 0.01 {
                let ratio = channels[1][i] / channels[0][i]
                XCTAssertEqual(ratio, 0.5, accuracy: 0.01, "stereo balance drifted at sample \(i)")
            }
        }
    }
}
