import Foundation
import MLX
import MLXNN
import MLXFast
import MLXRandom

public final class YuE2ARAttention: Module, @unchecked Sendable {
    public let numHeads: Int
    public let numKVHeads: Int
    public let headDim: Int
    public let scale: Float

    @ModuleInfo(key: "q_proj") public var qProj: Linear
    @ModuleInfo(key: "k_proj") public var kProj: Linear
    @ModuleInfo(key: "v_proj") public var vProj: Linear
    @ModuleInfo(key: "o_proj") public var oProj: Linear
    @ModuleInfo(key: "q_norm") public var qNorm: RMSNorm
    @ModuleInfo(key: "k_norm") public var kNorm: RMSNorm

    public init(hiddenSize: Int, numHeads: Int, numKVHeads: Int, headDim: Int, eps: Float) {
        self.numHeads = numHeads
        self.numKVHeads = numKVHeads
        self.headDim = headDim
        self.scale = 1.0 / sqrt(Float(headDim))

        self._qProj.wrappedValue = Linear(hiddenSize, numHeads * headDim, bias: false)
        self._kProj.wrappedValue = Linear(hiddenSize, numKVHeads * headDim, bias: false)
        self._vProj.wrappedValue = Linear(hiddenSize, numKVHeads * headDim, bias: false)
        self._oProj.wrappedValue = Linear(numHeads * headDim, hiddenSize, bias: false)
        self._qNorm.wrappedValue = RMSNorm(dimensions: headDim, eps: eps)
        self._kNorm.wrappedValue = RMSNorm(dimensions: headDim, eps: eps)
    }

    public func computeKV(_ x: MLXArray, cos: MLXArray? = nil, sin: MLXArray? = nil) -> (key: MLXArray, value: MLXArray) {
        let B = x.dim(0)
        let L = x.dim(1)
        var k = kProj(x).reshaped([B, L, numKVHeads, headDim])
        var v = vProj(x).reshaped([B, L, numKVHeads, headDim])
        k = kNorm(k).transposed(0, 2, 1, 3)
        v = v.transposed(0, 2, 1, 3)
        if let c = cos, let s = sin {
            k = YuE2RoPE.applyRoPE(k, cos: c, sin: s)
        }
        return (k, v)
    }

    public func callAsFunction(
        _ x: MLXArray,
        cos: MLXArray? = nil,
        sin: MLXArray? = nil,
        mask: MLXArray? = nil,
        cachedKey: MLXArray? = nil,
        cachedValue: MLXArray? = nil
    ) -> (output: MLXArray, key: MLXArray, value: MLXArray) {
        let B = x.dim(0)
        let L = x.dim(1)

        var q = qProj(x).reshaped([B, L, numHeads, headDim])
        var k = kProj(x).reshaped([B, L, numKVHeads, headDim])
        var v = vProj(x).reshaped([B, L, numKVHeads, headDim])

        q = qNorm(q).transposed(0, 2, 1, 3)
        k = kNorm(k).transposed(0, 2, 1, 3)
        v = v.transposed(0, 2, 1, 3)

        if let c = cos, let s = sin {
            q = YuE2RoPE.applyRoPE(q, cos: c, sin: s)
            k = YuE2RoPE.applyRoPE(k, cos: c, sin: s)
        }

        if let ck = cachedKey, let cv = cachedValue {
            k = MLX.concatenated([ck, k], axis: 2)
            v = MLX.concatenated([cv, v], axis: 2)
        }

        let kExp: MLXArray
        let vExp: MLXArray
        if numHeads != numKVHeads {
            let ratio = numHeads / numKVHeads
            kExp = MLX.repeated(k, count: ratio, axis: 1)
            vExp = MLX.repeated(v, count: ratio, axis: 1)
        } else {
            kExp = k
            vExp = v
        }

        var attnScores = MLX.matmul(q, kExp.transposed(0, 1, 3, 2)) * scale
        if let m = mask {
            attnScores = attnScores + m
        }
        let attnProbs = MLX.softmax(attnScores, axis: -1)
        let out = MLX.matmul(attnProbs, vExp).transposed(0, 2, 1, 3).reshaped([B, L, -1])
        return (oProj(out), k, v)
    }
}

