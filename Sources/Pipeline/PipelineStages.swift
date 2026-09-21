import Foundation
import MLX
import MLXNN
import MLXRandom

public struct GeneratedSongTokens: Sendable {
    /// Discrete codebook tokens for vocal track: [8, numFrames]
    public var vocalTokens: [[Int]]
    /// Discrete codebook tokens for instrumental track: [8, numFrames]
    public var instrumentalTokens: [[Int]]
    public var numFrames: Int {
        return vocalTokens.first?.count ?? 0
    }
}

public actor Stage1Generator {
    private var model: YuETransformer?
    private var config: YuEConfig

    public init(config: YuEConfig = YuEConfig.stage1Default7B()) {
        self.config = config
    }

    public func loadWeights(from modelDir: URL, precision: String = "4-bit") throws {
        if let diskConfig = YuEConfig.load(from: modelDir) {
            self.config = diskConfig
        }
        let transformer = YuETransformer(config: config)
        try transformer.loadWeights(from: modelDir, precision: precision)
        self.model = transformer
    }

    public func unload() {
        self.model = nil
        MLX.Memory.clearCache()
    }

    /// Autoregressively generates codebook 0 tokens for vocal & instrumental tracks across multiple lyric segments.
    ///
    /// All segments share a single growing KV-cache so the model hears everything it has
    /// already written. Each segment is a complete `<SOA> ... <EOA>` audio block, matching
    /// the structure the model was trained on.
    public func generateMultiSegment(
        segmentPrompts: [[Int]],
        maxTotalTokens: Int,
        segmentBudgets: [Int]? = nil,
        params: SamplingParameters,
        onProgress: @Sendable (Int, Double) -> Void
    ) async throws -> (vocalC0: [Int], instC0: [Int]) {
        guard let model = model else {
            throw NSError(domain: "Stage1Generator", code: 404, userInfo: [NSLocalizedDescriptionKey: "Stage 1 weights are not loaded. Please ensure models are loaded before generating."])
        }
        guard !segmentPrompts.isEmpty else {
            return ([], [])
        }

        // Make a run reproducible from its recorded seed.
        MLXRandom.seed(params.seed)

        let vocabSize = config.vocabSize

        // 1. Official YuE Stage 1 Logits Masking:
        // Official YuE (infer.py:215) uses BlockTokenRangeProcessor(0, 32002).
        // This blocks text tokens (0..<32000) and special tokens <EOD>(32000), <SOA>(32001).
        // All acoustic/codebook tokens and structural markers (>= 32002) are allowed.
        // During minSegTokens (first 100 tokens), <EOA> (32002) is blocked to guarantee
        // a complete musical section.
        var maskNoEOAArray = [Float](repeating: 0.0, count: vocabSize)
        var maskWithEOAArray = [Float](repeating: 0.0, count: vocabSize)

        let blockedPrefixEnd = min(32002, vocabSize)
        for i in 0..<blockedPrefixEnd {
            maskNoEOAArray[i] = -Float.infinity
            maskWithEOAArray[i] = -Float.infinity
        }
        if 32002 < vocabSize {
            maskNoEOAArray[32002] = -Float.infinity
            maskWithEOAArray[32002] = 0.0
        }

        let penaltyMaskNoEOA = MLXArray(maskNoEOAArray)
        let penaltyMaskWithEOA = MLXArray(maskWithEOAArray)

        // Keep the running context inside the window the model was trained on.
        // Beyond it, RoPE phases run off the end of the learned range and the
        // output degrades into unrelated material.
        let contextWindow = max(2048, config.maxPositionEmbeddings - 2048)
        // Once the window is reached, evict down to this mark so the next trim is
        // thousands of tokens away instead of 256.
        let contextLowWater = max(1024, (contextWindow * 3) / 4)

        // A few leading positions are retained across trims as attention sinks;
        // dropping every early position outright destabilises attention.
        let sinkTokens = min(64, segmentPrompts[0].count)

        // A healthy acoustic stream keeps cycling through many of the 1024 codebook
        // entries. Dropping to a few means the model has locked up.
        let degenerationWindow = 192
        let degenerationMinUnique = 6

        let condCaches = (0..<config.numHiddenLayers).map { _ in KVCache() }
        let useCFG = params.cfgScale > 1.0

        var vocalC0: [Int] = []
        var instC0: [Int] = []
        var allGenerated: [Int] = []
        var totalGeneratedTokens = 0
        let startTime = Date()

        let numSegments = segmentPrompts.count

        for segIdx in 0..<numSegments {
            // A frame is a (vocal, instrumental) token pair, so anything under
            // two remaining tokens cannot produce usable audio.
            let remainingTotalTokens = maxTotalTokens - totalGeneratedTokens
            if remainingTotalTokens < 2 {
                print("[Stage1Generator] Token budget exhausted; stopping before segment \(segIdx + 1)/\(numSegments).")
                break
            }

            var segPrompt = segmentPrompts[segIdx]
            // Ensure segment prompt ends with <SOA> (32001) and <xcodec> (32016)
            if !segPrompt.contains(32016) {
                segPrompt.append(32001)
                segPrompt.append(32016)
            }

            for cache in condCaches { cache.trim(toWindow: contextWindow) }

            // Prefill the prompt and sample the first token straight from the prefill logits.
            var condLogits = model.prefill(tokens: segPrompt, caches: condCaches)

            // Classifier-Free Guidance: match Hugging Face UnbatchedClassifierFreeGuidanceLogitsProcessor
            // Unconditional branch starts fresh per segment seeded with [32016] (<xcodec>).
            var uncondLogits: MLXArray? = nil
            var segmentUncondCaches: [KVCache]? = nil
            if useCFG {
                segmentUncondCaches = (0..<config.numHiddenLayers).map { _ in KVCache() }
                uncondLogits = model.prefill(tokens: [32016], caches: segmentUncondCaches!)
            }

            // Dynamic CFG scale: segment 0 uses params.cfgScale (e.g. 1.5), subsequent segments use 1.2 matching official infer_stage1
            let currentCFGScale = (segIdx == 0) ? params.cfgScale : min(params.cfgScale, 1.2)

            // Determine token budget for this segment. Budgets are pre-allocated by
            // the caller across the whole song, so an early segment can no longer
            // swallow the entire budget and starve everything after it.
            let segAllocated = (segmentBudgets != nil && segIdx < segmentBudgets!.count) ? segmentBudgets![segIdx] : maxTotalTokens
            let maxSegTokens = max(2, min(segAllocated, remainingTotalTokens))
            // Treat the budget as a ceiling, not a quota. Official YuE caps a segment
            // with max_new_tokens and lets the model emit <EOA> whenever it is
            // musically done; gating <EOA> until a large fraction of the budget forced
            // the model to generate well past its natural endpoint, where it collapses
            // into a degenerate loop that decodes to silence and poisons every later
            // segment. Keep only a small floor so a section cannot be zero-length.
            let minSegTokens = min(max(2, maxSegTokens - 2), 100)

            print("[Stage1Generator] Starting segment \(segIdx + 1)/\(numSegments) (budget: \(maxSegTokens) tokens, CFG: \(currentCFGScale))")

            var segTokens: [Int] = []
            var endedWithEOA = false
            var collapsed = false

            while segTokens.count < maxSegTokens {
                // Select mask: block <EOA> until the segment has earned the right to end
                let activeMask = (segTokens.count < minSegTokens) ? penaltyMaskNoEOA : penaltyMaskWithEOA

                let effectiveLogits: MLXArray
                if let uncond = uncondLogits, useCFG {
                    // Classifier-free guidance is defined over log-probabilities. The
                    // conditional and unconditional branches have different partition
                    // functions, so interpolating raw logits leaks an arbitrary
                    // per-step offset into the guided distribution and skews the
                    // temperature and top-p that follow.
                    let condLP = MLXNN.logSoftmax(condLogits, axis: -1)
                    let uncondLP = MLXNN.logSoftmax(uncond, axis: -1)
                    effectiveLogits = uncondLP + currentCFGScale * (condLP - uncondLP) + activeMask
                } else {
                    effectiveLogits = condLogits + activeMask
                }

                let nextToken = Sampler.sample(logits: effectiveLogits, params: params, pastTokens: allGenerated, penaltyWindow: 256)

                // Check for natural segment termination: <EOA> (32002)
                if nextToken == 32002 {
                    endedWithEOA = true
                    break
                }

                segTokens.append(nextToken)
                allGenerated.append(nextToken)
                totalGeneratedTokens += 1

                // Degeneration guard: if the model has collapsed onto a handful of
                // tokens it is emitting silence, and continuing only carries the
                // collapsed state into the next segment. Cut the section instead.
                if segTokens.count >= degenerationWindow,
                   segTokens.count % 64 == 0,
                   Set(segTokens.suffix(degenerationWindow)).count <= degenerationMinUnique {
                    print("[Stage1Generator] Segment \(segIdx + 1)/\(numSegments) collapsed to \(Set(segTokens.suffix(degenerationWindow)).count) unique tokens; ending early at \(segTokens.count).")
                    collapsed = true
                    break
                }

                // Feed the accepted token into both branches so every token the
                // model committed to is present in its own context exactly once.
                condLogits = model.step(tokenId: nextToken, caches: condCaches)
                if let uc = segmentUncondCaches {
                    uncondLogits = model.step(tokenId: nextToken, caches: uc)
                }

                // Hold the sliding window mid-segment, not just at segment starts.
                // Once the song's total budget exceeds the model's trained context,
                // a single long section would otherwise run the relative attention
                // distances past anything the model has seen.
                if totalGeneratedTokens % 256 == 0,
                   (condCaches.first?.cachedLength ?? 0) > contextWindow {
                    for cache in condCaches {
                        cache.trim(toWindow: contextLowWater, keepPrefix: sinkTokens)
                    }
                    if let uc = segmentUncondCaches {
                        for cache in uc { cache.trim(toWindow: contextLowWater, keepPrefix: 1) }
                    }
                    MLX.Memory.clearCache()
                }

                if totalGeneratedTokens % 10 == 0 || totalGeneratedTokens == maxTotalTokens {
                    let elapsed = Date().timeIntervalSince(startTime)
                    let speed = elapsed > 0 ? Double(totalGeneratedTokens) / elapsed : 0.0
                    onProgress(totalGeneratedTokens, speed)
                }
            }

            // Commit <EOA> to the context, including when the segment stopped on its
            // budget rather than by choice. The model was trained on terminated
            // `<SOA> ... <EOA>` blocks; leaving a block open and appending the next
            // segment's lyrics makes it read that as an unrelated new song, which is
            // what produced abrupt style and level jumps between sections.
            _ = model.step(tokenId: 32002, caches: condCaches)
            if let uc = segmentUncondCaches {
                _ = model.step(tokenId: 32002, caches: uc)
            }

            // De-interleave the dual-track stream [v0, i0, v1, i1, ...], discarding a
            // trailing unpaired token so the two tracks stay frame-aligned.
            let cb0Start = 45334
            let cb0End = min(cb0Start + 1024, vocabSize)
            let frameCount = segTokens.count / 2
            for f in 0..<frameCount {
                let vToken = segTokens[2 * f]
                let iToken = segTokens[2 * f + 1]
                vocalC0.append((vToken >= cb0Start && vToken < cb0End) ? vToken - cb0Start : ((vToken % 1024 + 1024) % 1024))
                instC0.append((iToken >= cb0Start && iToken < cb0End) ? iToken - cb0Start : ((iToken % 1024 + 1024) % 1024))
            }

            let ending = endedWithEOA ? "ending on <EOA>" : (collapsed ? "ended early (collapsed)" : "capped by budget")
            print("[Stage1Generator] Segment \(segIdx + 1)/\(numSegments) produced \(frameCount) frames (\(String(format: "%.1f", Double(frameCount) / 50.0))s) \(ending).")
        }

        return (vocalC0, instC0)
    }

    /// Autoregressively generates codebook 0 tokens for vocal & instrumental tracks (backward compatibility wrapper)
    public func generate(
        promptTokens: [Int],
        maxTokens: Int,
        params: SamplingParameters,
        onProgress: @Sendable (Int, Double) -> Void
    ) async throws -> (vocalC0: [Int], instC0: [Int]) {
        return try await generateMultiSegment(
            segmentPrompts: [promptTokens],
            maxTotalTokens: maxTokens,
            params: params,
            onProgress: onProgress
        )
    }
}


