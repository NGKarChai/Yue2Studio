import Foundation

public struct YuE2GeneratorConfig: Codable, Sendable {
    public let hiddenSize: Int
    public let intermediateSize: Int
    public let numHiddenLayers: Int
    public let numAttentionHeads: Int
    public let numKeyValueHeads: Int
    public let headDim: Int
    public let vocabSize: Int
    public let maxPositionEmbeddings: Int
    public let latentDim: Int
    public let maxLatentFrames: Int
    public let rmsNormEps: Float
    public let ropeTheta: Float
    public let timestepShift: Float

    enum CodingKeys: String, CodingKey {
        case hiddenSize = "hidden_size"
        case intermediateSize = "intermediate_size"
        case numHiddenLayers = "num_hidden_layers"
        case numAttentionHeads = "num_attention_heads"
        case numKeyValueHeads = "num_key_value_heads"
        case headDim = "head_dim"
        case vocabSize = "vocab_size"
        case maxPositionEmbeddings = "max_position_embeddings"
        case latentDim = "latent_dim"
        case maxLatentFrames = "max_latent_frames"
        case rmsNormEps = "rms_norm_eps"
        case ropeTheta = "rope_theta"
        case timestepShift = "timestep_shift"
    }

    public init(
        hiddenSize: Int = 2048,
        intermediateSize: Int = 6144,
        numHiddenLayers: Int = 28,
        numAttentionHeads: Int = 16,
        numKeyValueHeads: Int = 8,
        headDim: Int = 128,
        vocabSize: Int = 184704,
        maxPositionEmbeddings: Int = 24576,
        latentDim: Int = 64,
        maxLatentFrames: Int = 8192,
        rmsNormEps: Float = 1e-6,
        ropeTheta: Float = 1000000.0,
        timestepShift: Float = 3.0
    ) {
        self.hiddenSize = hiddenSize
        self.intermediateSize = intermediateSize
        self.numHiddenLayers = numHiddenLayers
        self.numAttentionHeads = numAttentionHeads
        self.numKeyValueHeads = numKeyValueHeads
        self.headDim = headDim
        self.vocabSize = vocabSize
        self.maxPositionEmbeddings = maxPositionEmbeddings
        self.latentDim = latentDim
        self.maxLatentFrames = maxLatentFrames
        self.rmsNormEps = rmsNormEps
        self.ropeTheta = ropeTheta
        self.timestepShift = timestepShift
    }

    public static func load(from url: URL) throws -> YuE2GeneratorConfig {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(YuE2GeneratorConfig.self, from: data)
    }
}

public struct YuE2VAEConfig: Codable, Sendable {
    public let channels: Int
    public let cMults: [Int]
    public let strides: [Int]
    public let latentDim: Int
    public let outChannels: Int
    public let sampleRate: Int
    public let useSnake: Bool
    public let finalTanh: Bool

    enum CodingKeys: String, CodingKey {
        case channels
        case cMults = "c_mults"
        case strides
        case latentDim = "latent_dim"
        case outChannels = "out_channels"
        case sampleRate = "sample_rate"
        case useSnake = "use_snake"
        case finalTanh = "final_tanh"
        case decoderConfig = "decoder_config"
    }

    public init(
        channels: Int = 64,
        cMults: [Int] = [1, 2, 4, 8, 16, 32],
        strides: [Int] = [2, 2, 4, 4, 5, 6],
        latentDim: Int = 64,
        outChannels: Int = 2,
        sampleRate: Int = 48000,
        useSnake: Bool = true,
        finalTanh: Bool = false
    ) {
        self.channels = channels
        self.cMults = cMults
        self.strides = strides
        self.latentDim = latentDim
        self.outChannels = outChannels
        self.sampleRate = sampleRate
        self.useSnake = useSnake
        self.finalTanh = finalTanh
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.decoderConfig) {
            let nested = try container.nestedContainer(keyedBy: CodingKeys.self, forKey: .decoderConfig)
            self.channels = try nested.decodeIfPresent(Int.self, forKey: .channels) ?? 64
            self.cMults = try nested.decodeIfPresent([Int].self, forKey: .cMults) ?? [1, 2, 4, 8, 16, 32]
            self.strides = try nested.decodeIfPresent([Int].self, forKey: .strides) ?? [2, 2, 4, 4, 5, 6]
            self.latentDim = try nested.decodeIfPresent(Int.self, forKey: .latentDim) ?? 64
            self.outChannels = try nested.decodeIfPresent(Int.self, forKey: .outChannels) ?? 2
            self.sampleRate = try container.decodeIfPresent(Int.self, forKey: .sampleRate) ?? 48000
            self.useSnake = try nested.decodeIfPresent(Bool.self, forKey: .useSnake) ?? true
            self.finalTanh = try nested.decodeIfPresent(Bool.self, forKey: .finalTanh) ?? false
        } else {
            self.channels = try container.decodeIfPresent(Int.self, forKey: .channels) ?? 64
            self.cMults = try container.decodeIfPresent([Int].self, forKey: .cMults) ?? [1, 2, 4, 8, 16, 32]
            self.strides = try container.decodeIfPresent([Int].self, forKey: .strides) ?? [2, 2, 4, 4, 5, 6]
            self.latentDim = try container.decodeIfPresent(Int.self, forKey: .latentDim) ?? 64
            self.outChannels = try container.decodeIfPresent(Int.self, forKey: .outChannels) ?? 2
            self.sampleRate = try container.decodeIfPresent(Int.self, forKey: .sampleRate) ?? 48000
            self.useSnake = try container.decodeIfPresent(Bool.self, forKey: .useSnake) ?? true
            self.finalTanh = try container.decodeIfPresent(Bool.self, forKey: .finalTanh) ?? false
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(channels, forKey: .channels)
        try container.encode(cMults, forKey: .cMults)
        try container.encode(strides, forKey: .strides)
        try container.encode(latentDim, forKey: .latentDim)
        try container.encode(outChannels, forKey: .outChannels)
        try container.encode(sampleRate, forKey: .sampleRate)
        try container.encode(useSnake, forKey: .useSnake)
        try container.encode(finalTanh, forKey: .finalTanh)
    }

    public static func load(from url: URL) throws -> YuE2VAEConfig {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(YuE2VAEConfig.self, from: data)
    }
}
