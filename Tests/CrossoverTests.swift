import XCTest
import MLX
@testable import Yue2Studio

final class CrossoverTests: XCTestCase {
    override func setUp() { Device.setDefault(device: Device(.gpu)) }

    /// The combined signal must take its lows from the codec source and its
    /// highs from the vocoder source.
    func testTakesLowsFromCodecAndHighsFromVocoder() {
        let sr = 44100.0, n = 44100
        func tone(_ f: Double, _ amp: Float) -> [Float] {
            var out = [Float](); out.reserveCapacity(n)
            for i in 0..<n {
                let phase: Double = 2.0 * Double.pi * f * Double(i) / sr
                out.append(amp * Float(sin(phase)))
            }
            return out
        }
        func mix(_ a: [Float], _ b: [Float]) -> [Float] {
            (0..<a.count).map { a[$0] + b[$0] }
        }

        // "low" source: strong 500 Hz, plus a 12 kHz tone that must be rejected.
        let lowSrc = mix(tone(500, 0.5), tone(12000, 0.5))
        // "high" source: weak 500 Hz, plus the 12 kHz content we want to keep.
        let highSrc = mix(tone(500, 0.25), tone(12000, 0.4))

        let out = SpectralCrossover(cutoffHz: 5500).combine(low: lowSrc, high: highSrc, sampleRate: sr)
        XCTAssertEqual(out.count, n)

        func mag(_ sig: [Float], _ f: Double) -> Double {
            let seg = Array(sig[(sig.count/4)..<(sig.count/4 + 16384)])
            let w = 2.0 * Double.pi * f / sr, c = 2.0 * cos(w)
            var s1 = 0.0, s2 = 0.0
            for x in seg { let s0 = Double(x) + c*s1 - s2; s2 = s1; s1 = s0 }
            return sqrt(max(0, s1*s1 + s2*s2 - c*s1*s2)) / Double(seg.count)
        }

        let out500 = mag(out, 500), out12k = mag(out, 12000)
        let lowSrc12k = mag(lowSrc, 12000)
        print(String(format: "[XOVER] out 500Hz=%.5f  out 12kHz=%.5f  (lowSrc 12kHz was %.5f)",
                     out500, out12k, lowSrc12k))

        XCTAssertGreaterThan(out500, 0.05, "low band should survive the crossover")
        XCTAssertGreaterThan(out12k, 0.05, "vocoder highs should survive the crossover")
        // The low source's 12 kHz must have been filtered out, so the output's
        // 12 kHz should track the vocoder's amplitude (0.4), not the sum (0.9).
        XCTAssertLessThan(out12k, 0.6, "low source's highs leaked through")
    }

    /// Energy matching must scale the codec lows to meet the vocoder lows.
    func testEnergyMatchesLowBands() {
        let sr = 44100.0, n = 44100
        func tone(_ f: Double, _ amp: Float) -> [Float] {
            var out = [Float](); out.reserveCapacity(n)
            for i in 0..<n {
                let phase: Double = 2.0 * Double.pi * f * Double(i) / sr
                out.append(amp * Float(sin(phase)))
            }
            return out
        }
        // Codec lows are 10x too quiet; the crossover should bring them up.
        let out = SpectralCrossover(cutoffHz: 5500)
            .combine(low: tone(500, 0.05), high: tone(500, 0.5), sampleRate: sr)
        let peak = out.map { abs($0) }.max() ?? 0
        print("[XOVER] matched peak = \(peak)")
        XCTAssertGreaterThan(peak, 0.3, "codec lows were not scaled up to the vocoder level")
        XCTAssertLessThan(peak, 0.8, "scaling overshot")
    }
}
