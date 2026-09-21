import Foundation
import SwiftUI
import AVFoundation

@Observable
public final class AppState: @unchecked Sendable {
    public static let buildNumber = "2026092101"

    // Core Pipeline Engines
    public let database: SQLiteDatabase
    public let settingsRepo: SettingsRepository
    public let generationRepo: GenerationRepository
    public let modelRepo: ModelRegistryRepository
    public let presetRepo: PresetRepository
    public let pipeline: YuEPipeline
    public let audioPlayer: AudioPlaybackEngine
    public let downloadManager: ModelDownloadManager
    public let referenceManager = AudioReferenceManager.shared

    // UI Navigation
    public enum NavigationTab: String, CaseIterable, Identifiable {
        case studio = "Studio"
        case models = "Model Manager"
        case history = "Library"
        case settings = "Settings"

        public var id: String { rawValue }
        public var iconName: String {
            switch self {
            case .studio: return "music.note"
            case .models: return "externaldrive.badge.icloud"
            case .history: return "clock.arrow.circlepath"
            case .settings: return "gearshape"
            }
        }
    }

    public var currentTab: NavigationTab = .studio

    // Studio Input Fields
    public var songTitle: String = "Untitled Song"
    public var genreTags: String = "female vocal, modern melodic pop, uplifting synth, acoustic guitar, driving drums, 120 bpm"
    public var lyrics: String = """
    [verse]
    Waking up under morning light
    Chasing shadows into the night
    Every step brings a brand new sound
    Feet are dancing off the ground

    [chorus]
    Hear the music rising high
    Painting colors in the sky
    We are singing through the rain
    Nothing holding back the flame
    """ {
        didSet {
            if !currentScore.isEmpty {
                self.currentScore = symbolicPlanner.rewriteLyrics(abc: currentScore, newLyrics: lyrics)
            }
        }
    }

    // Inference Parameters
    public var temperature: Double = 1.0
    public var topP: Double = 0.93
    public var cfgScale: Double = 1.5
    public var maxTokens: Int = 1600
    public var seed: Int = Int.random(in: 1000...999999)
    public var autoSeed: Bool = true
    public var quantizationPrecision: String = "4-bit"
    public var autoUnloadStage1: Bool = true
    public var stage2Quality: Stage2Quality = .full

    public func setStage2Quality(_ quality: Stage2Quality) {
        self.stage2Quality = quality
        settingsRepo.set(key: .stage2Quality, value: quality.rawValue)
    }

    // Audio Reference & Cover Song Creation
    public var referenceAudioURL: URL?
    public var referenceAudioName: String?
    public var referenceAudioDuration: Double?
    public var referenceMode: ReferenceMode = .melodyOnly
    public var keyShiftSemitones: Int = 0
    public var modeTransform: ModeTransform = .none
    public var isAnalyzingReference: Bool = false
    public var referenceAnalysis: ReferenceAudioAnalysis?

    public func setReferenceMode(_ mode: ReferenceMode) {
        self.referenceMode = mode
        settingsRepo.set(key: .referenceMode, value: mode.rawValue)
    }

    public func loadReferenceAudio(url: URL) {
        self.referenceAudioURL = url
        self.referenceAudioName = url.lastPathComponent
        self.isAnalyzingReference = true

        Task {
            do {
                let analysis = try await referenceManager.analyzeReference(url: url)
                await MainActor.run {
                    self.referenceAnalysis = analysis
                    self.referenceAudioDuration = analysis.durationSeconds
                    self.isAnalyzingReference = false
                    if self.planningMode == .melodyCover || self.currentScore.isEmpty {
                        self.currentScore = analysis.abcNotation
                    }
                }
            } catch {
                print("[AppState] Error analyzing reference audio: \(error)")
                await MainActor.run {
                    self.isAnalyzingReference = false
                }
            }
        }
    }

    public func extractMelodyFromReference() {
        if let analysis = referenceAnalysis {
            self.currentScore = analysis.abcNotation
        } else if let url = referenceAudioURL {
            loadReferenceAudio(url: url)
        }
    }

