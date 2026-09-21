import Foundation
import AVFoundation
import MLX
import MLXNN

public actor YuE2Pipeline {
    private var arModel: YuE2ARModel?
    private var narModel: YuE2NARFlowMatching?
    private var vaeDecoder: OobleckVAEDecoder?

    private var loadedModelDir: URL?
    private var loadedVaeDir: URL?
    private var isCancelled: Bool = false

    public init() {
        self.vaeDecoder = OobleckVAEDecoder()
        self.narModel = YuE2NARFlowMatching()
        self.arModel = YuE2ARModel()
    }

    public func cancel() {
        self.isCancelled = true
    }

    /// Primary async generation entrypoint for YuE2-3B
    public func generateSong(
        prompt: String,
        lyrics: String,
        abcScore: String? = nil,
        planningMode: PlanningMode = .fullGenerated,
        maxTokens: Int = 12000,
        steps: Int = 32,
        temperature: Float = 0.9,
        topP: Float = 0.95,
        cfgScale: Float = 1.0,
        modelDirectory: URL,
        vaeDirectory: URL,
        onProgress: @Sendable @escaping (PipelineProgress) -> Void
    ) async throws -> AVAudioPCMBuffer {
        self.isCancelled = false

        let vae = self.vaeDecoder ?? OobleckVAEDecoder()
        let nar = self.narModel ?? YuE2NARFlowMatching()
        let ar = self.arModel ?? YuE2ARModel()
        self.vaeDecoder = vae
        self.narModel = nar
        self.arModel = ar

        // 1. Loading Models (cached if paths have not changed)
        if loadedVaeDir != vaeDirectory {
            onProgress(PipelineProgress(
                phase: .loadingModels,
                progressFraction: 0.05,
                statusMessage: "Loading 48kHz Oobleck VAE decoder weights..."
            ))
            try vae.loadWeights(from: vaeDirectory)
            self.loadedVaeDir = vaeDirectory
        }

        if loadedModelDir != modelDirectory {
            onProgress(PipelineProgress(
                phase: .loadingModels,
                progressFraction: 0.10,
                statusMessage: "Loading YuE2-3B Flow Matching acoustic weights (BF16)..."
            ))
            try nar.loadWeights(from: modelDirectory)

            onProgress(PipelineProgress(
                phase: .loadingModels,
                progressFraction: 0.18,
                statusMessage: "Loading YuE2-3B Autoregressive semantic weights (8-bit)..."
            ))
            try ar.loadWeights(from: modelDirectory)

            let tiktokenURL = modelDirectory.appendingPathComponent("qwen.tiktoken")
            YuE2Tokenizer.shared.load(from: tiktokenURL)

            self.loadedModelDir = modelDirectory
        }

        if isCancelled {
            throw NSError(domain: "YuE2Pipeline", code: 999, userInfo: [NSLocalizedDescriptionKey: "Generation Cancelled"])
        }

        // 2. AR Planning & Acoustic Conditioning
        onProgress(PipelineProgress(
            phase: .stage1Generating,
            progressFraction: 0.22,
            statusMessage: "YuE2 AR: Tokenizing prompt and musical structure (\(planningMode.rawValue))..."
        ))

        let (cleanedLyrics, directives) = PromptFormatter.extractDirectivesAndCleanLyrics(lyrics: lyrics)
        let enrichedPrompt = PromptFormatter.enrichGenreTags(genreTags: prompt, lyrics: lyrics, extraDirectives: directives)
        let effectiveLyrics = cleanedLyrics.isEmpty ? lyrics : cleanedLyrics

        // Format prompt according to official YuE2 specification
        let instruction = planningMode.instruction
        let scoreToEncode: String?

        if planningMode == .direct {
            scoreToEncode = nil
        } else if let score = abcScore, !score.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            scoreToEncode = score
        } else {
            // Generate standard ABC score template with tempo and chords if no score is supplied
            let generated = SymbolicPlanner().generateStarterTemplate(title: "YuE2 Melody Plan", genreTags: prompt, lyrics: effectiveLyrics)
            scoreToEncode = generated
        }

        let requestText = "\(instruction)\n[Tags]\n\(enrichedPrompt)\n[Lyrics]\n\(effectiveLyrics)\n"
        let tokenizedPrompt = YuE2Tokenizer.shared.encode(text: requestText)

        let promptTokenIds: [Int]
        if let score = scoreToEncode {
            let tokenizedScore = YuE2Tokenizer.shared.encode(text: score)
            // [EOD] + prompt + [ABC_START] + score + [ABC_END, MUSIC_START]
            promptTokenIds = [151643] + tokenizedPrompt + [151847] + tokenizedScore + [151848, 151851]
        } else {
            // In direct mode (off), official protocol token_prefixes: [EOD] + prompt + [ABC_START, ABC_END, MUSIC_START]
            promptTokenIds = [151643] + tokenizedPrompt + [151847, 151848, 151851]
        }

        // Determine target duration based on user token budget and lyrics
        let lyricLines = lyrics
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // User setting: maxTokens maps to duration (100 tokens = 1 second in UI settings, or direct frame count)
        let requestedDurationSec: Double
        if maxTokens >= 1000 {
            // UI token budget: 100 tokens per second (e.g. 6000 -> 60s, 12000 -> 120s / 2m, 24000 -> 240s / 4m)
            requestedDurationSec = Double(maxTokens) / 100.0
        } else if maxTokens > 0 {
            // Direct frame/seconds entry if small
            requestedDurationSec = max(10.0, Double(maxTokens) / 25.0)
        } else {
            requestedDurationSec = 60.0
        }

        // Ensure duration accommodates lyric line count if lyrics are extensive (at least 4s per line)
        let lyricsBaselineSec = Double(max(10, lyricLines.count * 4))
        let targetDurationSec = max(requestedDurationSec, lyricsBaselineSec)

        // YuE2 runs at 25 fps (40ms per frame). Supported up to 24,000 frames (~16 minutes).
        let targetFrames = min(24000, max(250, Int(targetDurationSec * 25.0)))
        let actualDurationSec = Double(targetFrames) / 25.0

        // Minimum tokens floor to avoid cutting off mid-song before the requested duration:
        // Set minTokens so the model stays in full arrangement until ~85% of target frames
        let effectiveMinTokens = max(200, min(targetFrames - 50, Int(Double(targetFrames) * 0.85)))

        let minDisplay = Int(actualDurationSec) / 60
        let secDisplay = Int(actualDurationSec) % 60
        let durationDesc = minDisplay > 0 ? "\(minDisplay)m \(secDisplay)s" : "\(secDisplay)s"

        onProgress(PipelineProgress(
            phase: .stage1Generating,
            progressFraction: 0.25,
            statusMessage: "YuE2 AR: Synthesizing \(targetFrames) semantic frames (\(durationDesc))..."
        ))

        let semanticTokens = ar.generateSemanticTokens(
            promptTokens: promptTokenIds,
            count: targetFrames,
            temperature: temperature,
            topP: topP,
            topK: 100,
            repetitionPenalty: 1.2,
            penaltyWindow: 50,
            minTokens: effectiveMinTokens,
            onProgress: { currentTok, totalTok in
                let frac = 0.25 + (Double(currentTok) / Double(totalTok)) * 0.20
                onProgress(PipelineProgress(
                    phase: .stage1Generating,
                    progressFraction: frac,
                    currentStep: currentTok,
                    totalSteps: totalTok,
                    statusMessage: "YuE2 AR: Semantic tokens (\(currentTok)/\(totalTok)) [\(durationDesc)]..."
                ))
            }
        )

        if isCancelled {
            throw NSError(domain: "YuE2Pipeline", code: 999, userInfo: [NSLocalizedDescriptionKey: "Generation Cancelled"])
        }

        onProgress(PipelineProgress(
            phase: .stage1Generating,
            progressFraction: 0.46,
            statusMessage: "YuE2 AR: Computing acoustic 28-layer KV conditioning cache..."
        ))

        let allTokens = promptTokenIds + semanticTokens + [151852]
        let conditioningCache = ar.computeConditioningCache(tokenIds: allTokens)

        if isCancelled {
            throw NSError(domain: "YuE2Pipeline", code: 999, userInfo: [NSLocalizedDescriptionKey: "Generation Cancelled"])
        }

        // 3. NAR Flow Matching (ODE Midpoint Euler Solver)
        onProgress(PipelineProgress(
            phase: .stage2Refining,
            progressFraction: 0.50,
            statusMessage: "YuE2 NAR: Continuous flow matching synthesis (\(steps) steps)..."
        ))

        let numLatentFrames = max(25, semanticTokens.count)
        let latents = nar.solveLatents(
            frames: numLatentFrames,
            numSteps: steps,
            conditioningCache: conditioningCache,
            conditioningLength: allTokens.count
        ) { currentStep, totalSteps in
            let frac = 0.50 + (Double(currentStep) / Double(totalSteps)) * 0.35
            onProgress(PipelineProgress(
                phase: .stage2Refining,
                progressFraction: frac,
                currentStep: currentStep,
                totalSteps: totalSteps,
                statusMessage: "YuE2 NAR: Flow matching step \(currentStep)/\(totalSteps)"
            ))
        }

        if isCancelled {
            throw NSError(domain: "YuE2Pipeline", code: 999, userInfo: [NSLocalizedDescriptionKey: "Generation Cancelled"])
        }

        // 4. Oobleck VAE 48kHz Stereo Decoding
        onProgress(PipelineProgress(
            phase: .decodingAudio,
            progressFraction: 0.85,
            statusMessage: "YuE2 VAE: Decoding 64-channel latents to 48.0 kHz stereo audio..."
        ))

        guard let buffer = vae.decodeLatentsToPCMBuffer(latents: latents, onProgress: { currentChunk, totalChunks in
            let frac = 0.85 + (Double(currentChunk) / Double(totalChunks)) * 0.14
            onProgress(PipelineProgress(
                phase: .decodingAudio,
                progressFraction: frac,
                currentStep: currentChunk,
                totalSteps: totalChunks,
                statusMessage: "YuE2 VAE: Decoding audio chunk \(currentChunk)/\(totalChunks)"
            ))
        }) else {
            throw NSError(
                domain: "YuE2Pipeline",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: "Failed to decode acoustic latents into 48kHz PCM buffer"]
            )
        }

        onProgress(PipelineProgress(
            phase: .complete,
            progressFraction: 1.0,
            statusMessage: "YuE2 Song generation complete! 48.0 kHz Stereo (\(targetDurationSec)s)."
        ))

        return buffer
    }
}