public final class YuE2ARDecoderLayer: Module, @unchecked Sendable {
    @ModuleInfo(key: "input_layernorm") public var inputLayerNorm: RMSNorm
    @ModuleInfo(key: "self_attn") public var selfAttn: YuE2ARAttention
    @ModuleInfo(key: "post_attention_layernorm") public var postAttentionLayerNorm: RMSNorm
    @ModuleInfo(key: "mlp") public var mlp: YuE2AcousticMLP

    public init(config: YuE2GeneratorConfig) {
        self._inputLayerNorm.wrappedValue = RMSNorm(dimensions: config.hiddenSize, eps: config.rmsNormEps)
        self._selfAttn.wrappedValue = YuE2ARAttention(
            hiddenSize: config.hiddenSize,
            numHeads: config.numAttentionHeads,
            numKVHeads: config.numKeyValueHeads,
            headDim: config.headDim,
            eps: config.rmsNormEps
        )
        self._postAttentionLayerNorm.wrappedValue = RMSNorm(dimensions: config.hiddenSize, eps: config.rmsNormEps)
        self._mlp.wrappedValue = YuE2AcousticMLP(
            hiddenSize: config.hiddenSize,
            intermediateSize: config.intermediateSize
        )
    }

    public func callAsFunction(
        _ x: MLXArray,
        cos: MLXArray? = nil,
        sin: MLXArray? = nil,
        mask: MLXArray? = nil,
        cachedKey: MLXArray? = nil,
        cachedValue: MLXArray? = nil
    ) -> (output: MLXArray, key: MLXArray, value: MLXArray) {
        let (attnOut, k, v) = selfAttn(
            inputLayerNorm(x),
            cos: cos,
            sin: sin,
            mask: mask,
            cachedKey: cachedKey,
            cachedValue: cachedValue
        )
        var h = x + attnOut
        h = h + mlp(postAttentionLayerNorm(h))
        return (h, k, v)
    }
}

public final class YuE2ARModel: Module, @unchecked Sendable {
    public let config: YuE2GeneratorConfig
    @ModuleInfo(key: "embed_tokens") public var embedTokens: Embedding
    @ModuleInfo(key: "norm") public var norm: RMSNorm
    @ModuleInfo(key: "lm_head") public var lmHead: Linear
    public var layers: [YuE2ARDecoderLayer]
    public let rope: YuE2RoPE

    public init(config: YuE2GeneratorConfig = YuE2GeneratorConfig()) {
        self.config = config
        self._embedTokens.wrappedValue = Embedding(embeddingCount: config.vocabSize, dimensions: config.hiddenSize)
        self._norm.wrappedValue = RMSNorm(dimensions: config.hiddenSize, eps: config.rmsNormEps)
        self._lmHead.wrappedValue = Linear(config.hiddenSize, config.vocabSize, bias: false)

        var layerList: [YuE2ARDecoderLayer] = []
        for _ in 0..<config.numHiddenLayers {
            layerList.append(YuE2ARDecoderLayer(config: config))
        }
        self.layers = layerList
        self.rope = YuE2RoPE(headDim: config.headDim, base: config.ropeTheta)
    }

    public func callAsFunction(_ tokenIds: MLXArray) -> MLXArray {
        let L = tokenIds.dim(1)
        var h = embedTokens(tokenIds)
        let (cos, sin) = rope.factors(start: 0, length: L)
        let mask = (1.0 - MLX.tri(L)) * -1e9

        for layer in layers {
            let (out, _, _) = layer(h, cos: cos, sin: sin, mask: mask)
            h = out
        }
        h = norm(h)
        return lmHead(h)
    }

    /// Computes key/value conditioning caches for each of the 28 layers
    public func computeConditioningCache(tokenIds: [Int]) -> [(key: MLXArray, value: MLXArray)] {
        let L = tokenIds.count
        guard L > 0 else { return [] }

        let ids = MLXArray(tokenIds.map { Int32($0) }).reshaped([1, L])
        var x = embedTokens(ids)
        let (cos, sin) = rope.factors(start: 0, length: L)
        let mask = (1.0 - MLX.tri(L)) * -1e9

        var cache: [(key: MLXArray, value: MLXArray)] = []
        for layer in layers {
            let (out, k, v) = layer(x, cos: cos, sin: sin, mask: mask)
            cache.append((k, v))
            x = out
            MLX.eval(k, v, x)
        }
        return cache
    }

