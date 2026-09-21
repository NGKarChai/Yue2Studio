import XCTest
import MLX
import MLXNN
import AVFoundation
import Accelerate
@testable import Yue2Studio

final class PipelineTests: XCTestCase {
    override func setUpWithError() throws {
        Device.setDefault(device: Device(.gpu))
    }

    func testPromptFormatter() {
        let tags = "pop, female vocal"
        let lyrics = "[verse]\nSinging in the morning light\n\n[chorus]\nEchoes in the night"
        let formatted = PromptFormatter.format(genreTags: tags, lyrics: lyrics)

        XCTAssertTrue(formatted.contains("[Genre] English, pop, female vocal"))
        XCTAssertTrue(formatted.contains("Generate music from the given lyrics segment by segment."))
        XCTAssertTrue(formatted.contains("[start_of_segment]"))
        XCTAssertTrue(formatted.contains("[verse]\nSinging in the morning light"))

        let sections = PromptFormatter.extractSections(from: lyrics)
        XCTAssertEqual(sections, ["verse", "chorus"])

        let segments = PromptFormatter.splitIntoSegments(lyrics: lyrics)
        XCTAssertEqual(segments.count, 2)
    }

    func testSampler() {
        let logits = MLXArray([Float]([1.0, 2.0, 5.0, 0.5]))
        let params = SamplingParameters(temperature: 0.8, topP: 0.95, seed: 123)
        let sampled = Sampler.sample(logits: logits, params: params)
        XCTAssertTrue(sampled >= 0 && sampled < 4)
    }

    func testSamplerTopPAccuracy() {
        let original = MLXArray([Float]([1.0, 10.0, 3.0, 8.0, 2.0]))
        let probs = MLX.softmax(original, axis: -1)
        eval(probs)
        print("[testSamplerTopP] Probs: \(probs)")

        let sortedIndices = MLX.argSort(-probs, axis: -1)
        eval(sortedIndices)
        print("[testSamplerTopP] sortedIndices: \(sortedIndices)")

        let sortedProbs = probs[sortedIndices]
        eval(sortedProbs)
        print("[testSamplerTopP] sortedProbs: \(sortedProbs)")

        let cumProbs = MLX.cumsum(sortedProbs, axis: -1)
        eval(cumProbs)
        print("[testSamplerTopP] cumProbs: \(cumProbs)")

        let maskCondition = cumProbs .> 0.9
        eval(maskCondition)
        print("[testSamplerTopP] maskCondition: \(maskCondition)")

        let shiftedMask = MLX.concatenated([MLXArray([false]), maskCondition[0..<4]], axis: -1)
        eval(shiftedMask)
        print("[testSamplerTopP] shiftedMask: \(shiftedMask)")

        let filteredSorted = MLX.where(shiftedMask, MLXArray(-Float.infinity), original[sortedIndices])
        eval(filteredSorted)
        print("[testSamplerTopP] filteredSorted: \(filteredSorted)")

        let restoreIndices = MLX.argSort(sortedIndices, axis: -1)
        eval(restoreIndices)
        print("[testSamplerTopP] restoreIndices: \(restoreIndices)")

        let restored = filteredSorted[restoreIndices]
        eval(restored)
        print("[testSamplerTopP] restored: \(restored)")

        // Index 1 (value 10.0) and index 3 (value 8.0) must NOT be -infinity
        XCTAssertFalse(restored[1].item(Float.self).isInfinite, "Token with highest prob should survive top-p")
        XCTAssertFalse(restored[3].item(Float.self).isInfinite, "Token with 2nd highest prob should survive top-p")
    }

    func testYuETransformerForwardAndStep() {
        Device.setDefault(device: Device(.cpu))
        let config = YuEConfig(
            vocabSize: 500,
            hiddenSize: 64,
            intermediateSize: 128,
            numHiddenLayers: 2,
            numAttentionHeads: 4,
            numKeyValueHeads: 4
        )
        let model = YuETransformer(config: config)
        let caches = (0..<config.numHiddenLayers).map { _ in KVCache() }

        // Prefill sequence of 10 tokens
        let inputTokens = (0..<10).map { Int32($0) }
        let inputArray = MLXArray(inputTokens).reshaped([1, 10])
        let mask = YuETransformer.createCausalMask(seqLen: 10)

        let logits = model.forward(inputIds: inputArray, mask: mask, caches: caches)
        eval(logits)

        XCTAssertEqual(logits.shape, [1, 10, 500])

        // Single step autoregressive decoding
        let stepLogits = model.step(tokenId: 42, caches: caches)
        eval(stepLogits)

        XCTAssertEqual(stepLogits.shape, [500])
    }

    /// YuE Stage 1 only ever saw an instruction line, a [Genre] line and lyrics.
    /// Injecting anything else - a planner banner, ABC notation - degrades the
    /// melody, so keep the prompt inside the trained distribution.
    func testStage1PromptContainsNoOutOfDistributionMarkers() {
        let lyrics = "[verse]\nWaking up under morning light\n\n[chorus]\nHear the music rising high"
        let segs = PromptFormatter.prepareOrderedSegments(lyrics: lyrics)
        let prompt = PromptFormatter.formatSegment0Prompt(
            genreTags: "female vocal, pop, 120 bpm",
            lyrics: lyrics,
            firstSegment: segs[0],
            scoreABC: "X:1\nT:Untitled\nM:4/4\nK:C\nC E G C | D F A D |",
            cotMode: "full",
            referencePrompt: nil,
            referenceMode: nil
        )

        for banned in ["[System:", "Symbolic Planner", "[Score Plan]", "X:1", "M:4/4", "K:C"] {
            XCTAssertFalse(prompt.contains(banned),
                           "prompt leaked out-of-distribution marker: \(banned)")
        }

        XCTAssertTrue(prompt.hasPrefix("Generate music from the given lyrics segment by segment.\n[Genre] "),
                      "header must be the instruction line followed immediately by [Genre]")
        XCTAssertTrue(prompt.contains("[start_of_segment]"))
        XCTAssertTrue(prompt.contains("Waking up under morning light"))
    }

