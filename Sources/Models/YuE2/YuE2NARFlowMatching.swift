import Foundation
import MLX
import MLXNN
import MLXFast
import MLXRandom

public final class YuE2TimestepEmbedder: Module, @unchecked Sendable {
    public let embedDim: Int = 256
    public let hiddenSize: Int
    @ModuleInfo(key: "mlp0") public var mlp0: Linear
    @ModuleInfo(key: "mlp2") public var mlp2: Linear

    private let frequencies: MLXArray

    public init(hiddenSize: Int) {
        self.hiddenSize = hiddenSize
        self._mlp0.wrappedValue = Linear(embedDim, hiddenSize)
        self._mlp2.wrappedValue = Linear(hiddenSize, hiddenSize)

        let half = embedDim / 2
        var freqs = [Float](repeating: 0, count: half)
        let logBase = -log(10000.0)
        for i in 0..<half {
            freqs[i] = exp(Float(logBase) * Float(i) / Float(half))
        }
        self.frequencies = MLXArray(freqs)
    }

    public func callAsFunction(_ timestep: Float) -> MLXArray {
        let t = MLXArray([timestep]).reshaped([1, 1])
        return computeEmbedding(t)
    }

    public func callAsFunction(_ timestep: MLXArray) -> MLXArray {
        let t = timestep.reshaped([-1, 1])
        return computeEmbedding(t)
    }

    private func computeEmbedding(_ t: MLXArray) -> MLXArray {
        let freqs = frequencies.reshaped([1, -1])
        let args = t * freqs
        let cosPart = MLX.cos(args)
        let sinPart = MLX.sin(args)
        let emb = MLX.concatenated([cosPart, sinPart], axis: -1)

        var h = mlp0(emb)
        h = MLXNN.silu(h)
        return mlp2(h)
    }
}

public final class YuE2AudioPositionEmbedding: Module, @unchecked Sendable {
    @ParameterInfo(key: "pe") public var pe: MLXArray

    public init(maxFrames: Int, hiddenSize: Int) {
        self._pe.wrappedValue = MLXArray.zeros([maxFrames, hiddenSize])
    }

    public func callAsFunction(_ positionIds: MLXArray) -> MLXArray {
        return pe[positionIds]
    }
}

public final class YuE2RoPE: @unchecked Sendable {
    public let headDim: Int
    public let invFreq: MLXArray

    public init(headDim: Int = 128, base: Float = 1000000.0) {
        self.headDim = headDim
        let half = headDim / 2
        var freqs = [Float](repeating: 0, count: half)
        for i in 0..<half {
            let expVal = Float(i * 2) / Float(headDim)
            freqs[i] = 1.0 / pow(base, expVal)
        }
        self.invFreq = MLXArray(freqs)
    }

    public func factors(start: Int, length: Int) -> (cos: MLXArray, sin: MLXArray) {
        let positions = MLXArray(Int32(start)..<Int32(start + length)).asType(.float32).reshaped([-1, 1])
        let freqs = invFreq.reshaped([1, -1])
        let angles = positions * freqs
        let cos = MLX.cos(angles).reshaped([1, 1, length, headDim / 2])
        let sin = MLX.sin(angles).reshaped([1, 1, length, headDim / 2])
        return (cos, sin)
    }

    public static func applyRoPE(_ x: MLXArray, cos: MLXArray, sin: MLXArray) -> MLXArray {
        let half = x.dim(-1) / 2
        let first = x[0..., 0..., 0..., 0..<half]
        let second = x[0..., 0..., 0..., half...]
        let rotatedFirst = first * cos - second * sin
        let rotatedSecond = second * cos + first * sin
        return MLX.concatenated([rotatedFirst, rotatedSecond], axis: -1)
    }
}

public final class YuE2AcousticAttention: Module, @unchecked Sendable {
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

    public func callAsFunction(
        _ x: MLXArray,
        cos: MLXArray? = nil,
        sin: MLXArray? = nil,
        cachedKey: MLXArray? = nil,
        cachedValue: MLXArray? = nil
    ) -> MLXArray {
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

        // Expand KV heads if GQA
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

        let attnScores = MLX.matmul(q, kExp.transposed(0, 1, 3, 2)) * scale
        let attnProbs = MLX.softmax(attnScores, axis: -1)
        let out = MLX.matmul(attnProbs, vExp).transposed(0, 2, 1, 3).reshaped([B, L, -1])
        return oProj(out)
    }
}

public final class YuE2AcousticMLP: Module, @unchecked Sendable {
    @ModuleInfo(key: "gate_proj") public var gateProj: Linear
    @ModuleInfo(key: "up_proj") public var upProj: Linear
    @ModuleInfo(key: "down_proj") public var downProj: Linear