    public func clearReferenceAudio() {
        self.referenceAudioURL = nil
        self.referenceAudioName = nil
        self.referenceAudioDuration = nil
        self.referenceAnalysis = nil
        self.keyShiftSemitones = 0
        self.modeTransform = .none
    }

    public func applyKeyShift(delta: Int) {
        self.keyShiftSemitones = max(-12, min(12, self.keyShiftSemitones + delta))
        self.currentScore = symbolicPlanner.transpose(abc: self.currentScore, semitones: delta)
        settingsRepo.set(key: .keyShiftSemitones, value: "\(self.keyShiftSemitones)")
    }

    public func applyModeTransform(_ transform: ModeTransform) {
        self.modeTransform = transform
        self.currentScore = symbolicPlanner.modulateMode(abc: self.currentScore, transform: transform)
    }

    public func alignLyricsWithMelody() {
        self.currentScore = symbolicPlanner.rewriteLyrics(abc: self.currentScore, newLyrics: self.lyrics)
    }

    // YuE2 Symbolic Music Planning & Notation
    public var currentScore: String = ""
    public var planningMode: PlanningMode = .melodyCover {
        didSet {
            let str: String
            switch planningMode {
            case .fullPlan: str = "symbolic"
            case .melodyCover: str = "melody_cover"
            case .directAudio: str = "direct"
            }
            settingsRepo.set(key: .planningMode, value: str)
        }
    }
    public let symbolicPlanner = SymbolicPlanner()

    // Acoustic Mastering & Stereo Width
    public var stereoWidth: Double = 0.5

    public func setStereoWidth(_ width: Double) {
        self.stereoWidth = max(0.0, min(1.0, width))
        self.audioPlayer.stereoWidth = self.stereoWidth
    }

    /// Corrective EQ on the render. X-Codec output carries a heavy low-frequency
    /// tilt that reads as boxy; this lifts the scooped midrange back up. Off gives
    /// the raw codec output.
    public var masteringEnabled: Bool = false

    /// Runs the Vocos vocoder and 5.5 kHz crossover that official YuE v1 uses to
    /// finish a render. Without it the output has nothing above 8 kHz.
    public var upsampleEnabled: Bool = true

    /// Levels sections against each other and tames surges. YuE renders each
    /// section independently, so their levels drift badly without this.
    public var levelingEnabled: Bool = true

    public func setLevelingEnabled(_ enabled: Bool) {
        self.levelingEnabled = enabled
        settingsRepo.set(key: .levelingEnabled, value: enabled ? "true" : "false")
    }

    public func setUpsampleEnabled(_ enabled: Bool) {
        self.upsampleEnabled = enabled
        settingsRepo.set(key: .upsampleEnabled, value: enabled ? "true" : "false")
    }

    public func setMasteringEnabled(_ enabled: Bool) {
        self.masteringEnabled = enabled
        settingsRepo.set(key: .masteringEnabled, value: enabled ? "true" : "false")
    }

    public var masteringTargetRMS: Float = 0.18
    public var masteringCeilingDB: Float = -1.0
    public var playerMonitoringVolume: Float = 1.0

    public func setMasteringTargetRMS(_ val: Float) {
        self.masteringTargetRMS = val
        settingsRepo.set(key: .masteringTargetRMS, value: String(val))
    }

    public func setPlayerMonitoringVolume(_ val: Float) {
        self.playerMonitoringVolume = val
        self.audioPlayer.volume = val
        settingsRepo.set(key: .playerMonitoringVolume, value: String(val))
    }

    // Model Paths & Status
    public var modelDirectoryPath: String = AppPaths.defaultModelsURL.path
    public var modelList: [ModelItem] = []
    public var isModelsReady: Bool = false

    // Presets & History
    public var presetGenres: [PresetGenre] = []
    public var presetLyrics: [PresetLyric] = []
    public var historyRecords: [GenerationRecord] = []