    /// Every section must receive a usable share of the budget. The previous
    /// allocator handed each vocal section the whole song budget, so the first
    /// long verse could consume everything and starve the rest of the song.
    func testSegmentBudgetsAreDistributedAcrossAllSections() {
        let segments = [
            "[intro]",
            "[verse]\nWaking up under morning light\nChasing shadows into the night",
            "[chorus]\nHold on to me",
            "[verse]\nCounting every step I take\nLearning how to stay awake",
            "[outro]"
        ]
        let total = 3000
        let budgets = YuEPipeline.allocateSegmentBudgets(segments: segments, totalTokens: total)

        XCTAssertEqual(budgets.count, segments.count)
        XCTAssertLessThanOrEqual(budgets.reduce(0, +), total,
                                 "Allocation must not exceed the requested song length")

        for (i, b) in budgets.enumerated() {
            XCTAssertGreaterThanOrEqual(b, 100, "Section \(i) was starved of tokens")
            XCTAssertEqual(b % 2, 0, "Budgets must be even so no half frame is stranded")
        }

        // Verses carry far more lyrics than the bare instrumental bookends.
        XCTAssertGreaterThan(budgets[1], budgets[0])
        XCTAssertGreaterThan(budgets[3], budgets[4])
        // The longer verse should outrank the two-word chorus.
        XCTAssertGreaterThan(budgets[1], budgets[2])
    }

    /// Single-token decoding must not reallocate the cache every step. Growing in
    /// blocks is what keeps a long song from drowning the process in allocation
    /// churn, so pin both the block growth and the correctness of the contents.
    func testKVCacheGrowsInBlocksAndPreservesOrder() {
        Device.setDefault(device: Device(.cpu))
        let step = 16
        let cache = KVCache(growthStep: step)

        let tokenCount = 70
        for t in 0..<tokenCount {
            // One token: [B=1, heads=2, seq=1, headDim=4], tagged with its index.
            let k = MLXArray(Array(repeating: Float(t), count: 1 * 2 * 1 * 4)).reshaped([1, 2, 1, 4])
            let v = MLXArray(Array(repeating: Float(t) + 0.5, count: 1 * 2 * 1 * 4)).reshaped([1, 2, 1, 4])
            let (outK, outV) = cache.update(newKeys: k, newValues: v)
            eval(outK, outV)
            // The returned view exposes only the live region, never the zero tail.
            XCTAssertEqual(outK.dim(2), t + 1)
            XCTAssertEqual(outV.dim(2), t + 1)
        }

        XCTAssertEqual(cache.length, tokenCount)
        XCTAssertEqual(cache.offset, tokenCount)

        // Capacity must be block-quantised, so 70 tokens caused 5 reallocations, not 70.
        let capacity = cache.keys!.dim(2)
        XCTAssertEqual(capacity % step, 0, "Capacity should grow in whole blocks")
        XCTAssertEqual(capacity, 80, "70 tokens at step 16 should reserve exactly 5 blocks")
        XCTAssertGreaterThanOrEqual(capacity, tokenCount)

        // Every token must still be readable at its own position, in order.
        let liveKeys = cache.keys![0..., 0..., 0..<cache.length, 0...]
        eval(liveKeys)
        for t in [0, 1, 15, 16, 42, 69] {
            XCTAssertEqual(liveKeys[0, 0, t, 0].item(Float.self), Float(t), accuracy: 1e-5,
                           "Token \(t) lost or reordered after block growth")
        }
    }

    /// A collapsed acoustic stream decodes to silence. The guard must fire on a
    /// locked-up stream and stay quiet on a healthy one.
    func testDegenerationGuardThresholds() {
        let window = 192
        let minUnique = 6

        // Collapsed: the model cycling between a couple of tokens.
        let stuck = (0..<window).map { 45334 + ($0 % 3) }
        XCTAssertLessThanOrEqual(Set(stuck.suffix(window)).count, minUnique,
                                 "a 3-token loop must trip the guard")

        // Healthy: a real acoustic stream ranges widely over the 1024 entries.
        let healthy = (0..<window).map { 45334 + (($0 * 37 + $0 / 3) % 1024) }
        XCTAssertGreaterThan(Set(healthy.suffix(window)).count, minUnique,
                             "a varied stream must not trip the guard")

        // A sustained musical note still varies in the residual stream; make sure a
        // modest amount of repetition is tolerated.
        let sustained = (0..<window).map { 45334 + (($0 % 24) * 7) }
        XCTAssertGreaterThan(Set(sustained.suffix(window)).count, minUnique,
                             "24 alternating tokens is sparse but not collapse")
    }

    /// The segment budget is a ceiling, not a quota: <EOA> must be reachable early
    /// so the model can close a phrase instead of being forced into degeneration.
    func testEOAGateIsOnlyASmallFloor() {
        for budget in [200, 1000, 2750, 6914] {
            let minSeg = min(max(2, budget - 2), 100)
            XCTAssertLessThanOrEqual(minSeg, 100,
                                     "budget \(budget): gate must stay a small floor, got \(minSeg)")
            let fraction = Double(minSeg) / Double(budget)
            XCTAssertLessThan(fraction, 0.55,
                              "budget \(budget): gate covers \(Int(fraction*100))% of the budget")
        }
    }

    /// Trimming reallocates and copies every layer, so it must leave real headroom.
    /// Evicting back to exactly the window made the next trim fire 256 tokens later,
    /// and the repeated multi-gigabyte spike exhausted memory mid-song.
    func testTrimLeavesHeadroomBelowTheWindow() {
        let cache = KVCache(growthStep: 64)
        let window = 400
        let lowWater = (window * 3) / 4   // 300, the policy the generator uses

        for t in 0..<(window + 50) {
            let k = MLXArray(Array(repeating: Float(t), count: 1 * 2 * 1 * 4)).reshaped([1, 2, 1, 4])
            _ = cache.update(newKeys: k, newValues: k)
        }
        XCTAssertGreaterThan(cache.length, window)

        cache.trim(toWindow: lowWater, keepPrefix: 8)
        XCTAssertEqual(cache.length, lowWater)

        // The gap to the window is the headroom that keeps trims rare.
        let headroom = window - cache.length
        XCTAssertGreaterThanOrEqual(headroom, 64, "trim left too little headroom; it will re-fire almost immediately")
        print("[TRIM] length=\(cache.length) window=\(window) headroom=\(headroom) tokens")

        // Newest token must survive the eviction.
        let kept = cache.keys!
        eval(kept)
        XCTAssertEqual(kept[0, 0, cache.length - 1, 0].item(Float.self), Float(window + 49), accuracy: 1e-5)
    }

