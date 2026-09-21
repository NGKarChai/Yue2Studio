import XCTest
import MLX
@testable import Yue2Studio

final class DynamicsTests: XCTestCase {
    override func setUp() { Device.setDefault(device: Device(.gpu)) }

    private func tone(_ f: Double, _ amp: Float, _ n: Int, _ sr: Double) -> [Float] {
        var out = [Float](); out.reserveCapacity(n)
        for i in 0..<n {
            let phase: Double = 2.0 * Double.pi * f * Double(i) / sr
            out.append(amp * Float(sin(phase)))
        }
        return out
    }

    private func rms(_ x: ArraySlice<Float>) -> Float {
        guard !x.isEmpty else { return 0 }
        var acc: Float = 0
        for v in x { acc += v * v }
        return sqrt(acc / Float(x.count))
    }

    /// The real defect: sections rendered at very different levels. A 17 dB
    /// spread must come down substantially without being flattened to nothing.
    func testLevelerClosesSectionToSectionDrift() {
        let sr = 44100.0
        let secs = 8
        // Three "sections": quiet, loud, quiet-ish — a 17 dB spread.
        var sig = tone(220, 0.020, sr_i(secs, sr), sr)
        sig += tone(220, 0.140, sr_i(secs, sr), sr)
        sig += tone(220, 0.035, sr_i(secs, sr), sr)

        var channels = [sig, sig]
        let before = sectionRMS(sig, sr: sr, secs: secs)
        DynamicsProcessor().process(&channels, sampleRate: sr)
        let after = sectionRMS(channels[0], sr: sr, secs: secs)

        let spreadBefore = 20 * log10(before.max()! / before.min()!)
        let spreadAfter = 20 * log10(after.max()! / after.min()!)
        print(String(format: "[DYN] section spread %.1f dB -> %.1f dB", spreadBefore, spreadAfter))
        print("[DYN] before: " + before.map { String(format: "%.4f", $0) }.joined(separator: " "))
        print("[DYN] after:  " + after.map { String(format: "%.4f", $0) }.joined(separator: " "))

        XCTAssertGreaterThan(spreadBefore, 15.0, "test signal should start with a wide spread")
        XCTAssertLessThan(spreadAfter, spreadBefore - 6.0, "leveler should close most of the drift")
        XCTAssertGreaterThan(spreadAfter, 0.5, "should not flatten every section to identical level")
    }

    /// Silence must not be pumped up into a noise floor.
    func testLevelerLeavesSilenceAlone() {
        let sr = 44100.0
        let n = Int(sr * 3)
        var sig = [Float](repeating: 0, count: n)
        var channels = [sig, sig]
        DynamicsProcessor().process(&channels, sampleRate: sr)
        XCTAssertEqual(channels[0].map { abs($0) }.max() ?? 0, 0, accuracy: 1e-9)

        // A tiny amount of noise should also stay tiny.
        for i in 0..<n { sig[i] = (i % 7 == 0) ? 0.0005 : -0.0003 }
        channels = [sig, sig]
        DynamicsProcessor().process(&channels, sampleRate: sr)
        let peak = channels[0].map { abs($0) }.max() ?? 0
        print("[DYN] near-silence peak after leveling = \(peak)")
        XCTAssertLessThan(peak, 0.01, "leveler amplified the noise floor")
    }

    /// Stereo channels must share one gain curve so the image does not wander.
    func testAppliesIdenticalGainToBothChannels() {
        let sr = 44100.0
        let n = Int(sr * 4)
        let left = tone(220, 0.05, n, sr)
        let right = left.map { $0 * 0.5 }
        var channels = [left, right]
        DynamicsProcessor().process(&channels, sampleRate: sr)

        for i in stride(from: 1000, to: n, by: 4096) {
            let ratio = channels[1][i] / (channels[0][i] == 0 ? 1e-9 : channels[0][i])
            XCTAssertEqual(ratio, 0.5, accuracy: 0.02, "channel balance drifted at sample \(i)")
        }
    }

    /// Output must stay finite and bounded.
    func testStaysFiniteAndBounded() {
        let sr = 44100.0
        let n = Int(sr * 5)
        var sig = tone(440, 0.3, n, sr)
        for i in 0..<n where i % 20000 == 0 { sig[i] = 0.95 }   // transients
        var channels = [sig]
        DynamicsProcessor().process(&channels, sampleRate: sr)
        XCTAssertFalse(channels[0].contains { $0.isNaN || $0.isInfinite })
        XCTAssertLessThan(channels[0].map { abs($0) }.max() ?? 0, 3.0)
    }

    private func sr_i(_ secs: Int, _ sr: Double) -> Int { Int(Double(secs) * sr) }

    private func sectionRMS(_ x: [Float], sr: Double, secs: Int) -> [Float] {
        let per = Int(Double(secs) * sr)
        var out: [Float] = []
        var i = 0
        while i + per <= x.count { out.append(rms(x[i..<(i + per)])); i += per }
        return out
    }
}