    /// Predicts next semantic tokens using YuE2's exact sampling rules:
    /// - Candidate slice: [MUSIC_END(151852) ..< CODEC_OFFSET(151853) + CODEC_SIZE(32768)] = 32,769 candidates
    /// - minTokens: masks MUSIC_END until step >= minTokens
    /// - Frequency repetition penalty (window of 50, alpha = penalty^freq)
    /// - Temperature scaling
    /// - Top-K (100) + Top-P (0.95) nucleus filtering
    public func sampleNextSemanticToken(
        logits: MLXArray,
        step: Int = 0,
        recentTokens: [Int] = [],
        temperature: Float = 0.9,
        topP: Float = 0.95,
        topK: Int = 100,
        repetitionPenalty: Float = 1.2,
        penaltyWindow: Int = 50,
        minTokens: Int = 200
    ) -> Int {
        let musicEnd = 151852
        let codecOffset = 151853
        let codecSize = 32768
        let totalCandidates = codecSize + 1 // 32769: index 0 is MUSIC_END, 1..32768 are codec tokens

        let start = musicEnd
        let end = min(codecOffset + codecSize, logits.dim(-1))

        let slice = logits[0..., -1, start..<end].asType(.float32)
        MLX.eval(slice)
        var scores = slice.asArray(Float.self)
        guard scores.count == totalCandidates else {
            // Fallback if dimensions differ
            let sampledLocal = MLXRandom.categorical(MLX.softmax(slice, axis: -1))
            MLX.eval(sampledLocal)
            return start + sampledLocal.item(Int.self)
        }

        // 1. Min tokens constraint: mask MUSIC_END (local index 0)
        if step < minTokens {
            scores[0] = -Float.infinity
        }

        // 2. Sliding window repetition penalty (window of 50, power of frequency)
        if repetitionPenalty != 1.0 && !recentTokens.isEmpty {
            let window = recentTokens.suffix(penaltyWindow)
            var frequencies: [Int: Int] = [:]
            for tok in window {
                let local: Int
                if tok == musicEnd {
                    local = 0
                } else if tok >= codecOffset && tok < codecOffset + codecSize {
                    local = tok - musicEnd
                } else {
                    continue
                }
                if local >= 0 && local < scores.count {
                    frequencies[local, default: 0] += 1
                }
            }

            for (local, count) in frequencies {
                let alpha = pow(repetitionPenalty, Float(count))
                if scores[local] < 0 {
                    scores[local] *= alpha
                } else {
                    scores[local] /= alpha
                }
            }
        }

        // 3. Temperature scaling
        let temp = max(temperature, 1e-4)
        if temp != 1.0 {
            for i in 0..<scores.count {
                scores[i] /= temp
            }
        }

        // 4. Top-K filtering
        let k = min(max(1, topK), scores.count)
        var indexedScores: [(index: Int, score: Float)] = scores.enumerated().map { ($0.offset, $0.element) }
        indexedScores.sort { $0.score > $1.score }
        let topKCandidates = Array(indexedScores.prefix(k))

        // 5. Top-P (Nucleus) filtering on top-K
        let maxScore = topKCandidates[0].score
        let exps = topKCandidates.map { exp($0.score - maxScore) }
        let sumExp = exps.reduce(0, +)
        let probs = exps.map { $0 / max(sumExp, 1e-12) }

        var cumSum: Float = 0.0
        var filteredCount = 0
        for i in 0..<topKCandidates.count {
            cumSum += probs[i]
            filteredCount += 1
            if cumSum >= topP && filteredCount >= 1 {
                break
            }
        }

        let nucleusCandidates = Array(topKCandidates.prefix(filteredCount))
        let nucleusProbs = Array(probs.prefix(filteredCount))
        let nucleusSum = nucleusProbs.reduce(0, +)
        let normProbs = nucleusProbs.map { $0 / max(nucleusSum, 1e-12) }

        // 6. Categorical draw
        let r = Float.random(in: 0..<1.0)
        var accumulated: Float = 0.0
        var chosenLocal = nucleusCandidates[0].index
        for (i, p) in normProbs.enumerated() {
            accumulated += p
            if r < accumulated {
                chosenLocal = nucleusCandidates[i].index
                break
            }
        }

        // 7. Convert local token to native token
        if chosenLocal == 0 {
            return musicEnd
        } else {
            return musicEnd + chosenLocal
        }
    }

