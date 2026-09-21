import XCTest
import MLX
import AVFoundation
@testable import Yue2Studio

final class MasteringTests: XCTestCase {
    override func setUp() { Device.setDefault(device: Device(.gpu)) }

    /// The chain must cut the boxy low-mids and lift presence, without touching
    /// the top octave where only codec artifacts live.
    func testChainShapesSpectrumAsIntended() {
        let sr = 16000.0
        let proc = MasteringProcessor()
        let sections = proc.sections(sampleRate: sr)
        XCTAssertEqual(sections.count, 4, "high-pass + boxiness + body + presence")

        func responseDB(_ f: Double) -> Double {
            var total = 1.0
            let w = 2.0 * Double.pi * f / sr
            for s in sections {
                let cw = cos(w), sw = sin(w)
                let c2w = cos(2*w), s2w = sin(2*w)
                let nr = s.b0 + s.b1*cw + s.b2*c2w
                let ni = -(s.b1*sw + s.b2*s2w)
                let dr = 1.0 + s.a1*cw + s.a2*c2w
                let di = -(s.a1*sw + s.a2*s2w)
                total *= sqrt((nr*nr+ni*ni)/(dr*dr+di*di))
            }
            return 20*log10(total + 1e-12)
        }

        let at40 = responseDB(40), at220 = responseDB(220)
        let at1200 = responseDB(1200), at3200 = responseDB(3200), at7500 = responseDB(7500)
        print(String(format: "[EQ] 40Hz %+.1f  220Hz %+.1f  1200Hz %+.1f  3200Hz %+.1f  7500Hz %+.1f",
                     at40, at220, at1200, at3200, at7500))

        XCTAssertLessThan(at40, -7.5, "sub-rumble should be removed")
        XCTAssertLessThan(at220, -1.0, "boxiness band should be cut")
        XCTAssertGreaterThan(at3200, 1.0, "presence should be lifted")
        XCTAssertGreaterThan(at3200, at220, "midrange must end up above the low-mids")
        XCTAssertLessThan(abs(at7500), 2.0, "top octave left essentially alone")
        // The chain is corrective, not a loudness trick: keep every band modest so
        // peak normalization does not have to re-amplify a gutted signal.
        XCTAssertLessThan(at3200, 3.0, "presence lift must stay gentle")
        XCTAssertGreaterThan(at220, -4.0, "boxiness cut must stay gentle")
    }

    /// Filters must be stable: no NaN, no runaway on a long signal.
    func testChainIsStableOverLongSignal() {
        var sig = [Float]()
        sig.reserveCapacity(160_000)
        for i in 0..<160_000 {
            let t = Double(i)
            let a: Double = sin(t * 0.05) * 0.4
            let b: Double = sin(t * 0.9) * 0.2
            sig.append(Float(a + b))
        }
        MasteringProcessor().process(&sig, sampleRate: 16000.0)
        XCTAssertFalse(sig.contains { $0.isNaN || $0.isInfinite }, "filter produced non-finite output")
        let peak = sig.map { abs($0) }.max() ?? 0
        XCTAssertLessThan(peak, 4.0, "filter should not run away")
        XCTAssertGreaterThan(peak, 0.01, "filter should not kill the signal")
    }
}