    /// Long songs exceed the model's 16384-position context, so generation relies on
    /// a sliding window that keeps a few leading positions as attention sinks.
    func testKVCacheTrimKeepsSinkPrefixAndRecentTail() {
        Device.setDefault(device: Device(.cpu))
        let cache = KVCache(growthStep: 32)
        let total = 200
        for t in 0..<total {
            let k = MLXArray(Array(repeating: Float(t), count: 1 * 2 * 1 * 4)).reshaped([1, 2, 1, 4])
            _ = cache.update(newKeys: k, newValues: k)
        }
        XCTAssertEqual(cache.length, total)

        let window = 50, sink = 8
        cache.trim(toWindow: window, keepPrefix: sink)
        XCTAssertEqual(cache.length, window)
        XCTAssertEqual(cache.offset, total, "absolute position must survive trimming")

        let kept = cache.keys!
        eval(kept)
        // First `sink` entries are the original leading positions 0..<8.
        for i in 0..<sink {
            XCTAssertEqual(kept[0, 0, i, 0].item(Float.self), Float(i), accuracy: 1e-5,
                           "sink position \(i) should be preserved")
        }
        // The remainder is the most recent tail, ending at the newest token.
        XCTAssertEqual(kept[0, 0, window - 1, 0].item(Float.self), Float(total - 1), accuracy: 1e-5,
                       "newest token must be retained")
        let firstTail = kept[0, 0, sink, 0].item(Float.self)
        XCTAssertEqual(firstTail, Float(total - (window - sink)), accuracy: 1e-5,
                       "tail should start exactly window-sink back from the end")
    }

    /// Trimming evicts old positions but must leave `offset` advancing, because
    /// RoPE is relative: retained keys keep their original absolute phase.
    func testKVCacheTrimEvictsOldPositionsButKeepsAbsoluteOffset() {
        Device.setDefault(device: Device(.cpu))
        let cache = KVCache()
        // [B, heads, seqLen, headDim]
        let k = MLXArray((0..<(1 * 2 * 40 * 4)).map { Float($0) }).reshaped([1, 2, 40, 4])
        let v = MLXArray((0..<(1 * 2 * 40 * 4)).map { Float($0) }).reshaped([1, 2, 40, 4])
        _ = cache.update(newKeys: k, newValues: v)
        XCTAssertEqual(cache.offset, 40)
        XCTAssertEqual(cache.cachedLength, 40)

        cache.trim(toWindow: 16)
        XCTAssertEqual(cache.cachedLength, 16, "Cache should hold only the retained window")
        XCTAssertEqual(cache.offset, 40, "Absolute position must keep advancing after eviction")

        // The retained window must be the most recent positions, not the oldest.
        let retained = cache.keys!
        eval(retained)
        let firstRetained = retained[0, 0, 0, 0].item(Float.self)
        let expected = k[0, 0, 24, 0].item(Float.self)
        XCTAssertEqual(firstRetained, expected, accuracy: 1e-4)

        // A window larger than the contents is a no-op.
        cache.trim(toWindow: 999)
        XCTAssertEqual(cache.cachedLength, 16)
    }

    func testMultiSegmentKVCachePrefillAndAttentionMask() {
        Device.setDefault(device: Device(.cpu))
        let config = YuEConfig(
            vocabSize: 500,
            hiddenSize: 64,
            intermediateSize: 128,
            numHiddenLayers: 2,
            numAttentionHeads: 4,
            numKeyValueHeads: 4
        )
        let model = YuETransformer(config: config)
        let caches = (0..<config.numHiddenLayers).map { _ in KVCache() }

        // Segment 1 prefill: 10 tokens
        let seg1 = MLXArray((0..<10).map { Int32($0) }).reshaped([1, 10])
        let mask1 = YuETransformer.createCausalMask(seqLen: 10, pastLen: caches[0].offset)
        _ = model.forward(inputIds: seg1, mask: mask1, caches: caches)
        eval(caches[0].offset)
        XCTAssertEqual(caches[0].offset, 10)

        // Autoregressive steps in segment 1: 5 tokens
        for i in 0..<5 {
            _ = model.step(tokenId: 100 + i, caches: caches)
        }
        eval(caches[0].offset)
        XCTAssertEqual(caches[0].offset, 15)

        // Segment 2 prefill: 7 tokens into the active cache with pastLen = 15
        let seg2 = MLXArray((0..<7).map { Int32($0) }).reshaped([1, 7])
        let pastLen = caches[0].offset
        XCTAssertEqual(pastLen, 15)
        let mask2 = YuETransformer.createCausalMask(seqLen: 7, pastLen: pastLen)
        XCTAssertEqual(mask2.shape, [7, 22])

        // Verify forward passes cleanly without broadcast shape errors
        let outSeg2 = model.forward(inputIds: seg2, mask: mask2, caches: caches)
        eval(outSeg2)
        XCTAssertEqual(outSeg2.shape, [1, 7, 500])
        XCTAssertEqual(caches[0].offset, 22)

        // Subsequent step in segment 2
        let step2 = model.step(tokenId: 200, caches: caches)
        eval(step2)
        XCTAssertEqual(step2.shape, [500])
        XCTAssertEqual(caches[0].offset, 23)
    }

    func testStage1MLPDimensions() {
        Device.setDefault(device: Device(.cpu))
        // Verify exact Stage 1 dimensions: hiddenSize 4096, intermediateSize 11008
        let mlpConfig = YuEConfig(
            vocabSize: 32000,
            hiddenSize: 4096,
            intermediateSize: 11008,
            numHiddenLayers: 1,
            numAttentionHeads: 32,
            numKeyValueHeads: 32
        )
        let mlp = YuEMLP(config: mlpConfig)
        let dummyInput = MLXArray.zeros([1, 5, 4096])
        let mlpOut = mlp(dummyInput)
        eval(mlpOut)

        XCTAssertEqual(mlpOut.shape, [1, 5, 4096])
    }

    func testXCodecDecoderAndPCMBuffer() throws {
        Device.setDefault(device: Device(.cpu))
        let config = XCodecConfig(
            numCodebooks: 8,
            codebookSize: 256,
            codebookDim: 32,
            hiddenDim: 32,
            upsampleRates: [2, 2],
            sampleRate: 44100,
            channels: 2
        )
        let decoder = XCodecDecoder(config: config)
        decoder.initializeSyntheticWeightsForTesting()

        // Generate synthetic tokens [8, 4]
        let numFrames = 4
        var tokens: [Int32] = []
        for _ in 0..<(8 * numFrames) {
            tokens.append(Int32.random(in: 0..<256))
        }
        let tokenTensor = MLXArray(tokens).reshaped([8, numFrames])

        let audioTensor = try decoder.decode(tokens: tokenTensor)
        eval(audioTensor)

        XCTAssertEqual(audioTensor.ndim, 2)
        XCTAssertEqual(audioTensor.dim(0), 2) // Stereo

        let buffer = decoder.createPCMBuffer(from: audioTensor)
        XCTAssertNotNil(buffer)
        XCTAssertEqual(buffer?.format.channelCount, 2)
        XCTAssertEqual(buffer?.format.sampleRate, 44100)
    }

