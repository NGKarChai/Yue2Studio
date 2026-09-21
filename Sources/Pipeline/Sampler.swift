import Foundation
import MLX
import MLXRandom

public struct SamplingParameters: Sendable {
    public var temperature: Float
    public var topP: Float
    public var cfgScale: Float
    public var repetitionPenalty: Float
    public var seed: UInt64

    public init(
        temperature: Float = 1.0,
        topP: Float = 0.93,
        cfgScale: Float = 1.5,
        repetitionPenalty: Float = 1.1,
        seed: UInt64 = UInt64(Date().timeIntervalSince1970)
    ) {
        self.temperature = temperature
        self.topP = topP
        self.cfgScale = cfgScale
        self.repetitionPenalty = repetitionPenalty
        self.seed = seed
    }
}

public struct Sampler {
    public static func sample(
        logits: MLXArray,
        params: SamplingParameters,
        pastTokens: [Int] = [],
        penaltyWindow: Int = 256
    ) -> Int {
        var scaled = logits

        // 1. Sliding-window repetition penalty (default last 32 tokens)
        // Prevents stuck loops while preserving recurring musical formants and vocal pitches
        if params.repetitionPenalty != 1.0 && !pastTokens.isEmpty {
            let window = pastTokens.suffix(penaltyWindow)
            let maxIndex = scaled.shape[0]
            let uniqueTokens = Array(Set(window)).filter { $0 >= 0 && $0 < maxIndex }.map { Int32($0) }
            if !uniqueTokens.isEmpty {
                let indices = MLXArray(uniqueTokens)
                let selected = scaled[indices]
                let penalized = MLX.where(selected .< 0, selected * params.repetitionPenalty, selected / params.repetitionPenalty)
                scaled[indices] = penalized
            }
        }

        // 2. Temperature scaling
        let temp = max(params.temperature, 1e-4)
        scaled = scaled / temp

        // 3. Top-P (Nucleus) Filtering: cuts off improbable tail tokens to eliminate acoustic noise and static
        if params.topP < 1.0 && params.topP > 0.0 {
            let probs = MLX.softmax(scaled, axis: -1)
            let sortedIndices = MLX.argSort(-probs, axis: -1)
            let sortedProbs = probs[sortedIndices]
            let cumProbs = MLX.cumsum(sortedProbs, axis: -1)

            let numTokens = scaled.shape[0]
            if numTokens > 1 {
                let maskCondition = cumProbs .> params.topP
                let shiftedMask = MLX.concatenated([MLXArray([false]), maskCondition[0..<(numTokens - 1)]], axis: -1)
                let filteredSorted = MLX.where(shiftedMask, MLXArray(-Float.infinity), scaled[sortedIndices])
                let restoreIndices = MLX.argSort(sortedIndices, axis: -1)
                scaled = filteredSorted[restoreIndices]
            }
        }

        // Fast GPU-accelerated categorical sampling
        let sampled = MLXRandom.categorical(scaled.reshaped([1, -1]))
        MLX.eval(sampled)
        return Int(sampled.item(Int32.self))
    }

    /// Deterministic greedy argmax selection for artifact-free Stage 2 residual codebook reconstruction
    public static func greedy(logits: MLXArray) -> Int {
        let maxIdx = logits.argMax()
        MLX.eval(maxIdx)
        return Int(maxIdx.item(UInt32.self))
    }

    /// Parallel greedy argmax selection for batched tracks [B, V] -> [B]
    public static func greedyBatch(logits: MLXArray) -> [Int] {
        let maxIndices = logits.argMax(axis: -1)
        MLX.eval(maxIndices)
        return maxIndices.asArray(UInt32.self).map { Int($0) }
    }
}

