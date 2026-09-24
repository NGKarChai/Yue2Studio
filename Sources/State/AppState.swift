import Foundation
import SwiftUI
import AVFoundation

@Observable
public final class AppState: @unchecked Sendable {
    public static let buildNumber = "2026092401"

    // Core Pipeline Engines
    public let database: SQLiteDatabase
    public let settingsRepo: SettingsRepository
    public let generationRepo: GenerationRepository
    public let modelRepo: ModelRegistryRepository
    public let presetRepo: PresetRepository
    public let yue2Pipeline: YuE2Pipeline
    public let audioPlayer: AudioPlaybackEngine
    public let downloadManager: ModelDownloadManager
    public let referenceManager = AudioReferenceManager.shared

    // YuE2 Model Configurations
    public var yue2FlowSteps: Int = 32
    public var yue2ModelDirectory: String = "Models/yue2-3b"
    public var yue2VAEDirectory: String = "Models/yue2-vae"

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

    // Audio Reference & Cover Song Creation
    public var referenceAudioURL: URL?
    public var referenceAudioName: String?
    public var referenceAudioDuration: Double?
    public var referenceMode: ReferenceMode = .melodyOnly
    public var keyShiftSemitones: Int = 0
    public var modeTransform: ModeTransform = .none
    public var isAnalyzingReference: Bool = false
    public var referenceAnalysis: ReferenceAudioAnalysis?
    public var coverPipelineStatus: String?

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
                    if self.planningMode.isSupplied || self.currentScore.isEmpty {
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
            self.loadReferenceAudio(url: url)
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

    public func transposeScore(semitones: Int) {
        applyKeyShift(delta: semitones)
    }

    public func applyModeTransform(_ transform: ModeTransform) {
        self.modeTransform = transform
        self.currentScore = symbolicPlanner.modulateMode(abc: self.currentScore, transform: transform)
    }

    public func alignLyricsWithMelody() {
        self.currentScore = symbolicPlanner.rewriteLyrics(abc: self.currentScore, newLyrics: self.lyrics)
    }

    /// End-to-End Cover Pipeline:
    /// Transcribes source audio -> extracts melody & structure -> sets mode to melodySupplied/fullSupplied -> primes re-synthesis with target styles
    public func prepareCoverPipeline(targetGenre: String? = nil) {
        if let analysis = referenceAnalysis {
            self.currentScore = analysis.abcNotation
        } else if let url = referenceAudioURL {
            self.loadReferenceAudio(url: url)
        }

        // Set mode based on referenceMode
        if self.referenceMode == .fullReference {
            self.planningMode = .fullSupplied
        } else {
            self.planningMode = .melodySupplied
        }

        if let targetGenre = targetGenre, !targetGenre.isEmpty {
            self.genreTags = targetGenre
        }

        if self.songTitle.isEmpty || self.songTitle == "Untitled Song" {
            let baseName = referenceAudioName?.replacingOccurrences(of: "\\.[^.]+$", with: "", options: .regularExpression) ?? "Source Track"
            self.songTitle = "Cover of \(baseName)"
        }

        self.coverPipelineStatus = "Cover pipeline primed: Melodic score extracted, mode set to \(planningMode.rawValue). Ready to re-synthesize!"
    }

    /// Exports complete transcription bundle: ABC notation, playable MIDI file, and SheetSage2/MERT2 LAB timing labels
    public func exportTranscriptionBundle(directory: URL, baseName: String) throws -> [URL] {
        let name = baseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "transcription" : baseName
        let cleanName = name.replacingOccurrences(of: " ", with: "_")
        let effectiveScore = self.currentScore.isEmpty ? (self.referenceAnalysis?.abcNotation ?? "") : self.currentScore
        guard !effectiveScore.isEmpty else {
            throw NSError(domain: "AppState", code: 400, userInfo: [NSLocalizedDescriptionKey: "No musical score or transcribed audio available to export."])
        }

        var exportedURLs: [URL] = []

        // 1. ABC Score (.abc)
        let abcURL = directory.appendingPathComponent("\(cleanName).abc")
        try effectiveScore.write(to: abcURL, atomically: true, encoding: .utf8)
        exportedURLs.append(abcURL)

        // 2. Playable Standard MIDI File (.mid)
        let midiURL = directory.appendingPathComponent("\(cleanName).mid")
        let parsedScore = symbolicPlanner.parseScore(abc: effectiveScore)
        let midiData = MIDIExporter().export(score: parsedScore)
        try midiData.write(to: midiURL)
        exportedURLs.append(midiURL)

        // 3. Note Timing Labels (.lab)
        let labURL = directory.appendingPathComponent("\(cleanName)_notes.lab")
        let notesLab = self.referenceAnalysis?.labNotation ?? {
            var lines: [String] = []
            var t = 0.0
            for measure in parsedScore.measures {
                for note in measure.notes {
                    let durSec = (note.durationBeats / (max(20.0, parsedScore.tempoBpm) / 60.0))
                    if let pitch = note.pitch {
                        let noteName = "\(pitch.step)\(pitch.alter == 1 ? "#" : (pitch.alter == -1 ? "b" : ""))"
                        lines.append(String(format: "%.3f\t%.3f\t%@%d", t, t + durSec, noteName, pitch.octave))
                    }
                    t += durSec
                }
            }
            return lines.joined(separator: "\n")
        }()
        try notesLab.write(to: labURL, atomically: true, encoding: .utf8)
        exportedURLs.append(labURL)

        // 4. Chords Timing Labels (.lab)
        let chordsURL = directory.appendingPathComponent("\(cleanName)_chords.lab")
        let chordsLab = self.referenceAnalysis?.chordsLabNotation ?? "0.000\t4.000\t\(parsedScore.keySignature):maj"
        try chordsLab.write(to: chordsURL, atomically: true, encoding: .utf8)
        exportedURLs.append(chordsURL)

        // 5. Song Structure Timing Labels (.lab)
        let structURL = directory.appendingPathComponent("\(cleanName)_structure.lab")
        let structLab = self.referenceAnalysis?.structureLabNotation ?? referenceManager.generateStructureLAB(lyrics: self.lyrics, duration: self.referenceAudioDuration ?? 30.0)
        try structLab.write(to: structURL, atomically: true, encoding: .utf8)
        exportedURLs.append(structURL)

        return exportedURLs
    }

    // YuE2 Symbolic Music Planning & Notation
    public var currentScore: String = ""
    public var planningMode: PlanningMode = .fullGenerated {
        didSet {
            settingsRepo.set(key: .planningMode, value: planningMode.rawValue)
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
    public var downloadProgressTick: Int = 0

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
            fatalError("Failed to initialize SQLite database at \(dbPath): \(error)")
        }

        self.yue2Pipeline = YuE2Pipeline()
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

        dm.onProgressUpdated = { [weak self] in
            Task { @MainActor in
                self?.downloadProgressTick += 1
            }
        }

        dm.onStageCompleted = { [weak self] _ in
            Task { @MainActor in
                self?.checkModelsAvailability()
                self?.downloadProgressTick += 1
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
        if let masteringStr = settingsRepo.get(key: .masteringEnabled) {
            self.masteringEnabled = (masteringStr == "true")
        }
        if let refModeStr = settingsRepo.get(key: .referenceMode), let rm = ReferenceMode(rawValue: refModeStr) {
            self.referenceMode = rm
        }
        if let keyStr = settingsRepo.get(key: .keyShiftSemitones), let k = Int(keyStr) {
            self.keyShiftSemitones = k
        }
        if let planStr = settingsRepo.get(key: .planningMode) {
            if let mode = PlanningMode(rawValue: planStr) {
                self.planningMode = mode
            } else if planStr == "symbolic" {
                self.planningMode = .fullGenerated
            } else if planStr == "melody_cover" {
                self.planningMode = .melodySupplied
            } else if planStr == "direct" {
                self.planningMode = .direct
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
        if let stepsStr = settingsRepo.get(key: .yue2FlowSteps), let s = Int(stepsStr) {
            self.yue2FlowSteps = s
        }
        if let mDir = settingsRepo.get(key: .yue2ModelDirectory), !mDir.isEmpty {
            self.yue2ModelDirectory = AppPaths.resolvePath(mDir)
        }
        if let vDir = settingsRepo.get(key: .yue2VAEDirectory), !vDir.isEmpty {
            self.yue2VAEDirectory = AppPaths.resolvePath(vDir)
        }

        self.presetGenres = presetRepo.getGenres()
        self.presetLyrics = presetRepo.getLyrics()
        self.historyRecords = generationRepo.getAll()
        self.modelList = modelRepo.getAll()
        checkModelsAvailability()
    }

    public func setYuE2FlowSteps(_ steps: Int) {
        self.yue2FlowSteps = steps
        settingsRepo.set(key: .yue2FlowSteps, value: "\(steps)")
    }

    public func setYuE2ModelDirectory(_ path: String) {
        self.yue2ModelDirectory = path
        settingsRepo.set(key: .yue2ModelDirectory, value: path)
    }

    public func setYuE2VAEDirectory(_ path: String) {
        self.yue2VAEDirectory = path
        settingsRepo.set(key: .yue2VAEDirectory, value: path)
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

    public func directoryURL(for item: ModelItem) -> URL {
        if item.id == "yue2-3b" {
            return AppPaths.resolveURL(yue2ModelDirectory)
        } else if item.id == "yue2-vae" {
            return AppPaths.resolveURL(yue2VAEDirectory)
        } else {
            let rootURL = AppPaths.resolveURL(modelDirectoryPath)
            if item.localPath.hasPrefix("Models/") {
                let rel = String(item.localPath.dropFirst("Models/".count))
                return rootURL.appendingPathComponent(rel)
            }
            return rootURL.appendingPathComponent(item.stage)
        }
    }

    public func checkModelsAvailability() {
        var allExist = true

        for item in modelList {
            let stageDir = directoryURL(for: item)
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
        let yue2ModelURL = AppPaths.resolveURL(yue2ModelDirectory)
        if !directoryHasWeights(yue2ModelURL) {
            self.missingModelsMessage = "YuE2-3B model weights are not found in '\(yue2ModelURL.path)'. Please go to the Model Manager tab to download YuE2-3B weights, or configure the directory."
            self.showMissingModelsAlert = true
            return
        }
        let yue2VAEURL = AppPaths.resolveURL(yue2VAEDirectory)
        if !directoryHasWeights(yue2VAEURL) {
            self.missingModelsMessage = "YuE2 48kHz VAE weights are not found in '\(yue2VAEURL.path)'. Please go to the Model Manager tab to download YuE2-Vae weights, or configure the directory."
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
        let scoreToUse = (planningMode == .direct) ? nil : currentScore
        let yue2Steps = self.yue2FlowSteps

        Task {
            do {
                let buffer = try await yue2Pipeline.generateSong(
                    prompt: tags,
                    lyrics: currentLyrics,
                    abcScore: scoreToUse,
                    planningMode: planningMode,
                    maxTokens: currentTokens,
                    steps: yue2Steps,
                    temperature: Float(currentTemp),
                    topP: Float(currentTopP),
                    cfgScale: Float(currentCFG),
                    modelDirectory: yue2ModelURL,
                    vaeDirectory: yue2VAEURL
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
            await yue2Pipeline.cancel()
            await MainActor.run {
                self.isGenerating = false
                self.currentProgress = PipelineProgress(phase: .idle, statusMessage: "Generation cancelled.")
            }
        }
    }
}