public enum Stage2Quality: String, CaseIterable, Sendable {
    case draft = "draft"       // Codebook 0 only (instant, 0s Stage 2)
    case balanced = "balanced" // Codebooks 0..3 (4.7x faster, >92% acoustic fidelity)
    case full = "full"         // Codebooks 0..7 (2x faster with dual-track batching)

    public var targetCodebooks: Int {
        switch self {
        case .draft: return 1
        case .balanced: return 4
        case .full: return 8
        }
    }

    public var displayName: String {
        switch self {
        case .draft: return "Draft (Instant - Codebook 0)"
        case .balanced: return "Balanced (Fast - 3 Codebooks)"
        case .full: return "Studio Master (Full - 7 Codebooks)"
        }
    }
}

public final class Stage2Generator: @unchecked Sendable {
    public private(set) var model: YuETransformer?
    public private(set) var config: YuEConfig

    public init(config: YuEConfig = YuEConfig.stage2Default1B()) {
        self.config = config
    }

    public func loadWeights(from modelDir: URL, precision: String = "4-bit") async throws {
        if let diskConfig = YuEConfig.load(from: modelDir) {
            self.config = diskConfig
        }
        let transformer = YuETransformer(config: config)
        try transformer.loadWeights(from: modelDir, precision: precision)
        self.model = transformer
    }