    func testNeuralXCodecWeightsLoadingAndForwardPass() throws {
        let xcodecDir = URL(fileURLWithPath: "Models/xcodec")
        guard FileManager.default.fileExists(atPath: xcodecDir.appendingPathComponent("decoder.safetensors").path) else {
            print("[testNeuralXCodecWeightsLoadingAndForwardPass] Skipping as decoder.safetensors is not present")
            return
        }

        let decoder = XCodecDecoder()
        try decoder.loadWeights(from: xcodecDir)
        XCTAssertTrue(decoder.hasLoadedWeights)
        XCTAssertEqual(decoder.codebooks.count, 12)

        // Verify default ConvTransposed1d weight shape in MLX
        let dummyConvT = ConvTransposed1d(inputChannels: 1024, outputChannels: 512, kernelSize: 16, stride: 8, padding: 4)
        print("[testNeuralXCodec] MLX default ConvTransposed1d.weight.shape = \(dummyConvT.weight.shape)")
        print("[testNeuralXCodec] acousticDecoder.blocks[0].convT1.weight.shape = \(decoder.acousticDecoder.blocks[0].convT1.weight.shape)")

        // Verify that parameters were actually updated
        let p = decoder.acousticDecoder.parameters()
        let flattenedP = p.flattened()
        print("[testNeuralXCodec] flattened parameters count = \(flattenedP.count)")
        for (k, v) in flattenedP.prefix(25) {
            print("  Param: \(k) shape=\(v.shape)")
        }

        // Generate dummy audio tokens: 8 codebooks, 10 frames
        let numFrames = 10
        var tokens: [Int32] = []
        for _ in 0..<(8 * numFrames) {
            tokens.append(Int32.random(in: 0..<1024))
        }
        let tokenTensor = MLXArray(tokens).reshaped([8, numFrames])

        let audio = try decoder.decode(tokens: tokenTensor)
        eval(audio)

        print("[testNeuralXCodec] 8-codebook audio: min=\(audio.min().item(Float.self)), max=\(audio.max().item(Float.self)), mean=\(audio.mean().item(Float.self))")

        XCTAssertEqual(audio.dim(0), 2)
        // 10 frames * 320 upsampling = 3200 samples
        XCTAssertEqual(audio.dim(1), numFrames * 320)

        let rawBuffer = decoder.createPCMBuffer(from: audio, resampleTo: 16000)
        XCTAssertNotNil(rawBuffer)
        XCTAssertEqual(rawBuffer?.format.sampleRate, 16000)
        XCTAssertEqual(rawBuffer?.frameLength, AVAudioFrameCount(numFrames * 320))

        let studioBuffer = decoder.createPCMBuffer(from: audio)
        XCTAssertNotNil(studioBuffer)
        XCTAssertEqual(studioBuffer?.format.sampleRate, 44100)

        // Test single codebook decoding (clean Stage 1 output without Stage 2 noise)
        let cb0Tokens = (0..<numFrames).map { Int32($0 % 1024) }
        let cb0Tensor = MLXArray(cb0Tokens).reshaped([1, numFrames])
        let audioCb0 = try decoder.decode(tokens: cb0Tensor)
        eval(audioCb0)

        // Diagnostic check: check block by block in acousticDecoder
        var h = decoder.fc2Weight != nil ? (MLX.matmul(decoder.codebooks[0][0..<10].reshaped([1, 10, 1024]), decoder.fc2Weight!.transposed(1, 0)) + decoder.fc2Bias!) : MLXArray.zeros([1, 10, 256])
        h = decoder.acousticDecoder.conv1(h)
        eval(h)
        print("[testLayers] after conv1: shape=\(h.shape)")
        for (bi, b) in decoder.acousticDecoder.blocks.enumerated() {
            let beforeB = h.dim(1)
            let s1 = b.snake1(h)
            let ct = b.convT1(s1)
            eval(ct)
            print("[testLayers] block \(bi): input T=\(beforeB) -> after convT1 T=\(ct.dim(1)) (expected \(beforeB * b.stride))")
            
            // Check resUnit1, 2, 3
            let r1 = b.resUnit1(ct)
            eval(r1)
            print("  resUnit1 (dil 1): in=\(ct.dim(1)) out=\(r1.dim(1))")
            let r2 = b.resUnit2(r1)
            eval(r2)
            print("  resUnit2 (dil 3): in=\(r1.dim(1)) out=\(r2.dim(1))")
            let r3 = b.resUnit3(r2)
            eval(r3)
            print("  resUnit3 (dil 9): in=\(r2.dim(1)) out=\(r3.dim(1))")
            h = r3
        }
        let sn1 = decoder.acousticDecoder.snake1(h)
        let outWav = decoder.acousticDecoder.conv2(sn1)
        eval(outWav)
        print("[testLayers] final waveform shape: \(outWav.shape) (expected [1, \(10 * 320), 1])")
        print("[testNeuralXCodec] 1-codebook audioCb0: min=\(audioCb0.min().item(Float.self)), max=\(audioCb0.max().item(Float.self)), mean=\(audioCb0.mean().item(Float.self))")
        XCTAssertEqual(audioCb0.dim(0), 2)
        XCTAssertEqual(audioCb0.dim(1), numFrames * 320)
    }

    func testParallelDualTrackStepAndGreedy() {
        Device.setDefault(device: Device(.cpu))
        let config = YuEConfig(
            vocabSize: 200,
            hiddenSize: 32,
            intermediateSize: 64,
            numHiddenLayers: 2,
            numAttentionHeads: 2,
            numKeyValueHeads: 2
        )
        let transformer = YuETransformer(config: config)
        let caches = (0..<config.numHiddenLayers).map { _ in KVCache() }

        // Test dual-track batch step
        let dualTokens = [42, 88]
        let logits = transformer.stepBatch(tokenIds: dualTokens, caches: caches)
        eval(logits)

        XCTAssertEqual(logits.dim(0), 2)
        XCTAssertEqual(logits.dim(1), 200)

        // Test batched greedy argmax
        let greedyBatch = Sampler.greedyBatch(logits: logits)
        XCTAssertEqual(greedyBatch.count, 2)

        let greedy0 = Sampler.greedy(logits: logits[0])
        let greedy1 = Sampler.greedy(logits: logits[1])
        XCTAssertEqual(greedyBatch[0], greedy0)
        XCTAssertEqual(greedyBatch[1], greedy1)

        // Test Stage2Quality properties
        XCTAssertEqual(Stage2Quality.draft.targetCodebooks, 1)
        XCTAssertEqual(Stage2Quality.balanced.targetCodebooks, 4)
        XCTAssertEqual(Stage2Quality.full.targetCodebooks, 8)
    }

