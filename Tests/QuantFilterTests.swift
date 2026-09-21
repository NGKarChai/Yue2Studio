import XCTest
import MLX
import MLXNN
@testable import Yue2Studio

final class QuantFilterTests: XCTestCase {
    override func setUp() { Device.setDefault(device: Device(.gpu)) }

    /// The quantization filter matches on module path. If the path spelling were
    /// wrong the filter would silently match nothing and lm_head would be
    /// quantized anyway, so assert on the real module tree.
    func testLmHeadIsNotQuantizedButLayersAre() {
        let cfg = YuEConfig(
            vocabSize: 512, hiddenSize: 64, intermediateSize: 128,
            numHiddenLayers: 2, numAttentionHeads: 4, numKeyValueHeads: 4
        )
        let model = YuETransformer(config: cfg)

        let paths = model.leafModules().flattened().map { $0.0 }
        XCTAssertTrue(paths.contains("lm_head"), "path spelling changed; filter would be a no-op. Got: \(paths)")

        let keep: Set<String> = ["lm_head"]
        MLXNN.quantize(model: model, groupSize: 64, bits: 4, filter: { p, _ in !keep.contains(p) })

        let after = Dictionary(uniqueKeysWithValues: model.leafModules().flattened())
        XCTAssertFalse(after["lm_head"] is Quantized, "lm_head must stay full precision")

        let quantizedCount = after.filter { $0.value is Quantized }.count
        XCTAssertGreaterThan(quantizedCount, 0, "the rest of the model should still be quantized")
        print("[QUANT] quantized \(quantizedCount) leaf modules, lm_head excluded")
    }
}
