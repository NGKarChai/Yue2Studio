import XCTest
import MLX
import MLXFFT
@testable import Yue2Studio

final class FFTConventionTests: XCTestCase {
    override func setUp() { Device.setDefault(device: Device(.gpu)) }

    /// MLX must use the same irfft normalization as torch's norm="backward",
    /// otherwise every Vocos frame comes out scaled by n.
    func testIrfftIsTrueInverseOfRfft() {
        // Deliberately not forcing Device(.cpu): setDefault is global and would
        // leave every later test running MLX on CPU.
        let n = 64
        var vals = [Float]()
        for i in 0..<n { vals.append(Float(sin(Double(i) * 0.3) + 0.5 * cos(Double(i) * 0.11))) }
        let x = MLXArray(vals)

        let spec = MLXFFT.rfft(x)
        let back = MLXFFT.irfft(spec, n: n)
        eval(back)
        let out = back.asArray(Float.self)

        XCTAssertEqual(out.count, n)
        var maxErr: Float = 0
        for i in 0..<n { maxErr = max(maxErr, abs(out[i] - vals[i])) }
        print("[FFT] round-trip max error = \(maxErr)")
        XCTAssertLessThan(maxErr, 1e-4, "irfft is not the unscaled inverse of rfft")
    }
}