    public init(hiddenSize: Int, intermediateSize: Int) {
        self._gateProj.wrappedValue = Linear(hiddenSize, intermediateSize, bias: false)
        self._upProj.wrappedValue = Linear(hiddenSize, intermediateSize, bias: false)
        self._downProj.wrappedValue = Linear(intermediateSize, hiddenSize, bias: false)
    }

    public func callAsFunction(_ x: MLXArray) -> MLXArray {
        return downProj(MLXNN.silu(gateProj(x)) * upProj(x))
    }
}

public final class YuE2AcousticLayer: Module, @unchecked Sendable {
    @ModuleInfo(key: "nar_input_layernorm") public var inputLayerNorm: RMSNorm
    @ModuleInfo(key: "nar_self_attn") public var selfAttn: YuE2AcousticAttention
    @ModuleInfo(key: "nar_pre_mlp_layernorm") public var preMlpLayerNorm: RMSNorm
    @ModuleInfo(key: "nar_mlp") public var mlp: YuE2AcousticMLP

    public init(config: YuE2GeneratorConfig) {
        self._inputLayerNorm.wrappedValue = RMSNorm(dimensions: config.hiddenSize, eps: config.rmsNormEps)
        self._selfAttn.wrappedValue = YuE2AcousticAttention(
            hiddenSize: config.hiddenSize,
            numHeads: config.numAttentionHeads,
            numKVHeads: config.numKeyValueHeads,
            headDim: config.headDim,
            eps: config.rmsNormEps
        )
        self._preMlpLayerNorm.wrappedValue = RMSNorm(dimensions: config.hiddenSize, eps: config.rmsNormEps)
        self._mlp.wrappedValue = YuE2AcousticMLP(
            hiddenSize: config.hiddenSize,
            intermediateSize: config.intermediateSize
        )
    }

    public func callAsFunction(
        _ x: MLXArray,
        cos: MLXArray? = nil,
        sin: MLXArray? = nil,
        cachedKey: MLXArray? = nil,
        cachedValue: MLXArray? = nil
    ) -> MLXArray {
        let normX = inputLayerNorm(x)
        let attnOut = selfAttn(normX, cos: cos, sin: sin, cachedKey: cachedKey, cachedValue: cachedValue)
        var h = x + attnOut
        let normH = preMlpLayerNorm(h)
        h = h + mlp(normH)
        return h
    }
}

public final class YuE2NARFlowMatching: Module, @unchecked Sendable {
    public let config: YuE2GeneratorConfig
    @ModuleInfo(key: "llm2vae") public var llm2vae: Linear
    @ModuleInfo(key: "vae2llm") public var vae2llm: Linear
    @ModuleInfo(key: "time_embedder") public var timeEmbedder: YuE2TimestepEmbedder
    @ModuleInfo(key: "latent_pos_embed") public var latentPosEmbed: YuE2AudioPositionEmbedding
    @ModuleInfo(key: "norm") public var norm: RMSNorm
    public var layers: [YuE2AcousticLayer]
    public let rope: YuE2RoPE

    public init(config: YuE2GeneratorConfig = YuE2GeneratorConfig()) {
        self.config = config
        self._llm2vae.wrappedValue = Linear(config.hiddenSize, config.latentDim)
        self._vae2llm.wrappedValue = Linear(config.latentDim, config.hiddenSize)
        self._timeEmbedder.wrappedValue = YuE2TimestepEmbedder(hiddenSize: config.hiddenSize)
        self._latentPosEmbed.wrappedValue = YuE2AudioPositionEmbedding(
            maxFrames: config.maxLatentFrames,
            hiddenSize: config.hiddenSize
        )
        self._norm.wrappedValue = RMSNorm(dimensions: config.hiddenSize, eps: config.rmsNormEps)

        var layerList: [YuE2AcousticLayer] = []
        for _ in 0..<config.numHiddenLayers {
            layerList.append(YuE2AcousticLayer(config: config))
        }
        self.layers = layerList
        self.rope = YuE2RoPE(headDim: config.headDim, base: config.ropeTheta)
    }

    /// Shift timestep according to YuE2 sigmoid warping schedule
    public func shiftTimestep(_ rawT: Float) -> Float {
        let sig = 1.0 / (1.0 + exp(-rawT))
        let num = config.timestepShift * sig
        let delta = (config.timestepShift - 1.0) * sig
        return num / (1.0 + delta)
    }

    /// Reference _logit function for flow matching time schedule
    public static func logit(_ t: Float) -> Float {
        if t <= 0.0 { return -20.0 }
        if t >= 1.0 { return 20.0 }
        let val = log(t / (1.0 - t))
        return max(-20.0, min(20.0, val))
    }

