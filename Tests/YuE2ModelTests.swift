import XCTest
import MLX
import MLXNN
@testable import Yue2Studio

final class YuE2ModelTests: XCTestCase {
    func test_01_snake_beta_activation() throws {
        let snake = SnakeBeta(channels: 4)
        // Default alpha=0, beta=0 => ea = 1, eb = 1
        // f(x) = x + sin(x)^2 / 1.0
        let input = MLXArray([Float(0.0), Float(0.5), Float(1.0), Float(-0.5)]).reshaped([1, 1, 4])
        let output = snake(input)
        MLX.eval(output)

        let outVals = output.asArray(Float.self)
        let x0: Float = 0.0
        let expected0 = x0 + pow(sin(x0), 2)
        XCTAssertEqual(outVals[0], expected0, accuracy: 1e-4)

        let x1: Float = 0.5
        let expected1 = x1 + pow(sin(x1), 2)
        XCTAssertEqual(outVals[1], expected1, accuracy: 1e-4)

        let x2: Float = 1.0
        let expected2 = x2 + pow(sin(x2), 2)
        XCTAssertEqual(outVals[2], expected2, accuracy: 1e-4)
    }

    func test_02_oobleck_decoder_shape() throws {
        let config = YuE2VAEConfig(
            channels: 16, // Small channels for fast test
            cMults: [1, 2, 4, 8, 16, 32],
            strides: [2, 2, 4, 4, 5, 6],
            latentDim: 64,
            outChannels: 2,
            sampleRate: 48000
        )
        let decoder = OobleckVAEDecoder(config: config)
        // 10 frames of 64-channel latents
        let latents = MLX.zeros([1, 10, 64])
        let output = decoder(latents)
        MLX.eval(output)

        let expectedLen = decoder.outputLength(frames: 10)
        XCTAssertEqual(expectedLen, 19136)
        XCTAssertEqual(output.dim(0), 1)
        XCTAssertEqual(output.dim(1), expectedLen)
        XCTAssertEqual(output.dim(2), 2) // Stereo
    }

    func test_03_timestep_embedder() throws {
        let embedder = YuE2TimestepEmbedder(hiddenSize: 256)
        let t = MLXArray([Float(0.5)])
        let emb = embedder(t)
        MLX.eval(emb)

        XCTAssertEqual(emb.dim(0), 1)
        XCTAssertEqual(emb.dim(1), 256)
    }

    func test_04_flow_matching_timestep_shift() throws {
        let nar = YuE2NARFlowMatching(config: YuE2GeneratorConfig(timestepShift: 3.0))

        // t=0: sigmoid(0) = 0.5 => num = 3*0.5 = 1.5, delta = 2*0.5 = 1.0 => 1.5 / 2.0 = 0.75
        let shifted0 = nar.shiftTimestep(0.0)
        XCTAssertEqual(shifted0, 0.75, accuracy: 1e-3)

        let shiftedHigh = nar.shiftTimestep(10.0)
        XCTAssertEqual(shiftedHigh, 1.0, accuracy: 0.05)

        let shiftedLow = nar.shiftTimestep(-10.0)
        XCTAssertEqual(shiftedLow, 0.0, accuracy: 0.05)
    }

    func test_05_yue2_config_defaults() throws {
        let genConfig = YuE2GeneratorConfig()
        XCTAssertEqual(genConfig.numHiddenLayers, 28)
        XCTAssertEqual(genConfig.hiddenSize, 2048)
        XCTAssertEqual(genConfig.numAttentionHeads, 16)
        XCTAssertEqual(genConfig.numKeyValueHeads, 8)
        XCTAssertEqual(genConfig.headDim, 128)
        XCTAssertEqual(genConfig.latentDim, 64)
        XCTAssertEqual(genConfig.vocabSize, 184704)

        let vaeConfig = YuE2VAEConfig()
        XCTAssertEqual(vaeConfig.latentDim, 64)
        XCTAssertEqual(vaeConfig.sampleRate, 48000)
        XCTAssertEqual(vaeConfig.outChannels, 2)
    }

    func test_06_oobleck_load_weights() throws {
        let vaeDir = URL(fileURLWithPath: "Models/yue2-vae")
        guard FileManager.default.fileExists(atPath: vaeDir.appendingPathComponent("model.safetensors").path) else {
            print("[test_06_oobleck_load_weights] Skipped: Models/yue2-vae/model.safetensors not present on disk")
            return
        }

        let decoder = OobleckVAEDecoder()
        try decoder.loadWeights(from: vaeDir)

        // Test decoding 16 latent frames (equivalent to ~0.64s of audio)
        let latents = MLX.zeros([1, 16, 64])
        let audio = decoder.decode(latents: latents)
        MLX.eval(audio)

        XCTAssertEqual(audio.dim(0), 1)
        XCTAssertEqual(audio.dim(2), 2)
        XCTAssertGreaterThan(audio.dim(1), 0)

        // Verify PCM buffer conversion
        let pcm = decoder.decodeLatentsToPCMBuffer(latents: latents)
        XCTAssertNotNil(pcm)
        XCTAssertEqual(pcm?.format.sampleRate, 48000.0)
        XCTAssertEqual(pcm?.format.channelCount, 2)
    }