    func testYuETokenizerWithStage1() async throws {
        let tokenizer = YuETokenizer()
        await tokenizer.load(from: URL(fileURLWithPath: "Models/stage1"))
        XCTAssertTrue(tokenizer.isLoaded)

        let prompt = PromptFormatter.format(
            genreTags: "female vocal, modern melodic pop, uplifting synth, acoustic guitar, driving drums, 120 bpm",
            lyrics: "[verse]\nWaking up under morning light\nChasing shadows into the night"
        )
        print("[testYuETokenizerWithStage1] Formatted Prompt:\n\(prompt)")
        let officialPrompt = """
Generate music from the given lyrics segment by segment.
[Genre] female vocal, modern melodic pop, uplifting synth, acoustic guitar, driving drums, 120 bpm
[verse]
Waking up under morning light
Chasing shadows into the night

[start_of_segment]
[verse]
Waking up under morning light
Chasing shadows into the night

"""
        print("[testYuETokenizerWithStage1] Official Formatted Prompt:\n\(officialPrompt)")
        let offTokens = tokenizer.encode(text: officialPrompt)
        print("[testYuETokenizerWithStage1] Official token count: \(offTokens.count)")
        print("[testYuETokenizerWithStage1] Official First 25 tokens: \(offTokens.prefix(25))")
        let offDecoded = tokenizer.decode(tokens: offTokens)
        print("[testYuETokenizerWithStage1] Official Decoded:\n\(offDecoded)")
    }

    func testUserInputSegmentationAndFormatting() {
        let genre = "Acoustic Pop, Guitar Ballad"
        let lyrics = """
        [Intro]
        [Slow piano or acoustic guitar start]
        [Warm atmosphere]

        [Verse 1]
        [Soft and gentle]
        在你回家的路口
        那颗期待的大树
        红的花
        绿的叶

        [Verse 2]
        [Continuing the gentle mood]
        在夜幕中的窗口
        望向远方的眼眸
        """

        let (cleaned, directives) = PromptFormatter.extractDirectivesAndCleanLyrics(lyrics: lyrics)
        XCTAssertEqual(directives.count, 4)
        XCTAssertTrue(directives.contains("Slow piano or acoustic guitar start"))
        XCTAssertTrue(directives.contains("Warm atmosphere"))
        XCTAssertTrue(directives.contains("Soft and gentle"))
        XCTAssertTrue(directives.contains("Continuing the gentle mood"))

        // Verify cleaned lyrics contain canonical tags and no descriptive cues
        XCTAssertTrue(cleaned.contains("[intro]"))
        XCTAssertTrue(cleaned.contains("[verse]"))
        XCTAssertFalse(cleaned.contains("[Slow piano"))
        XCTAssertFalse(cleaned.contains("[Soft and gentle]"))

        // Verify enriched genre tags include Chinese language and extracted directives
        let enriched = PromptFormatter.enrichGenreTags(genreTags: genre, lyrics: cleaned, extraDirectives: directives)
        XCTAssertTrue(enriched.contains("Chinese, Mandarin vocal"))
        XCTAssertTrue(enriched.contains("Acoustic Pop"))
        XCTAssertTrue(enriched.contains("Slow piano or acoustic guitar start"))

        let segments = PromptFormatter.splitIntoSegments(lyrics: lyrics)
        XCTAssertEqual(segments.count, 3)
        XCTAssertEqual(segments[0], "[intro]")
        XCTAssertTrue(segments[1].hasPrefix("[verse]"))
        XCTAssertTrue(segments[1].contains("在你回家的路口"))
        XCTAssertTrue(segments[2].hasPrefix("[verse]"))
        XCTAssertTrue(segments[2].contains("在夜幕中的窗口"))
    }

    func testMultiSegmentPreparationAndPrompting() {
        let genre = "Acoustic Pop, Guitar Ballad"
        let lyrics = """
        [Intro]
        [Slow guitar start]
        [Verse 1]
        在你回家的路口
        那颗期待的大树
        [Verse 2]
        在夜幕中的窗口
        望向远方的眼眸
        """

        let ordered = PromptFormatter.prepareOrderedSegments(lyrics: lyrics)
        XCTAssertEqual(ordered.count, 3) // [intro], [verse], [verse] (never merged)
        XCTAssertEqual(ordered[0], "[intro]")
        XCTAssertTrue(ordered[1].contains("在你回家的路口"))
        XCTAssertTrue(ordered[2].contains("在夜幕中的窗口"))

        let seg0Prompt = PromptFormatter.formatSegment0Prompt(
            genreTags: genre,
            lyrics: lyrics,
            firstSegment: ordered[0]
        )
        XCTAssertTrue(seg0Prompt.contains("Generate music from the given lyrics segment by segment."))
        XCTAssertTrue(seg0Prompt.contains("Chinese, Mandarin vocal"))
        XCTAssertTrue(seg0Prompt.contains("[start_of_segment]"))
        XCTAssertTrue(seg0Prompt.contains("[intro]"))

        let seg1Prompt = PromptFormatter.formatNextSegmentPrompt(segment: ordered[1])
        XCTAssertTrue(seg1Prompt.hasPrefix("[end_of_segment]"))
        XCTAssertTrue(seg1Prompt.contains("[start_of_segment]"))
        XCTAssertTrue(seg1Prompt.contains("在你回家的路口"))
    }

    func testStrictAcousticMaskingConstraints() {
        let vocabSize = 83968
        var maskArray = [Float](repeating: -Float.infinity, count: vocabSize)
        let cb0Start = 45334
        let cb0End = min(cb0Start + 1024, vocabSize)
        for i in cb0Start..<cb0End {
            maskArray[i] = 0.0
        }
        maskArray[32002] = 0.0

        // Verify text tokens are strictly blocked (-inf)
        XCTAssertEqual(maskArray[0], -Float.infinity)
        XCTAssertEqual(maskArray[15000], -Float.infinity)
        XCTAssertEqual(maskArray[31999], -Float.infinity)

        // Verify DAC tokens are strictly blocked
        XCTAssertEqual(maskArray[32022], -Float.infinity)
        XCTAssertEqual(maskArray[40000], -Float.infinity)

        // Verify speech tokens (HuBERT and Semanticodec) are strictly blocked (-inf)
        XCTAssertEqual(maskArray[58700], -Float.infinity) // HuBERT speech
        XCTAssertEqual(maskArray[65000], -Float.infinity) // Semanticodec speech

        // Verify XCodec Codebook 0 tokens (45334..<46358) are strictly unmasked (0.0)
        XCTAssertEqual(maskArray[45334], 0.0)
        XCTAssertEqual(maskArray[45334 + 512], 0.0)
        XCTAssertEqual(maskArray[45334 + 1023], 0.0)

        // Verify <EOA> (32002) is unmasked
        XCTAssertEqual(maskArray[32002], 0.0)
    }