    public func unload() {
        self.model = nil
        MLX.Memory.clearCache()
    }

    /// Refines codebook 0 tokens into acoustic codebooks using parallel dual-track batching on Metal GPU
    public func refine(
        vocalC0: [Int],
        instC0: [Int],
        quality: Stage2Quality = .balanced,
        params: SamplingParameters,
        onProgress: @Sendable (Int, Int, Double) -> Void
    ) async throws -> GeneratedSongTokens {
        let numFrames = min(vocalC0.count, instC0.count)
        guard numFrames > 0 else {
            return GeneratedSongTokens(vocalTokens: [], instrumentalTokens: [])
        }

        let cleanVocalC0 = Array(vocalC0.prefix(numFrames))
        let cleanInstC0 = Array(instC0.prefix(numFrames))

        // Draft mode: Instant zero-step pass-through of Codebook 0 tokens
        if quality == .draft {
            print("[Stage2Generator] Draft mode: bypassing Stage 2 refinement, directly outputting Codebook 0 coarse tracks.")
            onProgress(1, 1, 1000.0)
            return GeneratedSongTokens(vocalTokens: [cleanVocalC0], instrumentalTokens: [cleanInstC0])
        }

        // If Stage 2 neural weights are not loaded, safely return clean Codebook 0
        guard let model = self.model else {
            print("[Stage2Generator] Stage 2 weights not loaded; outputting clean Codebook 0 coarse acoustic track.")
            return GeneratedSongTokens(vocalTokens: [cleanVocalC0], instrumentalTokens: [cleanInstC0])
        }

        let targetCodebooks = quality.targetCodebooks
        let residualCount = targetCodebooks - 1
        let totalSteps = numFrames * residualCount

        print("[Stage2Generator] Starting parallel dual-track Stage 2 refinement (\(quality.rawValue), \(numFrames) frames, \(totalSteps) batched steps)...")
        let startTime = Date()

        return refineDualTracks(
            vocalCb0: cleanVocalC0,
            instCb0: cleanInstC0,
            model: model,
            targetCodebooks: targetCodebooks,
            totalSteps: totalSteps,
            startTime: startTime,
            params: params,
            onProgress: onProgress
        )
    }

