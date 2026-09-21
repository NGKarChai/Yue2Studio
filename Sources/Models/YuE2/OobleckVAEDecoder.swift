import Foundation
import MLX
import MLXNN
import AVFoundation

public final class SnakeBeta: Module, @unchecked Sendable {
    @ParameterInfo(key: "alpha") public var alpha: MLXArray
    @ParameterInfo(key: "beta") public var beta: MLXArray

    public init(channels: Int) {
        self._alpha.wrappedValue = MLXArray.zeros([channels])
        self._beta.wrappedValue = MLXArray.zeros([channels])
    }

    public func callAsFunction(_ x: MLXArray) -> MLXArray {
        let ea = MLX.exp(self.alpha)
        let eb = MLX.exp(self.beta)
        let s = MLX.sin(x * ea)
        return x + (s * s) / (eb + 1e-9)
    }
}

public final class OobleckResidualUnit: Module, @unchecked Sendable {
    public let dilation: Int
    public var layers: [Module]

    public init(channels: Int, dilation: Int) {
        self.dilation = dilation
        self.layers = [
            SnakeBeta(channels: channels),
            Conv1d(
                inputChannels: channels,
                outputChannels: channels,
                kernelSize: 7,
                stride: 1,
                padding: 3 * dilation,
                dilation: dilation
            ),
            SnakeBeta(channels: channels),
            Conv1d(
                inputChannels: channels,
                outputChannels: channels,
                kernelSize: 1,
                stride: 1,
                padding: 0
            )
        ]
    }

    public func callAsFunction(_ x: MLXArray) -> MLXArray {
        var y = x
        for layer in layers {
            if let l = layer as? SnakeBeta {
                y = l(y)
            } else if let l = layer as? Conv1d {
                y = l(y)
            }
        }
        return x + y
    }
}

public final class OobleckDecoderBlock: Module, @unchecked Sendable {
    public let stride: Int
    public var layers: [Module]

    public init(cin: Int, cout: Int, stride: Int) {
        self.stride = stride
        let pad = Int(ceil(Double(stride) / 2.0))
        self.layers = [
            SnakeBeta(channels: cin),
            ConvTransposed1d(
                inputChannels: cin,
                outputChannels: cout,
                kernelSize: 2 * stride,
                stride: stride,
                padding: pad
            ),
            OobleckResidualUnit(channels: cout, dilation: 1),
            OobleckResidualUnit(channels: cout, dilation: 3),
            OobleckResidualUnit(channels: cout, dilation: 9)
        ]
    }

    public func callAsFunction(_ x: MLXArray) -> MLXArray {
        var h = x
        for layer in layers {
            if let l = layer as? SnakeBeta {
                h = l(h)
            } else if let l = layer as? ConvTransposed1d {
                h = l(h)
            } else if let l = layer as? OobleckResidualUnit {
                h = l(h)
            }
        }
        return h
    }
}

public final class OobleckVAEDecoder: Module, @unchecked Sendable {
    public let config: YuE2VAEConfig
    public var layers: [Module]

    public init(config: YuE2VAEConfig = YuE2VAEConfig()) {
        self.config = config
        let c = config.channels
        let mults = [1] + config.cMults
        let strides = config.strides

        var layerList: [Module] = []
        // Layer 0: Conv1d from latentDim to mults.last * c
        layerList.append(Conv1d(
            inputChannels: config.latentDim,
            outputChannels: mults[mults.count - 1] * c,
            kernelSize: 7,
            stride: 1,
            padding: 3
        ))

        // Layers 1..6: DecoderBlocks (reversed strides)
        for i in stride(from: mults.count - 1, through: 1, by: -1) {
            let cin = mults[i] * c
            let cout = mults[i - 1] * c
            let st = strides[i - 1]
            layerList.append(OobleckDecoderBlock(cin: cin, cout: cout, stride: st))
        }

        // Layer 7: Final SnakeBeta activation
        layerList.append(SnakeBeta(channels: c))

        // Layer 8: Final Conv1d to outChannels (bias: false)
        layerList.append(Conv1d(
            inputChannels: c,
            outputChannels: config.outChannels,
            kernelSize: 7,
            stride: 1,
            padding: 3,
            bias: false
        ))

        self.layers = layerList
    }

    public func callAsFunction(_ x: MLXArray) -> MLXArray {
        var h = x
        for layer in layers {
            if let l = layer as? Conv1d {
                h = l(h)
            } else if let l = layer as? OobleckDecoderBlock {
                h = l(h)
            } else if let l = layer as? SnakeBeta {
                h = l(h)
            }
        }
        if config.finalTanh {
            h = MLX.tanh(h)
        }
        return h
    }

    /// Exact output audio length following Oobleck stride parity:
    /// frames = frames * stride - (stride % 2) for each stride
    public func outputLength(frames: Int) -> Int {
        var f = frames
        let revStrides = Array(config.strides.reversed())
        for stride in revStrides {
            f = f * stride - (stride % 2)
        }
        return f
    }