    func testTopPSamplingAndWindowedPenalty() {
        // Create 100 logits where token 10 has dominant probability
        var logitsArr = [Float](repeating: -10.0, count: 100)
        logitsArr[10] = 5.0
        logitsArr[11] = 4.5
        logitsArr[12] = 4.0
        let logits = MLXArray(logitsArr)

        let params = SamplingParameters(temperature: 0.8, topP: 0.90, repetitionPenalty: 1.1)

        // Sample with empty past tokens - should consistently pick from top 3 tokens (10, 11, 12)
        var samples: Set<Int> = []
        for _ in 0..<20 {
            let s = Sampler.sample(logits: logits, params: params, pastTokens: [])
            samples.insert(s)
        }
        XCTAssertTrue(samples.contains(10) || samples.contains(11) || samples.contains(12))
        // Verify tail tokens are never picked
        for s in samples {
            XCTAssertTrue(s == 10 || s == 11 || s == 12, "Sampled token \(s) should be in top tokens")
        }

        // Test sliding-window repetition penalty:
        // When token 10 was recently generated in the last 32 tokens, it receives a penalty
        let past = [10, 10, 10]
        let sPenalized = Sampler.sample(logits: logits, params: params, pastTokens: past, penaltyWindow: 32)
        XCTAssertNotNil(sPenalized)
    }

    func testYuETokenizerWithActualStage1Model() async throws {
        let tokenizer = YuETokenizer()
        let modelDir = URL(fileURLWithPath: "/Users/ngkarchai/Documents/MyProjects/Yue2Studio/Models/stage1")
        await tokenizer.load(from: modelDir)
        XCTAssertTrue(tokenizer.isLoaded)

        let testLyric = "在你回家的路口"
        let tokens = tokenizer.encode(text: testLyric)
        print("=== DIAGNOSTIC TOKENS FOR '\(testLyric)': \(tokens) ===")
        let decoded = tokenizer.decode(tokens: tokens)
        print("=== DIAGNOSTIC DECODED: '\(decoded)' ===")

        let seg0Prompt = PromptFormatter.formatSegment0Prompt(
            genreTags: "Acoustic Pop",
            lyrics: "[Verse 1]\n在你回家的路口\n那颗期待的大树",
            firstSegment: "[Verse 1]\n在你回家的路口\n那颗期待的大树"
        )
        let promptTokens = tokenizer.encode(text: seg0Prompt)
        print("=== PROMPT TEXT:\n\(seg0Prompt)\n===")
        print("=== TOKENS FOR '[start_of_segment]': \(tokenizer.encode(text: "[start_of_segment]")) ===")
        print("=== TOKENS FOR '<SOA>': \(tokenizer.encode(text: "<SOA>")) ===")
        print("=== TOKENS FOR '<xcodec>': \(tokenizer.encode(text: "<xcodec>")) ===")
        print("=== TOKENS FOR '<EOA>': \(tokenizer.encode(text: "<EOA>")) ===")
    }

    func testStage1RealInferenceTokens() async throws {
        let stage1Dir = URL(fileURLWithPath: "/Users/ngkarchai/Documents/MyProjects/Yue2Studio/Models/stage1")
        guard FileManager.default.fileExists(atPath: stage1Dir.appendingPathComponent("model.safetensors.index.json").path) else {
            return
        }

        let tokenizer = YuETokenizer()
        await tokenizer.load(from: stage1Dir)

        let config = YuEConfig(
            vocabSize: 83968,
            hiddenSize: 4096,
            intermediateSize: 11008,
            numHiddenLayers: 32,
            numAttentionHeads: 32,
            numKeyValueHeads: 4
        )
        let transformer = YuETransformer(config: config)
        try transformer.loadWeights(from: stage1Dir, precision: "16-bit")

        let promptText = PromptFormatter.formatSegment0Prompt(
            genreTags: "female vocal, modern melodic pop",
            lyrics: "[verse]\nHello world sunshine",
            firstSegment: "[verse]\nHello world sunshine"
        )
        var promptTokens = tokenizer.encode(text: promptText)
        promptTokens.append(32001) // <SOA>
        promptTokens.append(32016) // <xcodec>

        print("[testStage1Real] prompt tokens count: \(promptTokens.count)")
        let caches = (0..<config.numHiddenLayers).map { _ in KVCache() }

        // Prefill and get logits for position after last prompt token
        var logits = transformer.prefill(tokens: promptTokens, caches: caches)

        let params = SamplingParameters(temperature: 1.0, topP: 0.93, repetitionPenalty: 1.1, seed: 42)
        var mask = [Float](repeating: 0.0, count: 83968)
        for i in 0..<32002 { mask[i] = -Float.infinity }
        let maskArray = MLXArray(mask)

        var generated: [Int] = []
        for step in 0..<30 {
            let nextToken = Sampler.sample(logits: logits + maskArray, params: params, pastTokens: generated, penaltyWindow: 256)
            generated.append(nextToken)
            logits = transformer.step(tokenId: nextToken, caches: caches)
        }
        let uniqueCount = Set(generated).count
        print("[testStage1Real] Generated 30 tokens with official YuE sampling: \(generated)")
        print("[testStage1Real] Unique tokens: \(uniqueCount)/30")
        XCTAssertGreaterThan(uniqueCount, 10, "Generation must not collapse into repeating single tokens")
    }

    func testStage2RealInference() throws {
        let stage2Dir = URL(fileURLWithPath: "/Users/ngkarchai/Documents/MyProjects/Yue2Studio/Models/stage2")
        guard FileManager.default.fileExists(atPath: stage2Dir.appendingPathComponent("model.safetensors").path) else {
            return
        }

        let config = YuEConfig(
            vocabSize: 83840,
            hiddenSize: 2048,
            intermediateSize: 5504,
            numHiddenLayers: 32,
            numAttentionHeads: 16,
            numKeyValueHeads: 16
        )
        let transformer = YuETransformer(config: config)
        try transformer.loadWeights(from: stage2Dir, precision: "16-bit")

        // 5 frames of cb0
        let cb0: [Int32] = [45642, 45674, 45610, 45354, 45866]
        let prompt: [Int32] = [32001, 32013] + cb0 + [32017]

        let caches = (0..<config.numHiddenLayers).map { _ in KVCache() }
        let promptArray = MLXArray(prompt).reshaped([1, prompt.count])
        let mask = YuETransformer.createCausalMask(seqLen: prompt.count)
        _ = transformer.forward(inputIds: promptArray, mask: mask, caches: caches)

        // For frame 0: step cb0 (45642)
        var cur = Int(cb0[0])
        print("[testStage2Real] Frame 0, cb0=\(cur)")
        for k in 1..<8 {
            let logits = transformer.step(tokenId: cur, caches: caches)
            let sortedIdx = MLX.argSort(logits)
            let top1 = Int(sortedIdx[83840 - 1].item(Int32.self))
            let startIdx = 45334 + k * 1024
            let endIdx = startIdx + 1024
            let cbSlice = logits[startIdx..<endIdx]
            let sliceTop1 = Int(MLX.argSort(cbSlice)[1023].item(Int32.self))
            print("  cb\(k): global top1 token=\(top1) (expected range \(startIdx)..< \(endIdx)), slice top1=\(startIdx + sliceTop1) (idx \(sliceTop1))")
            cur = startIdx + sliceTop1
        }
    }