    /// Evaluates latent velocity v_t = d(x_t)/dt with boundary padding
    public func forwardVelocity(
        latents: MLXArray,
        rawT: Float,
        cos: MLXArray? = nil,
        sin: MLXArray? = nil,
        conditioningCache: [(key: MLXArray, value: MLXArray)]? = nil
    ) -> MLXArray {
        // latents: [1, T, 64]
        let T = latents.dim(1)

        // Boundary padding: pad with 1 start frame and 1 end frame
        let zeroStart = MLXArray.zeros([1, 1, config.latentDim])
        let zeroEnd = MLXArray.zeros([1, 1, config.latentDim])
        let boundaryState = MLX.concatenated([zeroStart, latents, zeroEnd], axis: 1)
        let totalFrames = boundaryState.dim(1)

        var h = vae2llm(boundaryState)

        // Add shifted timestep embedding
        let shiftedT = shiftTimestep(rawT)
        let tEmb = timeEmbedder(shiftedT).reshaped([1, 1, config.hiddenSize])
        h = h + tEmb

        // Add positional embeddings
        let posIds = MLXArray(0..<Int32(min(totalFrames, config.maxLatentFrames)))
        let posEmb = latentPosEmbed(posIds).reshaped([1, totalFrames, config.hiddenSize])
        h = h + posEmb

        // Forward through NAR acoustic backbone
        for (idx, layer) in layers.enumerated() {
            let cond = (conditioningCache != nil && idx < conditioningCache!.count) ? conditioningCache![idx] : nil
            h = layer(h, cos: cos, sin: sin, cachedKey: cond?.key, cachedValue: cond?.value)
        }

        h = norm(h)
        let fullVelocity = llm2vae(h)

        // Strip boundary frames [1..<(totalFrames - 1)] to return [1, T, 64]
        return fullVelocity[0..., 1..<(totalFrames - 1), 0...]
    }

    /// Solves the ODE from t=1.0 to t=0.0 using Midpoint Euler solver
    public func solveLatents(
        frames: Int,
        numSteps: Int = 32,
        conditioningCache: [(key: MLXArray, value: MLXArray)]? = nil,
        conditioningLength: Int = 0,
        onProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) -> MLXArray {
        // Initial Gaussian noise x_0 ~ N(0, I)
        var state = MLXRandom.normal([1, frames, config.latentDim])

        let narLength = frames + 2
        let (cos, sin) = rope.factors(start: conditioningLength, length: narLength)

        let dt = 1.0 / Float(numSteps)
        let halfDt = dt / 2.0

        for step in 0..<numSteps {
            let t = 1.0 - (Float(step) * dt)
            let rawT = Self.logit(t)

            // Midpoint step 1: velocity at t
            let v1 = forwardVelocity(
                latents: state,
                rawT: rawT,
                cos: cos,
                sin: sin,
                conditioningCache: conditioningCache
            )
            let midpoint = state - (v1 * halfDt)

            // Midpoint step 2: velocity at t - dt/2
            let midT = t - halfDt
            let rawMidT = Self.logit(midT)
            let v2 = forwardVelocity(
                latents: midpoint,
                rawT: rawMidT,
                cos: cos,
                sin: sin,
                conditioningCache: conditioningCache
            )

            // Advance state: state = state - v2 * dt
            state = state - (v2 * dt)
            MLX.eval(state)

            onProgress?(step + 1, numSteps)
        }

        return state
    }

    /// Loads weights from directory containing `nar-bf16.safetensors`
    public func loadWeights(from directory: URL) throws {
        let possibleFilenames = ["nar-bf16.safetensors", "nar.safetensors", "model.safetensors"]
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
                domain: "YuE2NARFlowMatching",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "No NAR safetensors found in \(directory.path)"]
            )
        }

        let weights = try MLX.loadArrays(url: url)
        var mappedWeights: [String: MLXArray] = [:]

        for (fullKey, value) in weights {
            var key = fullKey
            if key.hasPrefix("model.layers.") {
                // Drop "model." so it becomes "layers.0..."
                key = String(key.dropFirst("model.".count))
            } else if key == "time_embedder.mlp.0.weight" {
                key = "time_embedder.mlp0.weight"
            } else if key == "time_embedder.mlp.0.bias" {
                key = "time_embedder.mlp0.bias"
            } else if key == "time_embedder.mlp.2.weight" {
                key = "time_embedder.mlp2.weight"
            } else if key == "time_embedder.mlp.2.bias" {
                key = "time_embedder.mlp2.bias"
            }
            mappedWeights[key] = value
        }

        // Check if AR weights have model.norm.weight to populate norm
        let arCandidate = directory.appendingPathComponent("ar-8bit.safetensors")
        if FileManager.default.fileExists(atPath: arCandidate.path) {
            if let arWeights = try? MLX.loadArrays(url: arCandidate),
               let normWeight = arWeights["model.norm.weight"] {
                mappedWeights["norm.weight"] = normWeight
            }
        }

        let _ = self.update(parameters: ModuleParameters.unflattened(mappedWeights))
        MLX.eval(self.parameters())
        print("[YuE2NARFlowMatching] Successfully loaded \(mappedWeights.count) tensors from \(url.lastPathComponent)")
    }
}
