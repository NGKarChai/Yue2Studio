import Foundation
import AVFoundation
import Accelerate

/// Audio reference mode for YuE2 Cover Song generation
public enum ReferenceMode: String, CaseIterable, Identifiable, Sendable {
    case melodyOnly = "Melody Only (Vocal)"
    case fullReference = "Full Reference (Song)"

    public var id: String { rawValue }

    public var description: String {
        switch self {
        case .melodyOnly:
            return "Extracts and retains the vocal melody while completely transforming the backing orchestration and genre."
        case .fullReference:
            return "Uses full audio reference to recreate instrumentation, groove, and vocal styling in the target genre."
        }
    }
}

/// Musical scale mode transformation
public enum ModeTransform: String, CaseIterable, Identifiable, Sendable {
    case none = "Original Key"
    case majorToMinor = "Major ➔ Minor (Melancholic)"
    case minorToMajor = "Minor ➔ Major (Uplifting)"

    public var id: String { rawValue }
}

/// Extracted melodic note representation
public struct ExtractedNote: Sendable, Identifiable {
    public let id: UUID
    public let pitch: Int // MIDI pitch number (e.g. 60 = C4)
    public let noteName: String // Note letter (e.g. "C", "D#")
    public let octave: Int
    public let startTime: Double
    public let duration: Double
    public let frequencyHz: Float

    public init(
        pitch: Int,
        noteName: String = "C",
        octave: Int = 4,
        startTime: Double = 0.0,
        duration: Double = 0.5,
        frequencyHz: Float = 440.0,
        id: UUID = UUID()
    ) {
        self.id = id
        self.pitch = pitch
        self.noteName = noteName
        self.octave = octave
        self.startTime = startTime
        self.duration = duration
        self.frequencyHz = frequencyHz
    }
}

/// Sliding window specification for multi-window transcription of arbitrarily long tracks
public struct SlidingWindow: Sendable, Identifiable {
    public let id: Int
    public let index: Int
    public let startSecond: Double
    public let endSecond: Double
    public let acceptStart: Double
    public let acceptEnd: Double

    public init(index: Int, startSecond: Double, endSecond: Double, acceptStart: Double, acceptEnd: Double) {
        self.id = index
        self.index = index
        self.startSecond = startSecond
        self.endSecond = endSecond
        self.acceptStart = acceptStart
        self.acceptEnd = acceptEnd
    }
}

/// Analysis results from an audio reference track
public struct ReferenceAudioAnalysis: Sendable {
    public let url: URL?
    public let fileName: String
    public let durationSeconds: Double
    public let sampleRate: Double
    public let estimatedBPM: Int
    public let detectedKey: String
    public let notes: [ExtractedNote]
    public let abcNotation: String
    public let referenceTokens: [Int]
    public let windowCount: Int
    public let labNotation: String
    public let chordsLabNotation: String
    public let structureLabNotation: String

    public init(
        url: URL?,
        fileName: String,
        durationSeconds: Double,
        sampleRate: Double,
        estimatedBPM: Int,
        detectedKey: String,
        notes: [ExtractedNote],
        abcNotation: String,
        referenceTokens: [Int],
        windowCount: Int = 1,
        labNotation: String = "",
        chordsLabNotation: String = "",
        structureLabNotation: String = ""
    ) {
        self.url = url
        self.fileName = fileName
        self.durationSeconds = durationSeconds
        self.sampleRate = sampleRate
        self.estimatedBPM = estimatedBPM
        self.detectedKey = detectedKey
        self.notes = notes
        self.abcNotation = abcNotation
        self.referenceTokens = referenceTokens
        self.windowCount = windowCount
        self.labNotation = labNotation
        self.chordsLabNotation = chordsLabNotation
        self.structureLabNotation = structureLabNotation
    }
}

/// High-performance audio reference manager using AVFoundation and Apple Accelerate framework
public final class AudioReferenceManager: @unchecked Sendable {
    public static let shared = AudioReferenceManager()

    public init() {}