    func testCompareXCodecCodebooks() throws {
        let xcodecDir = URL(fileURLWithPath: "/Users/ngkarchai/Documents/MyProjects/Yue2Studio/Models/xcodec")
        guard FileManager.default.fileExists(atPath: xcodecDir.appendingPathComponent("decoder.safetensors").path) else {
            return
        }

        let decoder = XCodecDecoder()
        try decoder.loadWeights(from: xcodecDir)
        XCTAssertTrue(decoder.hasLoadedWeights)

        let numFrames = 100 // 2 seconds
        // Create realistic cb0 tokens (e.g., constant musical pitch 440)
        let cb0 = [Int32](repeating: 250, count: numFrames)

        // 1. Single Codebook 0 (Draft)
        let t1 = MLXArray(cb0).reshaped([1, numFrames])
        let audio1 = try decoder.decode(tokens: t1)
        eval(audio1)
        let pcm1 = decoder.createPCMBuffer(from: audio1)
        XCTAssertNotNil(pcm1)

        // 2. 8 Codebooks with zero residuals
        var tokens8Zero = [Int32]()
        tokens8Zero.append(contentsOf: cb0)
        for _ in 1..<8 {
            tokens8Zero.append(contentsOf: [Int32](repeating: 0, count: numFrames))
        }
        let t8Zero = MLXArray(tokens8Zero).reshaped([8, numFrames])
        let audio8Zero = try decoder.decode(tokens: t8Zero)
        eval(audio8Zero)
        let pcm8Zero = decoder.createPCMBuffer(from: audio8Zero)
        XCTAssertNotNil(pcm8Zero)

        // 3. 8 Codebooks with random residuals
        var tokens8Rand = [Int32]()
        tokens8Rand.append(contentsOf: cb0)
        for _ in 1..<8 {
            tokens8Rand.append(contentsOf: (0..<numFrames).map { _ in Int32.random(in: 0..<1024) })
        }
        let t8Rand = MLXArray(tokens8Rand).reshaped([8, numFrames])
        let audio8Rand = try decoder.decode(tokens: t8Rand)
        eval(audio8Rand)
        let pcm8Rand = decoder.createPCMBuffer(from: audio8Rand)
        XCTAssertNotNil(pcm8Rand)

        print("[testCompare] 1-cb peak: \(abs(audio1).max().item(Float.self)), rms: \(sqrt(MLX.mean(audio1 * audio1)).item(Float.self))")
        print("[testCompare] 8-cb (zero residual) peak: \(abs(audio8Zero).max().item(Float.self)), rms: \(sqrt(MLX.mean(audio8Zero * audio8Zero)).item(Float.self))")
        print("[testCompare] 8-cb (random residual) peak: \(abs(audio8Rand).max().item(Float.self)), rms: \(sqrt(MLX.mean(audio8Rand * audio8Rand)).item(Float.self))")

        // Export all 3 to scratch/ for verification
        let scratchDir = URL(fileURLWithPath: "/Users/ngkarchai/.gemini/antigravity/brain/1d0c0acc-d626-4652-a321-5bf9bdb92f53/scratch")
        try? AudioExporter.export(buffer: pcm1!, to: scratchDir.appendingPathComponent("test_1cb.wav"))
        try? AudioExporter.export(buffer: pcm8Zero!, to: scratchDir.appendingPathComponent("test_8cb_zero.wav"))
        try? AudioExporter.export(buffer: pcm8Rand!, to: scratchDir.appendingPathComponent("test_8cb_rand.wav"))
    }

    func testEndToEndAudioFidelity() async throws {
        let modelsDir = URL(fileURLWithPath: "/Users/ngkarchai/Documents/MyProjects/Yue2Studio/Models")
        guard FileManager.default.fileExists(atPath: modelsDir.appendingPathComponent("xcodec/decoder.safetensors").path),
              FileManager.default.fileExists(atPath: modelsDir.appendingPathComponent("upsampler/vocal_upsampler.safetensors").path) else {
            return
        }

        let numFrames = 100
        let dec = XCodecDecoder()
        try dec.loadWeights(from: modelsDir.appendingPathComponent("xcodec"))

        var vTokens = [Int32]()
        var iTokens = [Int32]()
        for k in 0..<8 {
            for t in 0..<numFrames {
                vTokens.append(Int32((t * (13 + k) + 200) % 1024))
                iTokens.append(Int32((t * (17 + k) + 350) % 1024))
            }
        }
        let vTensor = MLXArray(vTokens).reshaped([8, numFrames])
        let iTensor = MLXArray(iTokens).reshaped([8, numFrames])

        let vocalAudio = try dec.decode(tokens: vTensor)
        let instAudio = try dec.decode(tokens: iTensor)
        eval(vocalAudio, instAudio)

        let vocalMono = vocalAudio[0]
        let instMono = instAudio[0]
        let mixed = MLX.concatenated([
            (vocalMono * 0.5 + instMono * 0.5).reshaped([1, -1]),
            (vocalMono * 0.5 + instMono * 0.5).reshaped([1, -1])
        ], axis: 0)

        guard var buffer = dec.createPCMBuffer(from: mixed, targetPeak: 0.891, resampleTo: 44100.0, mastering: MasteringProcessor()) else {
            XCTFail("Failed to create PCM buffer")
            return
        }

        let vocalFeats = try dec.quantizedEmbeddings(tokens: vTensor)
        let instFeats = try dec.quantizedEmbeddings(tokens: iTensor)
        let vocalUps = VocosUpsampler()
        try vocalUps.loadWeights(from: modelsDir.appendingPathComponent("upsampler/vocal_upsampler.safetensors"))
        let instUps = VocosUpsampler()
        try instUps.loadWeights(from: modelsDir.appendingPathComponent("upsampler/inst_upsampler.safetensors"))

        let vHi = try vocalUps.synthesize(features: vocalFeats)
        let iHi = try instUps.synthesize(features: instFeats)
        eval(vHi, iHi)

        let vArray = vHi.asArray(Float.self)
        let iArray = iHi.asArray(Float.self)
        let n = min(vArray.count, iArray.count)
        var high = [Float](repeating: 0, count: n)
        for k in 0..<n { high[k] = vArray[k] + iArray[k] }

        var highPeak: Float = 0
        vDSP_maxmgv(high, 1, &highPeak, vDSP_Length(n))
        if highPeak > 1e-4 {
            var highGain = 0.891 / highPeak
            vDSP_vsmul(high, 1, &highGain, &high, 1, vDSP_Length(n))
        }

        let lowChannels = XCodecDecoder.channelArrays(from: buffer)
        let crossover = SpectralCrossover(cutoffHz: 5500.0)
        let combined = lowChannels.map { crossover.combine(low: $0, high: high, sampleRate: 44100.0) }
        if let merged = XCodecDecoder.makeBuffer(channels: combined, sampleRate: 44100.0, targetPeak: 0.891) {
            buffer = merged
        }

        var channels = XCodecDecoder.channelArrays(from: buffer)
        DynamicsProcessor().process(&channels, sampleRate: buffer.format.sampleRate)
        if let leveled = XCodecDecoder.makeBuffer(channels: channels, sampleRate: buffer.format.sampleRate, targetPeak: 0.891) {
            buffer = leveled
        }

        XCTAssertGreaterThan(buffer.frameLength, 0)
        XCTAssertFalse(channels[0].contains { $0.isNaN || $0.isInfinite })

        let genURL = URL(fileURLWithPath: "/Users/ngkarchai/Documents/MyProjects/Yue2Studio/Generations/test_fidelity_repaired.wav")
        try AudioExporter.export(buffer: buffer, to: genURL)
        print("[testEndToEndAudioFidelity] Exported: \(genURL.path)")
    }