    /// Autoregressively generates semantic codec tokens from prompt tokens with full KV caching
    public func generateSemanticTokens(
        promptTokens: [Int],
        count: Int,
        temperature: Float = 0.9,
        topP: Float = 0.95,
        topK: Int = 100,
        repetitionPenalty: Float = 1.2,
        penaltyWindow: Int = 50,
        minTokens: Int = 200,
        onProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) -> [Int] {
        guard !promptTokens.isEmpty else { return [] }

        var currentTokens = promptTokens
        let maxL = promptTokens.count + count + 16
        let (cosFull, sinFull) = rope.factors(start: 0, length: maxL)
        var semanticTokens: [Int] = []

        // Initial prompt prefill with KV caching
        let L = currentTokens.count
        let ids = MLXArray(currentTokens.map { Int32($0) }).reshaped([1, L])
        var x = embedTokens(ids)
        let (cosPrefill, sinPrefill) = (cosFull[0..., 0..., 0..<L, 0...], sinFull[0..., 0..., 0..<L, 0...])
        let mask = (1.0 - MLX.tri(L)) * -1e9

        var kvCaches: [(key: MLXArray, value: MLXArray)] = []
        for layer in layers {
            let (out, k, v) = layer(x, cos: cosPrefill, sin: sinPrefill, mask: mask)
            kvCaches.append((k, v))
            x = out
            MLX.eval(k, v, x)
        }

        let lastIdx = x.dim(1) - 1
        var hLast = norm(x[0..., lastIdx..<x.dim(1), 0...])

        let effectiveMinTokens = min(minTokens, max(1, count / 2))

        for step in 0..<count {
            let logits = lmHead(hLast)
            let nextTok = sampleNextSemanticToken(
                logits: logits,
                step: step,
                recentTokens: semanticTokens,
                temperature: temperature,
                topP: topP,
                topK: topK,
                repetitionPenalty: repetitionPenalty,
                penaltyWindow: penaltyWindow,
                minTokens: effectiveMinTokens
            )
            semanticTokens.append(nextTok)
            currentTokens.append(nextTok)

            onProgress?(step + 1, count)

            if nextTok == 151852 { // MUSIC_END
                break
            }

            let nextId = MLXArray([Int32(nextTok)]).reshaped([1, 1])
            var nextX = embedTokens(nextId)
            let nextPos = currentTokens.count - 1
            if nextPos >= maxL { break }
            let (cosNext, sinNext) = (cosFull[0..., 0..., nextPos..<nextPos+1, 0...], sinFull[0..., 0..., nextPos..<nextPos+1, 0...])

            for (idx, layer) in layers.enumerated() {
                let cached = kvCaches[idx]
                let (out, k, v) = layer(
                    nextX,
                    cos: cosNext,
                    sin: sinNext,
                    mask: nil,
                    cachedKey: cached.key,
                    cachedValue: cached.value
                )
                kvCaches[idx] = (k, v)
                nextX = out
            }
            hLast = norm(nextX)
            MLX.eval(hLast)
        }

        return semanticTokens
    }

    /// Loads 8-bit quantized weights from `ar-8bit.safetensors`
    public func loadWeights(from directory: URL) throws {
        let possibleFilenames = ["ar-8bit.safetensors", "ar.safetensors", "model.safetensors"]
        var weightFile: URL?

        for name in possibleFilenames {
            let candidate = directory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: candidate.path) {
                weightFile = candidate
                break
            }
        }

        guard let url = weightFile else {
            throw NSError(
                domain: "YuE2ARModel",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "No AR safetensors found in \(directory.path)"]
            )
        }

        // Quantize only Linear modules to MLX 8-bit format (groupSize=64, bits=8, affine mode)
        // embed_tokens remains BF16 as in the checkpoint
        MLXNN.quantize(model: self, groupSize: 64, bits: 8, mode: .affine) { _, module in
            module is Linear
        }

        let weights = try MLX.loadArrays(url: url)
        var mappedWeights: [String: MLXArray] = [:]

        for (fullKey, value) in weights {
            var key = fullKey
            if key.hasPrefix("model.") {
                key = String(key.dropFirst("model.".count))
            }
            mappedWeights[key] = value
        }

        let _ = self.update(parameters: ModuleParameters.unflattened(mappedWeights))
        MLX.eval(self.parameters())
        print("[YuE2ARModel] Successfully loaded \(mappedWeights.count) tensors from \(url.lastPathComponent)")
    }
}
