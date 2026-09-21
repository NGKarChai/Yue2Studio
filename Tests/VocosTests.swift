import XCTest
import MLX
@testable import Yue2Studio

final class VocosTests: XCTestCase {
    override func setUp() { Device.setDefault(device: Device(.gpu)) }

    private let dir = URL(fileURLWithPath: "/Users/ngkarchai/Documents/MyProjects/Yue2Studio/Models/upsampler")

    /// Every tensor in the checkpoint must land on a parameter. A silent
    /// mismatch would leave layers randomly initialised and the output noise.
    func testWeightsLoadOntoEveryParameter() throws {
        let ups = VocosUpsampler()
        try ups.loadWeights(from: dir.appendingPathComponent("vocal_upsampler.safetensors"))
        XCTAssertTrue(ups.hasLoadedWeights)

        // The window ships in the checkpoint; if the remap failed it stays all ones.
        eval(ups.head.window)
        let w = ups.head.window.asArray(Float.self)
        XCTAssertEqual(w.count, 3528)
        let mx = w.max() ?? 0, mn = w.min() ?? 0
        XCTAssertLessThan(mn, 0.01, "window should taper to ~0 at the edges, got min \(mn)")
        XCTAssertGreaterThan(mx, 0.9, "window should peak near 1, got max \(mx)")

        // embed weight must be [out, kernel, in] after the transpose.
        eval(ups.backbone.embed.weight)
        XCTAssertEqual(ups.backbone.embed.weight.shape, [512, 7, 1024])
        eval(ups.backbone.convnext[0].dwconv.weight)
        XCTAssertEqual(ups.backbone.convnext[0].dwconv.weight.shape, [512, 7, 1])
    }

    /// The whole point: Vocos must synthesize energy above X-Codec's 8 kHz cliff.
    func testSynthesizesFullBandwidthFromRealCodecFeatures() throws {
        let ups = VocosUpsampler()
        try ups.loadWeights(from: dir.appendingPathComponent("vocal_upsampler.safetensors"))

        // Real 1024-dim features: sum X-Codec codebook embeddings, exactly as the
        // decode path does, so the input sits on the manifold Vocos was trained for.
        let dec = XCodecDecoder()
        try dec.loadWeights(from: URL(fileURLWithPath: "/Users/ngkarchai/Documents/MyProjects/Yue2Studio/Models/xcodec"))

        let frames = 200
        var ids: [Int32] = []
        for k in 0..<8 {
            for t in 0..<frames { ids.append(Int32((t * (7 + k) + k * 53) % 1024)) }
        }
        let tokens = MLXArray(ids).reshaped([8, frames])

        var quantized = MLXArray.zeros([frames, 1024])
        for k in 0..<8 {
            quantized = quantized + MLX.take(dec.codebooks[k], tokens[k], axis: 0)
        }
        let feats = quantized.reshaped([1, frames, 1024])

        let wave = try ups.synthesize(features: feats)
        eval(wave)
        let samples = wave.asArray(Float.self)

        let expected = frames * 882
        print("[VOCOS] frames=\(frames) -> \(samples.count) samples (expected ~\(expected)), \(Double(samples.count)/44100.0)s")
        XCTAssertEqual(Double(samples.count), Double(expected), accuracy: Double(882 * 2),
                       "output length should be frames * hopLength")

        XCTAssertFalse(samples.contains { $0.isNaN || $0.isInfinite }, "non-finite output")
        let peak = samples.map { abs($0) }.max() ?? 0
        XCTAssertGreaterThan(peak, 1e-4, "output is silent")
        print("[VOCOS] peak=\(peak)")

        // Energy above 8 kHz is impossible for the 16 kHz X-Codec path. If Vocos
        // is working, there is real content up there.
        func mag(_ f: Double) -> Double {
            let mid = samples.count / 2
            let seg = Array(samples[mid..<min(mid + 16384, samples.count)])
            let w = 2.0 * Double.pi * f / 44100.0
            let c = 2.0 * cos(w)
            var s1 = 0.0, s2 = 0.0
            for x in seg { let s0 = Double(x) + c * s1 - s2; s2 = s1; s1 = s0 }
            return sqrt(max(0, s1*s1 + s2*s2 - c*s1*s2)) / Double(seg.count)
        }
        let low = mag(1000), at10k = mag(10000), at14k = mag(14000)
        let db10 = 20 * log10(at10k / (low + 1e-12) + 1e-12)
        let db14 = 20 * log10(at14k / (low + 1e-12) + 1e-12)
        print(String(format: "[VOCOS] 1kHz=%.6f  10kHz=%.6f (%+.1f dB)  14kHz=%.6f (%+.1f dB)",
                     low, at10k, db10, at14k, db14))
        XCTAssertGreaterThan(at10k, 1e-7, "no energy at 10 kHz - above X-Codec's ceiling, so Vocos is not working")
    }
}