    /// Tiled audio decoding with halo boundary handling
    public func decode(
        latents: MLXArray,
        coreFrames: Int = 256,
        haloFrames: Int = 16,
        onProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) -> MLXArray {
        let totalLatentFrames = latents.dim(1)
        if totalLatentFrames <= coreFrames {
            let out = self(latents)
            MLX.eval(out)
            return out
        }

        let ratio = config.strides.reduce(1, *)
        let totalSamples = outputLength(frames: totalLatentFrames)
        var pieces: [MLXArray] = []
        let chunkCount = Int(ceil(Double(totalLatentFrames) / Double(coreFrames)))

        for (idx, start) in stride(from: 0, to: totalLatentFrames, by: coreFrames).enumerated() {
            let end = min(totalLatentFrames, start + coreFrames)
            let left = max(0, start - haloFrames)
            let right = min(totalLatentFrames, end + haloFrames)

            let slice = latents[0..., left..<right, 0...]
            let tile = self(slice)
            MLX.eval(tile)

            let offset = (start - left) * ratio
            let targetLen = min(end * ratio, totalSamples) - start * ratio
            let piece = tile[0..., offset..<(offset + targetLen), 0...]
            pieces.append(piece)

            onProgress?(idx + 1, chunkCount)
        }

        let result = MLX.concatenated(pieces, axis: 1)
        MLX.eval(result)
        return result
    }

    /// Decodes 64-channel latents to AVAudioPCMBuffer (48 kHz stereo)
    public func decodeLatentsToPCMBuffer(
        latents: MLXArray,
        onProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) -> AVAudioPCMBuffer? {
        let audioTensor = decode(latents: latents, onProgress: onProgress)
        MLX.eval(audioTensor)

        let totalFrames = audioTensor.dim(1)
        let channels = audioTensor.dim(2)
        guard totalFrames > 0, channels >= 2 else { return nil }

        guard let format = AVAudioFormat(standardFormatWithSampleRate: Double(config.sampleRate), channels: 2),
              let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(totalFrames)) else {
            return nil
        }
        pcmBuffer.frameLength = AVAudioFrameCount(totalFrames)

        let floatData = audioTensor.asArray(Float.self)
        guard let leftChannel = pcmBuffer.floatChannelData?[0],
              let rightChannel = pcmBuffer.floatChannelData?[1] else {
            return nil
        }

        // De-interleave [totalFrames, 2]
        for f in 0..<totalFrames {
            leftChannel[f] = floatData[f * 2]
            rightChannel[f] = floatData[f * 2 + 1]
        }

        return pcmBuffer
    }

    /// Loads weights from a directory containing `model.safetensors` or `vae.safetensors`,
    /// performing PyTorch Weight-Norm folding and convolution weight transposition.
    public func loadWeights(from directory: URL) throws {
        let possibleFilenames = ["model.safetensors", "vae.safetensors", "decoder.safetensors"]
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
                domain: "OobleckVAEDecoder",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "No VAE safetensors found in \(directory.path)"]
            )
        }

        let weights = try MLX.loadArrays(url: url)
        var mappedWeights: [String: MLXArray] = [:]

        for (fullKey, value) in weights {
            guard fullKey.hasPrefix("decoder.") else { continue }
            if fullKey.hasSuffix(".weight_g") { continue }

            var key = String(fullKey.dropFirst("decoder.".count))

            if key.hasSuffix(".weight_v") {
                let gKey = String(fullKey.dropLast(1)) + "g"
                guard let gain = weights[gKey] else {
                    throw NSError(
                        domain: "OobleckVAEDecoder",
                        code: 400,
                        userInfo: [NSLocalizedDescriptionKey: "Missing weight_g for \(fullKey)"]
                    )
                }

                // Weight norm folding: W = v * (g / ||v||)
                let norm = MLX.sqrt(MLX.sum(value * value, axes: [1, 2], keepDims: true))
                var folded = value * (gain / (norm + 1e-12))

                // ConvTranspose is the second module directly inside each decoder block:
                // key looks like: layers.<block_idx>.layers.1.weight_v
                let parts = key.split(separator: ".")
                let isConvTranspose = (parts.count == 5 && parts[2] == "layers" && parts[3] == "1")

                if isConvTranspose {
                    // PyTorch [Cin, Cout, K] -> MLX [Cout, K, Cin]
                    folded = folded.transposed(1, 2, 0)
                } else {
                    // PyTorch [Cout, Cin, K] -> MLX [Cout, K, Cin]
                    folded = folded.transposed(0, 2, 1)
                }

                key = String(key.dropLast("_v".count))
                mappedWeights[key] = folded
            } else {
                mappedWeights[key] = value
            }
        }

        let _ = self.update(parameters: ModuleParameters.unflattened(mappedWeights))
        MLX.eval(self.parameters())
        print("[OobleckVAEDecoder] Successfully loaded and folded \(mappedWeights.count) tensors from \(url.lastPathComponent)")
    }
}
