import Foundation
import AVFoundation
import Accelerate
import MLX

public enum PipelinePhase: String, Sendable {
    case idle = "Idle"
    case loadingModels = "Loading Models"
    case stage1Generating = "Stage 1: Generating Coarse Tokens"
    case stage2Refining = "Stage 2: Acoustic Refinement"
    case decodingAudio = "Stage 3: X-Codec Neural Synthesis"
    case complete = "Completed"
    case failed = "Failed"
}

public struct PipelineProgress: Sendable {
    public let phase: PipelinePhase
    public let progressFraction: Double
    public let currentStep: Int
    public let totalSteps: Int
    public let speed: Double
    public let statusMessage: String

    public init(
        phase: PipelinePhase = .idle,
        progressFraction: Double = 0.0,
        currentStep: Int = 0,
        totalSteps: Int = 0,
        speed: Double = 0.0,
        statusMessage: String = ""
    ) {
        self.phase = phase
        self.progressFraction = progressFraction
        self.currentStep = currentStep
        self.totalSteps = totalSteps
        self.speed = speed
        self.statusMessage = statusMessage
    }
}

public actor YuEPipeline {
    private let tokenizer: YuETokenizer
    private let stage1: Stage1Generator
    private let stage2: Stage2Generator
    private let decoder: XCodecDecoder

    private var isCancelled: Bool = false

    public init() {
        self.tokenizer = YuETokenizer()
        self.stage1 = Stage1Generator()
        self.stage2 = Stage2Generator()
        self.decoder = XCodecDecoder()
    }

    public func cancel() {
        self.isCancelled = true
    }

    /// Primary async generation entrypoint
    public func generateSong(
        genreTags: String,
        lyrics: String,
        scoreABC: String? = nil,
        cotMode: String? = nil,
        modelsDir: URL,
        maxTokens: Int = 600,
        params: SamplingParameters = SamplingParameters(),
        precision: String = "4-bit",
        stage2Quality: Stage2Quality = .full,
        referenceAudioURL: URL? = nil,
        referenceMode: ReferenceMode = .melodyOnly,
        referencePrompt: String? = nil,
        autoUnloadStage1: Bool = true,
        stereoWidth: Double = 0.5,
        applyMastering: Bool = true,
        upsampleEnabled: Bool = true,
        levelingEnabled: Bool = true,
        progressHandler: @Sendable @escaping (PipelineProgress) -> Void
    ) async throws -> AVAudioPCMBuffer {
        self.isCancelled = false

        // 1. Loading / Preparing
        progressHandler(PipelineProgress(
            phase: .loadingModels,
            progressFraction: 0.03,
            statusMessage: "Initializing tokenizers and verifying weight paths..."
        ))

        // YuE ships one Stage 1 checkpoint per language and they are not
        // interchangeable: an English model cannot sing Chinese lyrics, and asking
        // it to produces wandering, lyric-less sections. Pick the checkpoint that
        // matches the lyrics when one is installed.
        let lyricLanguage = PromptFormatter.detectLanguage(text: lyrics)
        let (stage1Dir, modelLanguage) = YuEPipeline.selectStage1Directory(
            modelsDir: modelsDir, lyricLanguage: lyricLanguage
        )
        if modelLanguage != lyricLanguage {
            print("[YuEPipeline] WARNING: lyrics look like '\(lyricLanguage)' but the loaded Stage 1 model is '\(modelLanguage)'. Vocals will not match the lyrics. Install the matching checkpoint for proper results.")
        } else {
            print("[YuEPipeline] Using Stage 1 checkpoint '\(stage1Dir.lastPathComponent)' for '\(lyricLanguage)' lyrics.")
        }

        await tokenizer.load(from: stage1Dir)
        if isCancelled { throw CancellationError() }

        // Load Stage 1 weights and quantize on Metal GPU
        progressHandler(PipelineProgress(
            phase: .loadingModels,
            progressFraction: 0.07,
            statusMessage: "Loading & quantizing Stage 1 weights (\(precision))..."
        ))
        try await stage1.loadWeights(from: stage1Dir, precision: precision)
        if isCancelled { throw CancellationError() }

        // 2. Prepare structured multi-segment prompts and adaptive budgets
        let segments = PromptFormatter.prepareOrderedSegments(lyrics: lyrics)
        print("[YuEPipeline] Prepared \(segments.count) structured lyric segment(s) for autoregressive generation.")

        var segmentTokenPrompts: [[Int]] = []

        for (idx, seg) in segments.enumerated() {
            let promptText: String
            if idx == 0 {
                promptText = PromptFormatter.formatSegment0Prompt(
                    genreTags: genreTags,
                    lyrics: lyrics,
                    firstSegment: seg,
                    scoreABC: scoreABC,
                    cotMode: cotMode,
                    referencePrompt: referencePrompt,
                    referenceMode: referenceMode,
                    modelLanguage: modelLanguage
                )
            } else {
                promptText = PromptFormatter.formatNextSegmentPrompt(segment: seg)
            }
            let encodedTokens = tokenizer.encode(text: promptText, addBOS: (idx == 0))
            segmentTokenPrompts.append(encodedTokens)
        }

        let segmentBudgets = YuEPipeline.allocateSegmentBudgets(segments: segments, totalTokens: maxTokens)
        for (idx, seg) in segments.enumerated() {
            let tag = seg.split(separator: "\n").first.map(String.init) ?? "[?]"
            print(String(format: "[YuEPipeline] Segment %d %@: %d tokens (~%.1fs)",
                         idx + 1, tag, segmentBudgets[idx], Double(segmentBudgets[idx]) / 100.0))
        }

        // 3. Stage 1: Coarse Generation
        progressHandler(PipelineProgress(
            phase: .stage1Generating,
            progressFraction: 0.1,
            totalSteps: maxTokens,
            statusMessage: "Generating dual-track audio tokens across \(segments.count) segment(s)..."
        ))

        let (vocalC0, instC0) = try await stage1.generateMultiSegment(
            segmentPrompts: segmentTokenPrompts,
            maxTotalTokens: maxTokens,
            segmentBudgets: segmentBudgets,
            params: params
        ) { step, speed in
            let frac = 0.1 + (Double(step) / Double(maxTokens)) * 0.4
            progressHandler(PipelineProgress(
                phase: .stage1Generating,
                progressFraction: frac,
                currentStep: step,
                totalSteps: maxTokens,
                speed: speed,
                statusMessage: String(format: "Stage 1: %d/%d tokens (%.1f tok/s)", step, maxTokens, speed)
            ))
        }

        if isCancelled { throw CancellationError() }

        // Memory optimization: clear cache & optionally unload Stage 1
        MLX.Memory.clearCache()
        if autoUnloadStage1 {
            await stage1.unload()
            MLX.Memory.clearCache()
        }

        // 4. Stage 2: Acoustic Refinement
        if stage2Quality != .draft {
            progressHandler(PipelineProgress(
                phase: .stage2Refining,
                progressFraction: 0.52,
                statusMessage: "Loading Stage 2 acoustic model weights (\(precision))..."
            ))

            try await stage2.loadWeights(from: modelsDir.appendingPathComponent("stage2"), precision: precision)
            if isCancelled { throw CancellationError() }
        }

        let songTokens = try await stage2.refine(
            vocalC0: vocalC0,
            instC0: instC0,
            quality: stage2Quality,
            params: params
        ) { currentStep, totalSteps, speed in
            let frac = 0.55 + (Double(currentStep) / Double(totalSteps)) * 0.3
            progressHandler(PipelineProgress(
                phase: .stage2Refining,
                progressFraction: frac,
                currentStep: currentStep,
                totalSteps: totalSteps,
                speed: speed,
                statusMessage: String(format: "Stage 2: %d/%d steps (%.1f step/s)", currentStep, totalSteps, speed)
            ))
        }

        if isCancelled { throw CancellationError() }

        // Memory optimization: clear Stage 2 intermediate cache
        MLX.Memory.clearCache()

        // 5. Stage 3: Neural Audio Synthesis (X-Codec)
        progressHandler(PipelineProgress(
            phase: .decodingAudio,
            progressFraction: 0.88,
            statusMessage: "Synthesizing 44.1 kHz 24-bit floating-point audio with X-Codec..."
        ))

        try decoder.loadWeights(from: modelsDir.appendingPathComponent("xcodec"))

        // Prepare token tensors for vocal and instrumental tracks: [numCodebooks, numFrames]
        let numFrames = songTokens.numFrames
        let numVocalCb = min(songTokens.vocalTokens.count, 8)
        let numInstCb = min(songTokens.instrumentalTokens.count, 8)
        let numCodebooks = max(1, min(numVocalCb, numInstCb))

        guard numFrames > 0 else {
            throw NSError(domain: "YuEPipeline", code: 400, userInfo: [NSLocalizedDescriptionKey: "No audio frames generated."])
        }

        var combinedVocalArray: [Int32] = []
        var combinedInstArray: [Int32] = []
        for k in 0..<numCodebooks {
            let vRow = songTokens.vocalTokens[k]
            let iRow = songTokens.instrumentalTokens[k]
            combinedVocalArray.append(contentsOf: vRow.prefix(numFrames).map { Int32($0) })
            combinedInstArray.append(contentsOf: iRow.prefix(numFrames).map { Int32($0) })
        }
        let vocalTensor = MLXArray(combinedVocalArray).reshaped([numCodebooks, numFrames])
        let instTensor = MLXArray(combinedInstArray).reshaped([numCodebooks, numFrames])

        // Zero-copy Metal acoustic & neural decoding for dual tracks
        let vocalAudio = try decoder.decode(tokens: vocalTensor)
        let instAudio = try decoder.decode(tokens: instTensor)

        // Master mix: lead vocal anchored in center, instrumental with controlled acoustic width
        let vocalMono = vocalAudio[0] // [totalSamples]
        let instMono = instAudio[0]   // [totalSamples]

        let width = Float(max(0.0, min(1.0, stereoWidth)))
        // Width = 0.0 -> pure centered mono (zero spatial widening)
        // Width = 0.5 -> natural focused acoustic mix
        // Width = 1.0 -> full stereo
        let leftInst = instMono * (1.0 + width * 0.05)
        let rightInst = instMono * (1.0 - width * 0.05)

        let mixedLeft = vocalMono * 0.5 + leftInst * 0.5
        let mixedRight = vocalMono * 0.5 + rightInst * 0.5
        let mixedAudio = MLX.concatenated([
            mixedLeft.reshaped([1, -1]),
            mixedRight.reshaped([1, -1])
        ], axis: 0)

        guard var buffer = decoder.createPCMBuffer(
            from: mixedAudio,
            targetPeak: 0.891,
            resampleTo: 44100.0,
            mastering: applyMastering ? MasteringProcessor() : nil
        ) else {
            throw NSError(domain: "YuEPipeline", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to allocate PCM audio buffer"])
        }

        // 6. Vocos upsampling + spectral crossover.
        //
        // The X-Codec render above stops at 8 kHz because the codec is 16 kHz.
        // Official YuE v1 finishes by running the same quantized features through
        // a per-track Vocos vocoder at 44.1 kHz, then keeping X-Codec's lows and
        // Vocos's highs across a 5.5 kHz crossover. Without this stage the output
        // has no top end at all.
        let upsamplerDir = modelsDir.appendingPathComponent("upsampler")
        if upsampleEnabled, FileManager.default.fileExists(atPath: upsamplerDir.path) {
            do {
                progressHandler(PipelineProgress(
                    phase: .decodingAudio,
                    progressFraction: 0.94,
                    statusMessage: "Upsampling to 44.1 kHz with Vocos vocoder..."
                ))

                let vocalFeats = try decoder.quantizedEmbeddings(tokens: vocalTensor)
                let instFeats = try decoder.quantizedEmbeddings(tokens: instTensor)

                let vocalUps = VocosUpsampler()
                try vocalUps.loadWeights(from: upsamplerDir.appendingPathComponent("vocal_upsampler.safetensors"))
                let vocalHi = try vocalUps.synthesize(features: vocalFeats)
                MLX.eval(vocalHi)

                let instUps = VocosUpsampler()
                try instUps.loadWeights(from: upsamplerDir.appendingPathComponent("inst_upsampler.safetensors"))
                let instHi = try instUps.synthesize(features: instFeats)
                MLX.eval(instHi)

                let v = vocalHi.asArray(Float.self)
                let i = instHi.asArray(Float.self)
                let n = min(v.count, i.count)
                guard n > 0 else { throw NSError(domain: "YuEPipeline", code: 500, userInfo: [
                    NSLocalizedDescriptionKey: "Vocos produced no samples."
                ]) }

                // Official YuE sums the two stems directly.
                var high = [Float](repeating: 0, count: n)
                for k in 0..<n { high[k] = v[k] + i[k] }

                let lowChannels = XCodecDecoder.channelArrays(from: buffer)
                guard !lowChannels.isEmpty else { throw NSError(domain: "YuEPipeline", code: 500, userInfo: [
                    NSLocalizedDescriptionKey: "Could not read the 16 kHz render back."
                ]) }

                let crossover = SpectralCrossover(cutoffHz: 5500.0)
                let combined = lowChannels.map {
                    crossover.combine(low: $0, high: high, sampleRate: 44100.0)
                }

                if let merged = XCodecDecoder.makeBuffer(channels: combined, sampleRate: 44100.0, targetPeak: nil) {
                    buffer = merged
                    print("[YuEPipeline] Vocos upsampling applied (\(n) samples, 5.5 kHz crossover).")
                }
            } catch {
                // The 16 kHz render is already valid, so a missing or broken
                // upsampler degrades quality rather than failing the generation.
                print("[YuEPipeline] Vocos upsampling skipped: \(error.localizedDescription)")
            }
        }

        // 7. Leveling and compression.
        //
        // Each section is generated as its own Stage 1 block with no knowledge of
        // how loud the previous one came out, so sections drift against each other
        // by well over 10 dB. That drift is what makes the vocal sound like it is
        // wandering toward and away from the microphone.
        if levelingEnabled {
            var channels = XCodecDecoder.channelArrays(from: buffer)
            if !channels.isEmpty {
                DynamicsProcessor().process(&channels, sampleRate: buffer.format.sampleRate)
                if let leveled = XCodecDecoder.makeBuffer(
                    channels: channels,
                    sampleRate: buffer.format.sampleRate,
                    targetPeak: nil
                ) {
                    buffer = leveled
                    print("[YuEPipeline] Leveling and compression applied.")
                }
            }
        }

        // 8. Final Mastering Limiter & Loudness Normalization (studio -14 LUFS standard, true-peak ceiling 0.891)
        let limiter = MasteringLimiter()
        buffer = limiter.processBuffer(buffer)
        print("[YuEPipeline] Final mastering limiter applied (-14 LUFS standard, ceiling 0.891).")

        progressHandler(PipelineProgress(
            phase: .complete,
            progressFraction: 1.0,
            statusMessage: "Song generated successfully!"
        ))

        return buffer
    }

    /// Chooses the Stage 1 checkpoint whose language matches the lyrics.
    ///
    /// Looks for `stage1-<lang>` (e.g. `stage1-zh`) and falls back to `stage1`.
    /// Returns the directory and the language that checkpoint actually speaks, so
    /// callers can warn and avoid promising vocals the model cannot deliver.
    static func selectStage1Directory(modelsDir: URL, lyricLanguage: String) -> (URL, String) {
        let fm = FileManager.default
        func isUsable(_ url: URL) -> Bool {
            guard let files = try? fm.contentsOfDirectory(atPath: url.path) else { return false }
            return files.contains { $0.hasSuffix(".safetensors") }
        }

        let preferred = modelsDir.appendingPathComponent("stage1-\(lyricLanguage)")
        if isUsable(preferred) {
            return (preferred, lyricLanguage)
        }

        // Fall back to the default checkpoint. Its language is recorded alongside
        // it when known; otherwise assume English, which is what YuE's default
        // anneal checkpoint is.
        let fallback = modelsDir.appendingPathComponent("stage1")
        var fallbackLanguage = "en"
        let marker = fallback.appendingPathComponent("language.txt")
        if let raw = try? String(contentsOf: marker, encoding: .utf8) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { fallbackLanguage = trimmed }
        }
        return (fallback, fallbackLanguage)
    }

    /// Splits the song-wide token budget across sections up front.
    ///
    /// Stage 1 emits one interleaved (vocal, instrumental) token pair per 50 Hz frame,
    /// so 100 tokens is one second of audio.
    ///
    /// Budgets are proportional to how much text each section has to sing, with a
    /// guaranteed floor for every section. Previously each vocal section was handed the
    /// entire song budget and simply consumed what it wanted, so the first long verse
    /// could exhaust everything and leave the remaining sections either ungenerated or
    /// squeezed into a fraction of a second.
    static func allocateSegmentBudgets(segments: [String], totalTokens: Int) -> [Int] {
        guard !segments.isEmpty else { return [] }

        let tokensPerSecond = 100
        let minSegmentTokens = 2 * tokensPerSecond // never shorter than ~2 s

        func lyricCharacterCount(_ segment: String) -> Int {
            segment
                .split(separator: "\n")
                .dropFirst() // the leading [tag] line is structure, not lyrics
                .reduce(0) { $0 + $1.trimmingCharacters(in: .whitespaces).count }
        }

        let weights: [Double] = segments.map { seg in
            let chars = lyricCharacterCount(seg)
            if chars == 0 {
                // Purely instrumental section: enough for a short passage, not a whole verse.
                return 0.35
            }
            // Roughly one second of singing per ~9 characters of lyrics.
            return max(1.0, Double(chars) / 9.0)
        }

        let totalWeight = weights.reduce(0, +)
        guard totalWeight > 0 else {
            let even = max(minSegmentTokens, totalTokens / segments.count)
            return Array(repeating: even - (even % 2), count: segments.count)
        }

        var budgets = weights.map { weight -> Int in
            let share = Double(totalTokens) * (weight / totalWeight)
            return max(minSegmentTokens, Int(share.rounded()))
        }

        // The per-section floor can push the total past what the user asked for;
        // scale proportionally so the song still lands near the requested length.
        let sum = budgets.reduce(0, +)
        if sum > totalTokens {
            let scale = Double(totalTokens) / Double(sum)
            budgets = budgets.map { max(2, Int((Double($0) * scale).rounded())) }
        }

        // A frame is a token pair, so an odd budget would strand a half frame.
        return budgets.map { $0 - ($0 % 2) }
    }
}