    func test_07_nar_load_weights() throws {
        let modelDir = URL(fileURLWithPath: "Models/yue2-3b")
        guard FileManager.default.fileExists(atPath: modelDir.appendingPathComponent("nar-bf16.safetensors").path) else {
            print("[test_07_nar_load_weights] Skipped: Models/yue2-3b/nar-bf16.safetensors not present on disk")
            return
        }

        let nar = YuE2NARFlowMatching()
        try nar.loadWeights(from: modelDir)

        // Solve 4 latent frames for 2 steps
        let latents = nar.solveLatents(frames: 4, numSteps: 2)
        MLX.eval(latents)

        XCTAssertEqual(latents.dim(0), 1)
        XCTAssertEqual(latents.dim(1), 4)
        XCTAssertEqual(latents.dim(2), 64)

        // Verify values are finite numbers and not NaN/Inf
        let floatVals = latents.asArray(Float.self)
        for val in floatVals {
            XCTAssertFalse(val.isNaN)
            XCTAssertFalse(val.isInfinite)
        }
    }

    func test_08_end_to_end_synthesis() throws {
        let vaeDir = URL(fileURLWithPath: "Models/yue2-vae")
        let modelDir = URL(fileURLWithPath: "Models/yue2-3b")
        guard FileManager.default.fileExists(atPath: vaeDir.appendingPathComponent("model.safetensors").path),
              FileManager.default.fileExists(atPath: modelDir.appendingPathComponent("nar-bf16.safetensors").path) else {
            print("[test_08_end_to_end_synthesis] Skipped: Models not present on disk")
            return
        }

        let vae = OobleckVAEDecoder()
        try vae.loadWeights(from: vaeDir)

        let nar = YuE2NARFlowMatching()
        try nar.loadWeights(from: modelDir)

        // 25 frames = 1.0 second at 25 fps, 4 steps
        let latents = nar.solveLatents(frames: 25, numSteps: 4)
        MLX.eval(latents)

        guard let pcm = vae.decodeLatentsToPCMBuffer(latents: latents) else {
            XCTFail("Failed to decode latents to PCM buffer")
            return
        }

        XCTAssertEqual(pcm.format.sampleRate, 48000.0)
        XCTAssertEqual(pcm.format.channelCount, 2)
        XCTAssertGreaterThan(pcm.frameLength, 40000)

        // Verify audio is not silent and not all zero
        let left = pcm.floatChannelData![0]
        var maxAmp: Float = 0.0
        for f in 0..<Int(pcm.frameLength) {
            maxAmp = max(maxAmp, abs(left[f]))
        }
        XCTAssertGreaterThan(maxAmp, 1e-4, "Audio should contain real signal, not silence")
        print("[test_08_end_to_end_synthesis] Successfully synthesized 48kHz audio: frameCount=\(pcm.frameLength), peakAmp=\(maxAmp)")
    }

    func test_09_tokenizer_load_and_encode() throws {
        let tiktokenURL = URL(fileURLWithPath: "Models/yue2-3b/qwen.tiktoken")
        guard FileManager.default.fileExists(atPath: tiktokenURL.path) else {
            print("[test_09_tokenizer_load_and_encode] Skipped: qwen.tiktoken not present on disk")
            return
        }

        let tokenizer = YuE2Tokenizer()
        tokenizer.load(from: tiktokenURL)

        let tokens = tokenizer.encode(text: "Generate music with codec tokens.")
        XCTAssertGreaterThan(tokens.count, 0)
        print("[test_09_tokenizer_load_and_encode] Encoded text into \(tokens.count) tokens: \(tokens)")
    }

    func test_10_ar_load_weights_and_conditioning() throws {
        let modelDir = URL(fileURLWithPath: "Models/yue2-3b")
        guard FileManager.default.fileExists(atPath: modelDir.appendingPathComponent("ar-8bit.safetensors").path) else {
            print("[test_10_ar_load_weights_and_conditioning] Skipped: ar-8bit.safetensors not present on disk")
            return
        }

        let ar = YuE2ARModel()
        try ar.loadWeights(from: modelDir)

        // Compute conditioning cache for a prompt sequence
        let promptTokens = [151643, 2048, 1024, 151847, 151848, 151851]
        let cache = ar.computeConditioningCache(tokenIds: promptTokens)

        XCTAssertEqual(cache.count, 28)
        XCTAssertEqual(cache[0].key.dim(0), 1)
        XCTAssertEqual(cache[0].key.dim(2), promptTokens.count)

        // Generate 2 semantic tokens
        let semanticTokens = ar.generateSemanticTokens(promptTokens: promptTokens, count: 2)
        XCTAssertEqual(semanticTokens.count, 2)
        for tok in semanticTokens {
            XCTAssertGreaterThanOrEqual(tok, 151852)
        }
        print("[test_10_ar_load_weights_and_conditioning] Generated semantic tokens: \(semanticTokens)")
    }