    // Generation State
    public var isGenerating: Bool = false
    public var currentProgress: PipelineProgress = PipelineProgress()
    public var activeAudioBuffer: AVAudioPCMBuffer?
    public var latestAudioPath: String?

    // Alerts & Warnings
    public var showMissingModelsAlert: Bool = false
    public var missingModelsMessage: String = ""

    // Hardware Memory
    public var memoryStats: MemoryStats = MemoryStats(usedGB: 0, totalGB: 16, percentage: 0)

    public init() {
        let dbPath = AppPaths.databasePath
        do {
            let db = try SQLiteDatabase(path: dbPath)
            try Schema.migrate(database: db)
            self.database = db
            self.settingsRepo = SettingsRepository(database: db)
            self.generationRepo = GenerationRepository(database: db)
            self.modelRepo = ModelRegistryRepository(database: db)
            self.presetRepo = PresetRepository(database: db)
        } catch {
            fatalError("Failed to initialize database: \(error)")
        }

        self.pipeline = YuEPipeline()
        self.audioPlayer = AudioPlaybackEngine()
        let dm = ModelDownloadManager()
        self.downloadManager = dm

        self.currentScore = self.symbolicPlanner.generateStarterTemplate(
            title: self.songTitle,
            genreTags: self.genreTags,
            lyrics: self.lyrics
        )

        loadPersistedState()
        refreshMemoryStats()

        dm.onStageCompleted = { [weak self] _ in
            Task { @MainActor in
                self?.checkModelsAvailability()
            }
        }
    }

    public func loadPersistedState() {
        if let path = settingsRepo.get(key: .modelDirectoryPath), !path.isEmpty {
            self.modelDirectoryPath = AppPaths.resolvePath(path)
        } else {
            self.modelDirectoryPath = AppPaths.defaultModelsURL.path
        }
        if let prec = settingsRepo.get(key: .quantizationPrecision) {
            self.quantizationPrecision = prec
        }
        if let tempStr = settingsRepo.get(key: .defaultTemperature), let t = Double(tempStr) {
            self.temperature = t
        }
        if let topPStr = settingsRepo.get(key: .defaultTopP), let p = Double(topPStr) {
            self.topP = p
        }
        if let cfgStr = settingsRepo.get(key: .defaultCFGScale), let c = Double(cfgStr) {
            self.cfgScale = c
        }
        if let maxTStr = settingsRepo.get(key: .defaultMaxTokens), let m = Int(maxTStr) {
            self.maxTokens = m
        }
        if let unloadStr = settingsRepo.get(key: .autoUnloadStage1) {
            self.autoUnloadStage1 = (unloadStr == "true")
        }
        if let lvlStr = settingsRepo.get(key: .levelingEnabled) {
            self.levelingEnabled = (lvlStr == "true")
        }
        if let upsStr = settingsRepo.get(key: .upsampleEnabled) {
            self.upsampleEnabled = (upsStr == "true")
        }
        if let masteringStr = settingsRepo.get(key: .masteringEnabled) {
            self.masteringEnabled = (masteringStr == "true")
        }
        if let qualityStr = settingsRepo.get(key: .stage2Quality), let q = Stage2Quality(rawValue: qualityStr) {
            self.stage2Quality = q
        }
        if let refModeStr = settingsRepo.get(key: .referenceMode), let rm = ReferenceMode(rawValue: refModeStr) {
            self.referenceMode = rm
        }
        if let keyStr = settingsRepo.get(key: .keyShiftSemitones), let k = Int(keyStr) {
            self.keyShiftSemitones = k
        }
        if let planStr = settingsRepo.get(key: .planningMode) {
            if planStr == "symbolic" {
                self.planningMode = .fullPlan
            } else if planStr == "melody_cover" {
                self.planningMode = .melodyCover
            } else if planStr == "direct" {
                self.planningMode = .directAudio
            }
        }
        if let targetRMSStr = settingsRepo.get(key: .masteringTargetRMS), let tr = Float(targetRMSStr) {
            self.masteringTargetRMS = tr
        }
        if let ceilingStr = settingsRepo.get(key: .masteringCeilingDB), let c = Float(ceilingStr) {
            self.masteringCeilingDB = c
        }
        if let volStr = settingsRepo.get(key: .playerMonitoringVolume), let v = Float(volStr) {
            self.playerMonitoringVolume = v
            self.audioPlayer.volume = v
        }

        self.presetGenres = presetRepo.getGenres()
        self.presetLyrics = presetRepo.getLyrics()
        self.historyRecords = generationRepo.getAll()
        self.modelList = modelRepo.getAll()
        checkModelsAvailability()
    }