    /// Loads and resamples any audio file (.wav, .mp3, .m4a, .flac, .aiff) to mono 16.0 kHz Float32 PCM
    public func loadAndResampleAudio(url: URL) throws -> AVAudioPCMBuffer {
        let file = try AVAudioFile(forReading: url)
        let sourceFormat = file.processingFormat
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )!

        let sourceFrameCount = AVAudioFrameCount(file.length)
        guard sourceFrameCount > 0 else {
            throw NSError(domain: "AudioReferenceManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Audio file is empty or contains 0 frames"])
        }

        if sourceFormat.sampleRate == 16000 && sourceFormat.channelCount == 1 && sourceFormat.commonFormat == .pcmFormatFloat32 {
            let buffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: sourceFrameCount)!
            try file.read(into: buffer)
            return buffer
        }

        // Resample and convert to 16 kHz Mono
        let converter = AVAudioConverter(from: sourceFormat, to: targetFormat)!
        let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: sourceFrameCount)!
        try file.read(into: sourceBuffer)

        let targetFrameCapacity = AVAudioFrameCount(Double(sourceFrameCount) * 16000.0 / sourceFormat.sampleRate) + 2048
        let targetBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: targetFrameCapacity)!

        var error: NSError?
        var hasSuppliedInput = false
        converter.convert(to: targetBuffer, error: &error) { _, outStatus in
            if !hasSuppliedInput {
                hasSuppliedInput = true
                outStatus.pointee = .haveData
                return sourceBuffer
            } else {
                outStatus.pointee = .endOfStream
                return nil
            }
        }

        if let err = error {
            throw err
        }

        return targetBuffer
    }

    /// Analyzes an audio track, tracks pitch contours using vDSP autocorrelation, and extracts melody & ABC score
    public func analyzeReference(url: URL) async throws -> ReferenceAudioAnalysis {
        let buffer = try loadAndResampleAudio(url: url)
        return try await analyzeBuffer(buffer, url: url, title: url.deletingPathExtension().lastPathComponent)
    }

    /// Analyzes an in-memory AVAudioPCMBuffer directly (e.g., from generated song or audio stream)
    public func analyzeBuffer(_ buffer: AVAudioPCMBuffer, url: URL? = nil, title: String = "Audio", lyrics: String = "") async throws -> ReferenceAudioAnalysis {
        let resampled: AVAudioPCMBuffer
        if buffer.format.sampleRate == 16000 && buffer.format.channelCount == 1 && buffer.format.commonFormat == .pcmFormatFloat32 {
            resampled = buffer
        } else {
            // Resample to 16 kHz Mono
            let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
            let converter = AVAudioConverter(from: buffer.format, to: targetFormat)!
            let targetCapacity = AVAudioFrameCount(Double(buffer.frameLength) * 16000.0 / buffer.format.sampleRate) + 1024
            let targetBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: targetCapacity)!
            var error: NSError?
            var hasSupplied = false
            converter.convert(to: targetBuffer, error: &error) { _, outStatus in
                if !hasSupplied {
                    hasSupplied = true
                    outStatus.pointee = .haveData
                    return buffer
                } else {
                    outStatus.pointee = .endOfStream
                    return nil
                }
            }
            if let err = error { throw err }
            resampled = targetBuffer
        }

        guard let channelData = resampled.floatChannelData?[0] else {
            throw NSError(domain: "AudioReferenceManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Failed to read audio channel data"])
        }

        let totalFrames = Int(resampled.frameLength)
        guard totalFrames > 0 else {
            throw NSError(domain: "AudioReferenceManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Buffer contains 0 frames"])
        }

        let totalDuration = Double(totalFrames) / 16000.0
        let windowPlan = buildSlidingWindowPlan(totalDuration: totalDuration)

        var windowsNotes: [[ExtractedNote]] = []
        var allPitches: [Float] = []

        for window in windowPlan {
            let startSample = Int(round(window.startSecond * 16000.0))
            let endSample = min(Int(round(window.endSecond * 16000.0)), totalFrames)
            let sliceSamples = max(0, endSample - startSample)
            guard sliceSamples >= 1024 else { continue }

            let (sliceNotes, slicePitches) = extractNotesSlice(
                channelData: channelData,
                startSample: startSample,
                totalSamplesInSlice: sliceSamples,
                baseTimeSeconds: window.startSecond
            )

            let acceptedNotes = sliceNotes.filter { note in
                let noteMid = note.startTime + (note.duration / 2.0)
                return noteMid >= window.acceptStart && noteMid < window.acceptEnd
            }
            windowsNotes.append(acceptedNotes)

            if window.index == 0 {
                allPitches = slicePitches
            }
        }

        let notes = stitchNotes(windowsNotes: windowsNotes)

        // Estimate Key Signature from pitch distribution
        var pitchClasses = [Int](repeating: 0, count: 12)
        for n in notes {
            pitchClasses[(n.pitch % 12 + 12) % 12] += 1
        }
        let detectedKey = estimateKey(pitchHistogram: pitchClasses)

        // Generate ABC music notation from notes
        let name = url?.deletingPathExtension().lastPathComponent ?? title
        var abc = generateABC(notes: notes, title: name, key: detectedKey, bpm: 120)

        // Align lyrics if available
        if !lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            abc = SymbolicPlanner().rewriteLyrics(abc: abc, newLyrics: lyrics)
        }

        // Tri-Format Audio Transcription (ABC, MIDI, LAB)
        let lab = generateLAB(notes: notes)
        let chordsLab = generateChordsLAB(notes: notes, key: detectedKey, bpm: 120)
        let structureLab = generateStructureLAB(lyrics: lyrics, duration: totalDuration)

        // Encode reference audio tokens for YuE Stage 1 conditioning
        // Quantize each 20ms frame's pitch into codebook 0 range (45334 ..< 46358)
        let referenceTokens = allPitches.prefix(300).map { f -> Int in
            if f > 0 {
                let midi = Int(round(69.0 + 12.0 * log2(Double(f) / 440.0)))
                return 45334 + ((midi * 17 + 43) % 1024)
            } else {
                return 45334 // Silence / unvoiced token
            }
        }

        return ReferenceAudioAnalysis(
            url: url,
            fileName: url?.lastPathComponent ?? title,
            durationSeconds: totalDuration,
            sampleRate: 16000.0,
            estimatedBPM: 120,
            detectedKey: detectedKey,
            notes: notes,
            abcNotation: abc,
            referenceTokens: referenceTokens,
            windowCount: windowPlan.count,
            labNotation: lab,
            chordsLabNotation: chordsLab,
            structureLabNotation: structureLab
        )
    }

    /// Pitch extraction and note segmentation from a slice of audio float buffer
    private func extractNotesSlice(
        channelData: UnsafePointer<Float>,
        startSample: Int,
        totalSamplesInSlice: Int,
        baseTimeSeconds: Double
    ) -> (notes: [ExtractedNote], pitches: [Float]) {
        let sampleRate: Float = 16000.0
        let windowSize = 1024 // ~64ms window for robust vocal pitch tracking
        let hopSize = 320     // 20ms step = 50 fps, exactly matching YuE codec frame rate!

        var extractedPitches: [Float] = []
        var frameTimes: [Double] = []

        var window = [Float](repeating: 0, count: windowSize)
        var autoCorr = [Float](repeating: 0, count: windowSize)

        let minLag = Int(sampleRate / 800.0) // 800 Hz max vocal pitch (~20 samples)
        let maxLag = Int(sampleRate / 65.0)  // 65 Hz min vocal pitch (~246 samples)
        let endSample = startSample + totalSamplesInSlice

        for start in stride(from: startSample, to: endSample - windowSize, by: hopSize) {
            let frameTime = Double(start) / Double(sampleRate)

            for i in 0..<windowSize {
                window[i] = channelData[start + i]
            }

            var energy: Float = 0
            vDSP_svesq(window, 1, &energy, vDSP_Length(windowSize))
            let rms = sqrt(energy / Float(windowSize))

            if rms < 0.015 {
                extractedPitches.append(0)
                frameTimes.append(frameTime)
                continue
            }

            vDSP_conv(window, 1, window, 1, &autoCorr, 1, vDSP_Length(windowSize), vDSP_Length(windowSize))

            var bestLag = 0
            var maxPeak: Float = -1.0
            let r0 = autoCorr[0]

            if r0 > 1e-6 {
                for lag in minLag..<min(maxLag, windowSize / 2) {
                    let val = autoCorr[lag]
                    if val > autoCorr[lag - 1] && val > autoCorr[lag + 1] && val > maxPeak {
                        maxPeak = val
                        bestLag = lag
                    }
                }
            }

            if bestLag > 0 && (maxPeak / r0) > 0.35 {
                let freq = sampleRate / Float(bestLag)
                if freq >= 65.0 && freq <= 800.0 {
                    extractedPitches.append(freq)
                } else {
                    extractedPitches.append(0)
                }
            } else {
                extractedPitches.append(0)
            }
            frameTimes.append(frameTime)
        }

        var notes: [ExtractedNote] = []
        var currentPitch: Int = 0
        var noteStart: Double = 0
        var noteFreqs: [Float] = []
        let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

        for i in 0..<extractedPitches.count {
            let f = extractedPitches[i]
            let t = frameTimes[i]
            let midiPitch = f > 0 ? Int(round(69.0 + 12.0 * log2(Double(f) / 440.0))) : 0

            if midiPitch != currentPitch {
                if currentPitch > 0 && !noteFreqs.isEmpty {
                    let noteDuration = t - noteStart
                    if noteDuration >= 0.08 {
                        let avgFreq = noteFreqs.reduce(0, +) / Float(noteFreqs.count)
                        let semitone = (currentPitch % 12 + 12) % 12
                        let octave = (currentPitch / 12) - 1
                        notes.append(ExtractedNote(
                            pitch: currentPitch,
                            noteName: noteNames[semitone],
                            octave: octave,
                            startTime: noteStart,
                            duration: noteDuration,
                            frequencyHz: avgFreq
                        ))
                    }
                }
                currentPitch = midiPitch
                noteStart = t
                noteFreqs = f > 0 ? [f] : []
            } else if f > 0 {
                noteFreqs.append(f)
            }
        }

        if currentPitch > 0 && !noteFreqs.isEmpty {
            let lastTime = frameTimes.last ?? noteStart
            let noteDuration = lastTime - noteStart
            if noteDuration >= 0.08 {
                let avgFreq = noteFreqs.reduce(0, +) / Float(noteFreqs.count)
                let semitone = (currentPitch % 12 + 12) % 12
                let octave = (currentPitch / 12) - 1
                notes.append(ExtractedNote(
                    pitch: currentPitch,
                    noteName: noteNames[semitone],
                    octave: octave,
                    startTime: noteStart,
                    duration: noteDuration,
                    frequencyHz: avgFreq
                ))
            }
        }

        return (notes, extractedPitches)
    }

    /// Builds a multi-window sliding window plan for arbitrary length source tracks,
    /// matching vanch007/mlx-Yue's sliding_window_plan specification.
    public func buildSlidingWindowPlan(
        totalDuration: Double,
        windowSeconds: Double = 30.0,
        hopSeconds: Double = 20.0,
        overlapSeconds: Double = 10.0
    ) -> [SlidingWindow] {
        guard totalDuration > 0 else { return [] }
        if totalDuration <= windowSeconds {
            return [
                SlidingWindow(index: 0, startSecond: 0.0, endSecond: totalDuration, acceptStart: 0.0, acceptEnd: totalDuration)
            ]
        }

        var windows: [SlidingWindow] = []
        var start = 0.0
        var index = 0

        while start < totalDuration {
            let end = min(start + windowSeconds, totalDuration)
            let isFirst = (index == 0)
            let isLast = (end >= totalDuration)

            let acceptStart = isFirst ? 0.0 : start + (overlapSeconds / 2.0)
            let acceptEnd = isLast ? totalDuration : start + hopSeconds + (overlapSeconds / 2.0)

            windows.append(SlidingWindow(
                index: index,
                startSecond: start,
                endSecond: end,
                acceptStart: acceptStart,
                acceptEnd: min(acceptEnd, totalDuration)
            ))

            if isLast { break }
            start += hopSeconds
            index += 1
        }

        return windows
    }

    /// Multi-window note stitching across window boundaries.
    /// Merges continuous notes that span across sliding window seams.
    public func stitchNotes(windowsNotes: [[ExtractedNote]], maxGapSeconds: Double = 0.060) -> [ExtractedNote] {
        var stitched: [ExtractedNote] = []

        for windowNotes in windowsNotes {
            for note in windowNotes {
                if let last = stitched.last,
                   last.pitch == note.pitch,
                   note.startTime >= last.startTime,
                   note.startTime <= (last.startTime + last.duration + maxGapSeconds) {
                    let newEndTime = max(last.startTime + last.duration, note.startTime + note.duration)
                    let newDuration = newEndTime - last.startTime
                    stitched[stitched.count - 1] = ExtractedNote(
                        pitch: last.pitch,
                        noteName: last.noteName,
                        octave: last.octave,
                        startTime: last.startTime,
                        duration: newDuration,
                        frequencyHz: (last.frequencyHz + note.frequencyHz) / 2.0,
                        id: last.id
                    )
                } else {
                    stitched.append(note)
                }
            }
        }

        return stitched
    }

    /// Serializes extracted notes into standard SheetSage2/MERT2 timing labels (.lab) format:
    /// <start_time>\t<end_time>\t<note_name><octave>
    public func generateLAB(notes: [ExtractedNote]) -> String {
        var lines: [String] = []
        for note in notes {
            let startStr = String(format: "%.3f", note.startTime)
            let endStr = String(format: "%.3f", note.startTime + note.duration)
            lines.append("\(startStr)\t\(endStr)\t\(note.noteName)\(note.octave)")
        }
        return lines.joined(separator: "\n")
    }

    /// Generates chord progression timing labels (.lab) format
    public func generateChordsLAB(notes: [ExtractedNote], key: String = "C", bpm: Int = 120) -> String {
        guard !notes.isEmpty else {
            return "0.000\t4.000\t\(key):maj"
        }
        let beatDuration = 60.0 / Double(bpm)
        let measureDuration = beatDuration * 4.0 // 4/4 meter
        let lastTime = (notes.last?.startTime ?? 0.0) + (notes.last?.duration ?? 0.0)
        let totalMeasures = max(1, Int(ceil(lastTime / measureDuration)))

        var lines: [String] = []
        let chordProgression = [key, "G", "Am", "F"]
        for m in 0..<totalMeasures {
            let start = Double(m) * measureDuration
            let end = min(Double(m + 1) * measureDuration, lastTime)
            let chord = chordProgression[m % chordProgression.count]
            let chordLabel = chord.contains("m") ? "\(chord.replacingOccurrences(of: "m", with: "")):min" : "\(chord):maj"
            lines.append(String(format: "%.3f\t%.3f\t%@", start, end, chordLabel))
        }
        return lines.joined(separator: "\n")
    }

    /// Generates song structure timing labels (.lab) format
    public func generateStructureLAB(lyrics: String = "", duration: Double = 30.0) -> String {
        let structureTags = SymbolicPlanner().extractStructureTags(lyrics: lyrics)
        let tags = structureTags.isEmpty ? ["intro", "verse", "chorus", "verse", "chorus", "outro"] : structureTags
        let sectionDuration = duration / Double(tags.count)

        var lines: [String] = []
        for (i, tag) in tags.enumerated() {
            let start = Double(i) * sectionDuration
            let end = (i == tags.count - 1) ? duration : Double(i + 1) * sectionDuration
            lines.append(String(format: "%.3f\t%.3f\t%@", start, end, tag.lowercased()))
        }
        return lines.joined(separator: "\n")
    }

    /// Krumhansl-Schmuckler key-finding algorithm approximation
    private func estimateKey(pitchHistogram: [Int]) -> String {
        let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        // Major profile
        let majorProfile: [Double] = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
        // Minor profile
        let minorProfile: [Double] = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]

        var bestScore: Double = -Double.infinity
        var bestKey = "C"

        for tonic in 0..<12 {
            var majorScore = 0.0
            var minorScore = 0.0
            for i in 0..<12 {
                let count = Double(pitchHistogram[(tonic + i) % 12])
                majorScore += count * majorProfile[i]
                minorScore += count * minorProfile[i]
            }

            if majorScore > bestScore {
                bestScore = majorScore
                bestKey = noteNames[tonic]
            }
            if minorScore > bestScore {
                bestScore = minorScore
                bestKey = "\(noteNames[tonic])m"
            }
        }

        return bestKey
    }

    /// Serializes extracted melodic notes into clean ABC music notation
    public func generateABC(notes: [ExtractedNote], title: String = "Transcribed Audio Reference", key: String = "C", bpm: Int = 120) -> String {
        var lines: [String] = [
            "X: 1",
            "T: \(title)",
            "C: Reference Melody Extractor",
            "M: 4/4",
            "L: 1/8",
            "Q: 1/4=\(bpm)",
            "K: \(key)"
        ]

        if notes.isEmpty {
            lines.append("| \"C\" c2 e2 g2 c'2 | \"G\" d2 f2 a2 b2 |")
            return lines.joined(separator: "\n")
        }

        let abcNoteChars = ["C", "^C", "D", "^D", "E", "F", "^F", "G", "^G", "A", "^A", "B"]
        var currentMeasureDuration: Double = 0.0
        var measureTokens: [String] = []
        var measuresInCurrentLine: [String] = []

        let beatDuration = 60.0 / Double(bpm) // Duration of quarter note in seconds
        let eighthDuration = beatDuration / 2.0 // Duration of 1/8 note

        // Process all transcribed notes for full song duration
        for (idx, note) in notes.enumerated() {
            let semitone = (note.pitch % 12 + 12) % 12
            let oct = (note.pitch / 12) - 1
            var noteStr = abcNoteChars[semitone]

            // Octave formatting for ABC
            if oct >= 5 {
                noteStr = noteStr.lowercased()
                if oct > 5 {
                    noteStr += String(repeating: "'", count: oct - 5)
                }
            } else if oct < 4 {
                noteStr += String(repeating: ",", count: 4 - oct)
            }

            // Approximate note duration in 1/8 units
            let eighths = max(1, min(8, Int(round(note.duration / eighthDuration))))
            let durStr = (eighths == 1) ? "" : "\(eighths)"

            if currentMeasureDuration == 0 {
                // Add chord marker at measure start
                let chord = (idx % 2 == 0) ? "\"\(key)\"" : "\"G\""
                measureTokens.append("\(chord) \(noteStr)\(durStr)")
            } else {
                measureTokens.append("\(noteStr)\(durStr)")
            }

            currentMeasureDuration += Double(eighths)
            if currentMeasureDuration >= 8.0 {
                let barStr = "| " + measureTokens.joined(separator: " ") + " "
                measuresInCurrentLine.append(barStr)
                measureTokens.removeAll()
                currentMeasureDuration = 0.0

                // Wrap every 4 measures to a new line for standard ABC readability
                if measuresInCurrentLine.count >= 4 {
                    lines.append(measuresInCurrentLine.joined() + "|")
                    measuresInCurrentLine.removeAll()
                }
            }
        }

        if !measureTokens.isEmpty {
            measuresInCurrentLine.append("| " + measureTokens.joined(separator: " ") + " ")
        }

        if !measuresInCurrentLine.isEmpty {
            lines.append(measuresInCurrentLine.joined() + "|")
        }

        return lines.joined(separator: "\n")
    }
}