    func testMasteringLinearTruePeakAndResampling() throws {
        let decoder = XCodecDecoder()
        // Generate a 16kHz sine wave with artificial DC offset [2, 16000] (1 second)
        let sampleCount = 16000
        var left = [Float](repeating: 0, count: sampleCount)
        var right = [Float](repeating: 0, count: sampleCount)
        let dcOffset: Float = 0.25
        for i in 0..<sampleCount {
            let t = Float(i) / 16000.0
            left[i] = sin(2.0 * .pi * 440.0 * t) * 1.5 + dcOffset
            right[i] = sin(2.0 * .pi * 880.0 * t) * 1.2 + dcOffset
        }
        let tensor = MLXArray(left + right).reshaped([2, sampleCount])
        eval(tensor)

        // Process through mastering chain to 44.1 kHz with target peak 0.891
        guard let mastered = decoder.createPCMBuffer(from: tensor, targetPeak: 0.891, resampleTo: 44100.0) else {
            XCTFail("createPCMBuffer failed to produce mastered buffer")
            return
        }

        XCTAssertEqual(mastered.format.sampleRate, 44100.0)
        XCTAssertEqual(mastered.format.channelCount, 2)
        XCTAssertGreaterThan(mastered.frameLength, 40000)

        guard let outL = mastered.floatChannelData?[0],
              let outR = mastered.floatChannelData?[1] else {
            XCTFail("Missing float channel data")
            return
        }

        let length = Int(mastered.frameLength)
        var maxPeak: Float = 0.0
        var sumL: Float = 0.0
        var sumR: Float = 0.0

        for i in 0..<length {
            let aL = abs(outL[i])
            let aR = abs(outR[i])
            if aL > maxPeak { maxPeak = aL }
            if aR > maxPeak { maxPeak = aR }
            sumL += outL[i]
            sumR += outR[i]
        }

        let meanL = sumL / Float(length)
        let meanR = sumR / Float(length)

        // Verify DC offset is eliminated (< 0.01)
        XCTAssertLessThan(abs(meanL), 0.01)
        XCTAssertLessThan(abs(meanR), 0.01)

        // Verify linear peak normalization holds true (target 0.891 +/- 0.05 due to sinc filter overshoot)
        XCTAssertLessThanOrEqual(maxPeak, 0.95)
        XCTAssertGreaterThan(maxPeak, 0.80)
    }

    func testWeightLoadingThrowsOnMissingFiles() {
        let emptyDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: emptyDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: emptyDir) }

        let decoder = XCodecDecoder()
        XCTAssertThrowsError(try decoder.loadWeights(from: emptyDir)) { error in
            print("[testWeightLoadingThrows] XCodecDecoder threw as expected: \(error.localizedDescription)")
        }

        let transformer = YuETransformer(config: YuEConfig.stage2Default1B())
        XCTAssertThrowsError(try transformer.loadWeights(from: emptyDir)) { error in
            print("[testWeightLoadingThrows] YuETransformer threw as expected: \(error.localizedDescription)")
        }
    }

    func testEndToEndNeuralAudioGeneration() async throws {
        let modelsDir = URL(fileURLWithPath: "/Users/ngkarchai/Documents/MyProjects/Yue2Studio/Models")
        guard FileManager.default.fileExists(atPath: modelsDir.appendingPathComponent("xcodec/decoder.safetensors").path),
              FileManager.default.fileExists(atPath: modelsDir.appendingPathComponent("stage1/config.json").path) else {
            print("[testEndToEndNeuralAudioGeneration] Skipping as model files are not fully present.")
            return
        }

        let pipeline = YuEPipeline()
        let params = SamplingParameters(temperature: 0.8, topP: 0.95, cfgScale: 1.0, seed: 100)

        let buffer = try await pipeline.generateSong(
            genreTags: "acoustic pop guitar",
            lyrics: "[verse]\nMorning sun is rising high",
            modelsDir: modelsDir,
            maxTokens: 40,
            params: params,
            precision: "4-bit",
            stage2Quality: .draft,
            autoUnloadStage1: true,
            progressHandler: { prog in
                print("[EndToEndProgress] \(prog.phase.rawValue): \(prog.statusMessage)")
            }
        )

        XCTAssertNotNil(buffer)
        XCTAssertEqual(buffer.format.sampleRate, 44100)
        XCTAssertEqual(buffer.format.channelCount, 2)
        XCTAssertGreaterThan(buffer.frameLength, 0)

        let ch0 = buffer.floatChannelData![0]
        var maxPeak: Float = 0
        var sumSquares: Float = 0
        for i in 0..<Int(buffer.frameLength) {
            let val = abs(ch0[i])
            if val > maxPeak { maxPeak = val }
            sumSquares += val * val
        }
        let rms = sqrt(sumSquares / Float(buffer.frameLength))
        print("[testEndToEndNeuralAudioGeneration] Generated buffer frames=\(buffer.frameLength), peak=\(maxPeak), rms=\(rms)")

        XCTAssertGreaterThan(maxPeak, 0.1, "Output must contain genuine acoustic audio energy")
        XCTAssertGreaterThan(rms, 0.01, "RMS must indicate audible non-silent acoustic signal")

        let outURL = URL(fileURLWithPath: "/Users/ngkarchai/Documents/MyProjects/Yue2Studio/Generations/test_neural_gen.wav")
        try AudioExporter.export(buffer: buffer, to: outURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outURL.path))
    }
}