    public func setModelDirectory(newPath: String) {
        let resolved = AppPaths.resolvePath(newPath)
        self.modelDirectoryPath = resolved
        settingsRepo.set(key: .modelDirectoryPath, value: resolved)
        checkModelsAvailability()
    }

    public func setQuantization(precision: String) {
        self.quantizationPrecision = precision
        settingsRepo.set(key: .quantizationPrecision, value: precision)
    }

    public func directoryHasWeights(_ dir: URL) -> Bool {
        guard let enumerator = FileManager.default.enumerator(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }
        while let file = enumerator.nextObject() as? URL {
            let ext = file.pathExtension.lowercased()
            if ext == "safetensors" || ext == "bin" || ext == "mlmodelc" || ext == "pth" {
                let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                if size > 1_000_000 {
                    return true
                }
            }
        }
        return false
    }

    public func directoryWeightSizeString(_ dir: URL) -> String? {
        guard let enumerator = FileManager.default.enumerator(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        var total: Int64 = 0
        while let file = enumerator.nextObject() as? URL {
            if let isReg = (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile, isReg {
                let size = Int64((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
                total += size
            }
        }
        if total == 0 { return nil }
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }

    public func checkModelsAvailability() {
        let rootURL = AppPaths.resolveURL(modelDirectoryPath)
        var allExist = true

        for item in modelList {
            let stageDir = rootURL.appendingPathComponent(item.stage)
            let exists = directoryHasWeights(stageDir)
            modelRepo.updateStatus(id: item.id, status: exists ? "ready" : "not_downloaded")
            if !exists {
                allExist = false
            }
        }
        self.modelList = modelRepo.getAll()
        self.isModelsReady = allExist
    }

    public func applyPresetGenre(_ preset: PresetGenre) {
        self.genreTags = preset.tags
        self.currentScore = symbolicPlanner.generateStarterTemplate(
            title: self.songTitle,
            genreTags: preset.tags,
            lyrics: self.lyrics
        )
    }

    public func applyPresetLyric(_ preset: PresetLyric) {
        self.lyrics = preset.lyrics
        self.songTitle = preset.title
        self.currentScore = symbolicPlanner.generateStarterTemplate(
            title: preset.title,
            genreTags: self.genreTags,
            lyrics: preset.lyrics
        )
    }

    public func refreshMemoryStats() {
        self.memoryStats = SystemMonitor.getUnifiedMemoryStats()
    }

    @MainActor
    public func startGeneration() {
        guard !isGenerating else { return }

        // Safeguard: Check if weights exist before launching inference
        let modelsURL = AppPaths.resolveURL(modelDirectoryPath)
        let stage1URL = modelsURL.appendingPathComponent("stage1")
        if !directoryHasWeights(stage1URL) {
            self.missingModelsMessage = "Stage 1 model weights are not found in '\(stage1URL.path)'. Please go to the Model Manager tab to download the required weights, or choose a folder containing converted YuE safetensors.\n\nTip: You can click 'Demo Preview' to test the audio player and waveform immediately!"
            self.showMissingModelsAlert = true
            return
        }

        let xcodecURL = modelsURL.appendingPathComponent("xcodec")
        if !directoryHasWeights(xcodecURL) {
            self.missingModelsMessage = "X-Codec neural vocoder weights ('decoder.safetensors') are not found in '\(xcodecURL.path)'. Please check that your model directory contains the X-Codec decoder weights."
            self.showMissingModelsAlert = true
            return
        }

        isGenerating = true

        if autoSeed {
            seed = Int.random(in: 10000...999999)
        }

        let currentSeed = seed
        let currentTemp = temperature
        let currentTopP = topP
        let currentCFG = cfgScale
        let currentTokens = maxTokens
        let title = songTitle.isEmpty ? "Song \(Date().formatted(date: .numeric, time: .shortened))" : songTitle
        let tags = genreTags
        let currentLyrics = lyrics
        let unloadStage1 = autoUnloadStage1
        let currentPrecision = quantizationPrecision
        let currentQuality = stage2Quality
        let currentWidth = stereoWidth
        let currentMastering = masteringEnabled
        let currentUpsample = upsampleEnabled
        let currentLeveling = levelingEnabled
        let scoreToUse = (planningMode == .directAudio) ? nil : currentScore
        let cotToUse = (planningMode == .melodyCover) ? "melody" : "full"
        let currentRefURL = referenceAudioURL
        let currentRefMode = referenceMode
        let currentRefPrompt = referenceAnalysis?.referenceTokens.map { String($0) }.joined(separator: " ")

        let samplingParams = SamplingParameters(
            temperature: Float(currentTemp),
            topP: Float(currentTopP),
            cfgScale: Float(currentCFG),
            seed: UInt64(currentSeed)
        )

        Task {
            do {
                let buffer = try await pipeline.generateSong(
                    genreTags: tags,
                    lyrics: currentLyrics,
                    scoreABC: scoreToUse,
                    cotMode: cotToUse,
                    modelsDir: modelsURL,
                    maxTokens: currentTokens,
                    params: samplingParams,
                    precision: currentPrecision,
                    stage2Quality: currentQuality,
                    referenceAudioURL: currentRefURL,
                    referenceMode: currentRefMode,
                    referencePrompt: currentRefPrompt,
                    autoUnloadStage1: unloadStage1,
                    stereoWidth: currentWidth,
                    applyMastering: currentMastering,
                    upsampleEnabled: currentUpsample,
                    levelingEnabled: currentLeveling
                ) { [weak self] progress in
                    Task { @MainActor in
                        self?.currentProgress = progress
                        self?.refreshMemoryStats()
                    }
                }

                // Save audio file locally in Generations directory
                let outputDir = AppPaths.defaultGenerationsURL
                let filename = "song_\(Int(Date().timeIntervalSince1970)).wav"
                let audioURL = outputDir.appendingPathComponent(filename)

                try AudioExporter.export(buffer: buffer, to: audioURL, format: .wav)

                let duration = Double(buffer.frameLength) / buffer.format.sampleRate

                let record = GenerationRecord(
                    title: title,
                    genreTags: tags,
                    lyrics: currentLyrics,
                    temperature: currentTemp,
                    topP: currentTopP,
                    cfgScale: currentCFG,
                    maxTokens: currentTokens,
                    seed: currentSeed,
                    audioPath: audioURL.path,
                    durationSeconds: duration,
                    status: "completed"
                )

                try generationRepo.insert(record: record)

                // Transcribe the generated audio to update the Musical Notes & Sheet Score immediately on UI
                var transcribedScore: String? = nil
                if let analysis = try? await AudioReferenceManager.shared.analyzeBuffer(buffer, url: audioURL, title: title, lyrics: currentLyrics) {
                    transcribedScore = analysis.abcNotation
                }

                Task { @MainActor in
                    self.activeAudioBuffer = buffer
                    self.latestAudioPath = audioURL.path
                    self.audioPlayer.load(buffer: buffer)
                    if let score = transcribedScore {
                        self.currentScore = score
                    }
                    self.historyRecords = self.generationRepo.getAll()
                    self.isGenerating = false
                    self.refreshMemoryStats()
                }
            } catch {
                Task { @MainActor in
                    self.isGenerating = false
                    self.currentProgress = PipelineProgress(
                        phase: .failed,
                        statusMessage: "Error: \(error.localizedDescription)"
                    )
                    self.refreshMemoryStats()
                }
            }
        }
    }

    @MainActor
    public func startDemoSynthesis() {
        guard !isGenerating else { return }
        isGenerating = true

        currentProgress = PipelineProgress(
            phase: .stage1Generating,
            progressFraction: 0.25,
            statusMessage: "Synthesizing demo acoustic tracks..."
        )

        Task {
            do {
                let sampleRate: Double = 44100.0
                let duration: Double = 8.0 // 8 seconds demo song
                let frameCount = AVAudioFrameCount(sampleRate * duration)

                guard let format = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32,
                    sampleRate: sampleRate,
                    channels: 2,
                    interleaved: false
                ), let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                    self.isGenerating = false
                    return
                }
                buffer.frameLength = frameCount

                let chordFreqs: [[Double]] = [
                    [261.63, 329.63, 392.00, 523.25], // C maj
                    [196.00, 246.94, 293.66, 392.00], // G maj
                    [220.00, 261.63, 329.63, 440.00], // A min
                    [174.61, 220.00, 261.63, 349.23]  // F maj
                ]

                let leftChannel = buffer.floatChannelData![0]
                let rightChannel = buffer.floatChannelData![1]

                for i in 0..<Int(frameCount) {
                    let t = Double(i) / sampleRate
                    let chordIndex = min(Int(t / 2.0), 3)
                    let currentChord = chordFreqs[chordIndex]

                    var sampleL: Float = 0.0
                    var sampleR: Float = 0.0

                    for (ci, freq) in currentChord.enumerated() {
                        let pan = Float(ci) / Float(currentChord.count)
                        let wave = Float(sin(2.0 * .pi * freq * t)) * 0.15
                        let overtone = Float(sin(4.0 * .pi * freq * t)) * 0.05
                        let val = wave + overtone

                        sampleL += val * (1.0 - pan * 0.4)
                        sampleR += val * (0.6 + pan * 0.4)
                    }

                    let env: Float = Float(min(1.0, min(t * 2.0, (duration - t) * 2.0)))
                    leftChannel[i] = sampleL * env
                    rightChannel[i] = sampleR * env
                }

                let outputDir = AppPaths.defaultGenerationsURL
                let audioURL = outputDir.appendingPathComponent("demo_\(Int(Date().timeIntervalSince1970)).wav")
                try AudioExporter.export(buffer: buffer, to: audioURL, format: .wav)

                let record = GenerationRecord(
                    title: songTitle.isEmpty ? "Demo Preview Song" : "\(songTitle) (Demo Preview)",
                    genreTags: genreTags,
                    lyrics: lyrics,
                    temperature: temperature,
                    topP: topP,
                    cfgScale: cfgScale,
                    maxTokens: maxTokens,
                    seed: seed,
                    audioPath: audioURL.path,
                    durationSeconds: duration,
                    status: "completed"
                )
                try generationRepo.insert(record: record)

                // Transcribe demo audio into sheet music score
                if let analysis = try? await AudioReferenceManager.shared.analyzeBuffer(buffer, url: audioURL, title: songTitle.isEmpty ? "Demo Song" : songTitle, lyrics: lyrics) {
                    self.currentScore = analysis.abcNotation
                }

                self.activeAudioBuffer = buffer
                self.latestAudioPath = audioURL.path
                self.audioPlayer.load(buffer: buffer)
                self.historyRecords = self.generationRepo.getAll()
                self.isGenerating = false
                self.currentProgress = PipelineProgress(
                    phase: .complete,
                    progressFraction: 1.0,
                    statusMessage: "Demo synthesized and loaded into Waveform Player! Click Play below to listen."
                )
            } catch {
                self.isGenerating = false
                self.currentProgress = PipelineProgress(phase: .failed, statusMessage: error.localizedDescription)
            }
        }
    }

    public func cancelGeneration() {
        Task {
            await pipeline.cancel()
            await MainActor.run {
                self.isGenerating = false
                self.currentProgress = PipelineProgress(phase: .idle, statusMessage: "Generation cancelled.")
            }
        }
    }
}