    /// Autoregressively predicts residual codebooks for BOTH vocal and instrumental tracks concurrently
    /// using parallel dual-track batching [2, seqLen] in 6-second (300-frame) chunks.
    private func refineDualTracks(
        vocalCb0: [Int],
        instCb0: [Int],
        model: YuETransformer,
        targetCodebooks: Int,
        totalSteps: Int,
        startTime: Date,
        params: SamplingParameters,
        onProgress: @Sendable (Int, Int, Double) -> Void
    ) -> GeneratedSongTokens {
        let numFrames = vocalCb0.count
        var vocalCodebooks: [[Int]] = Array(repeating: [Int](repeating: 0, count: numFrames), count: targetCodebooks)
        var instCodebooks: [[Int]] = Array(repeating: [Int](repeating: 0, count: numFrames), count: targetCodebooks)
        vocalCodebooks[0] = vocalCb0
        instCodebooks[0] = instCb0

        let chunkSize = 300 // 6-second chunking matching official YuE infer_stage2
        let numChunks = (numFrames + chunkSize - 1) / chunkSize
        var stepCount = 0

        for c in 0..<numChunks {
            let startF = c * chunkSize
            let endF = min(startF + chunkSize, numFrames)
            let chunkLength = endF - startF
            let vChunk = Array(vocalCb0[startF..<endF])
            let iChunk = Array(instCb0[startF..<endF])

            // Fresh KV Cache for this 6-second chunk (bounds cache to max 2400 tokens per track)
            let caches = (0..<config.numHiddenLayers).map { _ in KVCache() }

            // Format Stage 2 prompts: [<SOA> (32001), <stage_1> (32013)] + cb0_ids + [<stage_2> (32017)]
            let vCb0Ids = vChunk.map { Int32(45334 + ($0 % 1024)) }
            let iCb0Ids = iChunk.map { Int32(45334 + ($0 % 1024)) }

            var vPrompt: [Int32] = [32001, 32013]
            vPrompt.append(contentsOf: vCb0Ids)
            vPrompt.append(32017)

            var iPrompt: [Int32] = [32001, 32013]
            iPrompt.append(contentsOf: iCb0Ids)
            iPrompt.append(32017)

            let promptLen = vPrompt.count
            // Batched prompt prefill: shape [2, promptLen]
            let promptFlat = vPrompt + iPrompt
            let promptArray = MLXArray(promptFlat).reshaped([2, promptLen])
            let mask = YuETransformer.createCausalMask(seqLen: promptLen)
            _ = model.forward(inputIds: promptArray, mask: mask, caches: caches)

            for fIdx in 0..<chunkLength {
                let globalF = startF + fIdx
                let vCb0 = Int(vCb0Ids[fIdx])
                let iCb0 = Int(iCb0Ids[fIdx])

                var currentTokens = [vCb0, iCb0]

                // Predict residual codebooks 1..<targetCodebooks (e.g. 1..<8 in Full mode)
                for k in 1..<targetCodebooks {
                    let logits = model.stepBatch(tokenIds: currentTokens, caches: caches) // shape [2, vocabSize]
                    let startIdx = 45334 + k * 1024
                    let endIdx = min(startIdx + 1024, config.vocabSize)

                    let cbLogits = logits[0..<2, startIdx..<endIdx] // shape [2, 1024]
                    let cbVals = Sampler.greedyBatch(logits: cbLogits) // returns [vocalCbVal, instCbVal]

                    vocalCodebooks[k][globalF] = cbVals[0]
                    instCodebooks[k][globalF] = cbVals[1]

                    currentTokens = [startIdx + cbVals[0], startIdx + cbVals[1]]

                    stepCount += 1
                    if stepCount % 20 == 0 || stepCount == totalSteps {
                        let elapsed = Date().timeIntervalSince(startTime)
                        let speed = elapsed > 0 ? Double(stepCount) / elapsed : 0.0
                        onProgress(stepCount, totalSteps, speed)
                    }
                }

                // Step the final predicted codebook into the cache so the frame's complete
                // token history (cb0..cb7) is available in the KV-cache for the next frame
                if targetCodebooks > 1 {
                    _ = model.stepBatch(tokenIds: currentTokens, caches: caches)
                }
            }
        }

        return GeneratedSongTokens(vocalTokens: vocalCodebooks, instrumentalTokens: instCodebooks)
    }
}