    func test_11_investigate_semantic_tokens() throws {
        let modelDir = URL(fileURLWithPath: "Models/yue2-3b")
        let tiktokenURL = modelDir.appendingPathComponent("qwen.tiktoken")
        let tokenizer = YuE2Tokenizer.shared
        tokenizer.load(from: tiktokenURL)

        let prompt = "female vocal, modern melodic pop, uplifting synth, acoustic guitar, driving drums, 120 bpm"
        let lyrics = "[verse]\nWaking up under morning light\nChasing shadows into the night"
        let (cleanedLyrics, directives) = PromptFormatter.extractDirectivesAndCleanLyrics(lyrics: lyrics)
        let enrichedPrompt = PromptFormatter.enrichGenreTags(genreTags: prompt, lyrics: lyrics, extraDirectives: directives)
        let requestText = "Generate music with codec tokens from the given conditions.\n[Tags]\n\(enrichedPrompt)\n[Lyrics]\n\(cleanedLyrics)\n"
        let tokenizedPrompt = tokenizer.encode(text: requestText)
        let promptTokenIds = [151643] + tokenizedPrompt + [151847, 151848, 151851]

        print("[test_11] promptTokenIds count=\(promptTokenIds.count): \(promptTokenIds)")

        let ar = YuE2ARModel()
        try ar.loadWeights(from: modelDir)

        let tokens = ar.generateSemanticTokens(promptTokens: promptTokenIds, count: 20)
        print("[test_11] generated \(tokens.count) tokens:")
        print(tokens)
    }

    func test_12_grounded_audio_synthesis() async throws {
        let modelDir = URL(fileURLWithPath: "Models/yue2-3b")
        let vaeDir = URL(fileURLWithPath: "Models/yue2-vae")

        let pipeline = YuE2Pipeline()
        let prompt = "female vocal, modern melodic pop, uplifting synth, acoustic guitar, driving drums, 120 bpm"
        let lyrics = "[verse]\nWaking up under morning light\nChasing shadows into the night"

        let starterScore = SymbolicPlanner().generateStarterTemplate(title: "Morning Sun", genreTags: prompt, lyrics: lyrics)

        print("[test_12] Starting grounded song synthesis with 8 flow steps...")
        let buffer = try await pipeline.generateSong(
            prompt: prompt,
            lyrics: lyrics,
            abcScore: starterScore,
            maxTokens: 1200,
            steps: 8,
            temperature: 0.9,
            topP: 0.95,
            cfgScale: 1.0,
            modelDirectory: modelDir,
            vaeDirectory: vaeDir
        ) { progress in
            if progress.totalSteps > 0 {
                print("[\(progress.phase.rawValue)] step \(progress.currentStep)/\(progress.totalSteps): \(progress.statusMessage)")
            } else {
                print("[\(progress.phase.rawValue)] \(progress.statusMessage)")
            }
        }

        let outDir = URL(fileURLWithPath: "Generations")
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let outWav = outDir.appendingPathComponent("song_grounded_yue2.wav")
        try AudioExporter.export(buffer: buffer, to: outWav, format: .wav)

        let frameCount = buffer.frameLength
        let sampleRate = buffer.format.sampleRate
        let duration = Double(frameCount) / sampleRate

        guard let channelData = buffer.floatChannelData else {
            XCTFail("Missing float channel data")
            return
        }

        var peak: Float = 0
        var sumSquares: Float = 0
        for i in 0..<Int(frameCount) {
            let left = channelData[0][i]
            let right = channelData[1][i]
            peak = max(peak, max(abs(left), abs(right)))
            sumSquares += (left * left + right * right) * 0.5
        }
        let rms = sqrt(sumSquares / Float(frameCount))
        let rmsDb = 20 * log10(max(rms, 1e-6))

        print("[test_12] Synthesized audio:")
        print("  - Duration: \(String(format: "%.2f", duration))s (\(frameCount) frames @ \(sampleRate) Hz)")
        print("  - Peak: \(String(format: "%.4f", peak))")
        print("  - RMS: \(String(format: "%.2f", rmsDb)) dBFS")
        print("  - Saved to: \(outWav.path)")

        XCTAssertGreaterThan(duration, 8.0, "Duration should be at least 8 seconds")
        XCTAssertGreaterThan(peak, 0.05, "Peak amplitude should be audible")
        XCTAssertLessThanOrEqual(peak, 1.05, "Peak should not have harsh digital clipping")
    }
}
