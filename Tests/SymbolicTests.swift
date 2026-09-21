import XCTest
import AVFoundation
@testable import Yue2Studio

final class SymbolicTests: XCTestCase {
    let sampleABC = """
    X: 1
    T: Melody in C Major
    C: YuE2 AI
    M: 4/4
    L: 1/8
    Q: 1/4=120
    K: C
    "C" C2 E2 G2 c2 | "G" D2 F2 A2 B2 |
    w: Sing-ing in the sun | Fly-ing in the sky |
    """

    func testABCParser() throws {
        let parser = ABCParser()
        let score = parser.parse(abcString: sampleABC)

        XCTAssertEqual(score.title, "Melody in C Major")
        XCTAssertEqual(score.composer, "YuE2 AI")
        XCTAssertEqual(score.meter.beats, 4)
        XCTAssertEqual(score.meter.beatType, 4)
        XCTAssertEqual(score.tempoBpm, 120)
        XCTAssertEqual(score.keySignature, "C")
        XCTAssertEqual(score.measures.count, 2)

        let m1 = score.measures[0]
        XCTAssertEqual(m1.notes.count, 4)
        XCTAssertEqual(m1.notes[0].pitch?.step, "C")
        XCTAssertEqual(m1.notes[0].pitch?.octave, 4)
        XCTAssertEqual(m1.notes[0].chord, "C")
        XCTAssertEqual(m1.notes[0].lyricSyllable, "Sing")
        XCTAssertEqual(m1.notes[1].lyricSyllable, "ing")

        let m2 = score.measures[1]
        XCTAssertEqual(m2.notes.count, 4)
        XCTAssertEqual(m2.notes[0].pitch?.step, "D")
        XCTAssertEqual(m2.notes[0].chord, "G")
    }

    func testMIDIExporter() throws {
        let parser = ABCParser()
        let score = parser.parse(abcString: sampleABC)
        let exporter = MIDIExporter()
        let midiData = exporter.export(score: score)

        XCTAssertFalse(midiData.isEmpty)
        XCTAssertGreaterThan(midiData.count, 32)

        // Verify SMF Header "MThd"
        let headerPrefix = String(data: midiData.subdata(in: 0..<4), encoding: .ascii)
        XCTAssertEqual(headerPrefix, "MThd")

        // Verify Header Length = 6
        let headerLength = midiData[4...7].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        XCTAssertEqual(headerLength, 6)

        // Verify SMF Format 1
        let format = midiData[8...9].withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
        XCTAssertEqual(format, 1)

        // Verify 3 Tracks (Conductor, Vocal Melody, Harmonic Chords)
        let tracksCount = midiData[10...11].withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
        XCTAssertEqual(tracksCount, 3)

        // Verify Division = 480 ticks per quarter
        let division = midiData[12...13].withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
        XCTAssertEqual(division, 480)

        // Verify Track Chunk "MTrk" exists in data
        let trackPrefix = String(data: midiData.subdata(in: 14..<18), encoding: .ascii)
        XCTAssertEqual(trackPrefix, "MTrk")

        // Verify that CoreAudio AVMIDIPlayer can load and play the generated MIDI file
        let player = try AVMIDIPlayer(data: midiData, soundBankURL: nil)
        player.prepareToPlay()
        XCTAssertGreaterThan(player.duration, 0.0, "MIDI player should calculate valid duration")
    }

    func testMusicXMLExporter() throws {
        let parser = ABCParser()
        let score = parser.parse(abcString: sampleABC)
        let exporter = MusicXMLExporter()
        let xml = exporter.export(score: score)

        XCTAssertTrue(xml.contains("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"))
        XCTAssertTrue(xml.contains("<!DOCTYPE score-partwise PUBLIC"))
        XCTAssertTrue(xml.contains("<work-title>Melody in C Major</work-title>"))
        XCTAssertTrue(xml.contains("<creator type=\"composer\">YuE2 AI</creator>"))
        XCTAssertTrue(xml.contains("<beats>4</beats>"))
        XCTAssertTrue(xml.contains("<beat-type>4</beat-type>"))
        XCTAssertTrue(xml.contains("<sound tempo=\"120\"/>"))
        XCTAssertTrue(xml.contains("<step>C</step>"))
        XCTAssertTrue(xml.contains("<harmony>"))
        XCTAssertTrue(xml.contains("<root-step>C</root-step>"))
        XCTAssertTrue(xml.contains("<text>Sing</text>"))
    }

    func testSymbolicPlanner() throws {
        let planner = SymbolicPlanner()

        // 1. Starter template generation
        let template = planner.generateStarterTemplate(
            title: "Summer Vibes",
            genreTags: "upbeat pop, synth",
            lyrics: "[verse]\nWalking down the sunny street\nFeeling every happy beat"
        )
        XCTAssertTrue(template.contains("T: Summer Vibes"))
        XCTAssertTrue(template.contains("K: C"))
        XCTAssertTrue(template.contains("M: 4/4"))
        XCTAssertTrue(template.contains("w: Walking-down-the-sunny-street |"))

        // 2. Planning prompt formatting with official YuE2 protocol instructions
        let fullPrompt = planner.formatPlanningPrompt(
            genreTags: "acoustic ballad",
            lyrics: "Softly weeping",
            mode: .fullGenerated
        )
        XCTAssertTrue(fullPrompt.contains("Generate a chord-annotated ABC transcription"))
        XCTAssertTrue(fullPrompt.contains("[Tags]\nacoustic ballad"))

        let melodyPrompt = planner.formatPlanningPrompt(
            genreTags: "rock cover",
            lyrics: "Never gonna give you up",
            mode: .melodyGenerated
        )
        XCTAssertTrue(melodyPrompt.contains("Generate a melody-only ABC transcription without chord symbols"))

        let directPrompt = planner.formatPlanningPrompt(
            genreTags: "electronic trance",
            lyrics: "Dance all night",
            mode: .direct
        )
        XCTAssertTrue(directPrompt.contains("Generate music with codec tokens from the given conditions."))

        // Verify all 5 official modes exist
        XCTAssertEqual(PlanningMode.allCases.count, 5)

        // 3. Extract score
        let rawOutput = "Here is your plan:\nX: 1\nT: Song\nK: C\n\"C\" c2 e2 |"
        let extracted = planner.extractABCScore(from: rawOutput)
        XCTAssertTrue(extracted.hasPrefix("X: 1"))
    }

    func testChordParsingAndMIDIPlayback() throws {
        let exporter = MIDIExporter()

        // Test B-root and flat/sharp chord parsing
        let bm = exporter.chordToMidi("Bm")
        XCTAssertNotNil(bm, "Bm chord must be parsed correctly")
        XCTAssertEqual(bm, [59, 62, 66], "Bm is B(59), D(62), F#(66)")

        let bb = exporter.chordToMidi("Bb")
        XCTAssertNotNil(bb, "Bb chord must be parsed correctly")
        XCTAssertEqual(bb, [58, 62, 65], "Bb is Bb(58), D(62), F(65)")

        let b7 = exporter.chordToMidi("B7")
        XCTAssertNotNil(b7, "B7 chord must be parsed correctly")
        XCTAssertEqual(b7, [59, 63, 66, 69])

        let fsharpM = exporter.chordToMidi("F#m")
        XCTAssertNotNil(fsharpM, "F#m chord must be parsed correctly")
        XCTAssertEqual(fsharpM, [54, 57, 61])

        // Verify full song ABC with Bm chord exports to valid playable MIDI
        let abcWithChords = """
        X: 1
        T: Song with Chords
        M: 4/4
        L: 1/8
        Q: 1/4=120
        K: D
        | "Bm" B2 d2 f2 b2 | "G" g2 b2 d'2 g2 | "D" f2 a2 d'2 f2 | "A" e2 a2 c'2 e2 |
        """
        let parser = ABCParser()
        let score = parser.parse(abcString: abcWithChords)
        let midiData = exporter.export(score: score)

        XCTAssertFalse(midiData.isEmpty)

        // Verify CoreAudio AVMIDIPlayer loads and plays without error
        let player = try AVMIDIPlayer(data: midiData, soundBankURL: nil)
        player.prepareToPlay()
        XCTAssertGreaterThan(player.duration, 0.0)
    }

    func testFullABCScoreGenerationNoTruncation() {
        // Test that AudioReferenceManager transcribes full song beyond 32 notes
        var notes: [ExtractedNote] = []
        for i in 0..<120 {
            notes.append(ExtractedNote(pitch: 60 + (i % 12), startTime: Double(i) * 0.5, duration: 0.5))
        }

        let abc = AudioReferenceManager.shared.generateABC(notes: notes, title: "Transcribed Audio Reference", key: "C", bpm: 120)
        XCTAssertFalse(abc.isEmpty)
        XCTAssertTrue(abc.contains("X: 1"))
        XCTAssertTrue(abc.contains("T: Transcribed Audio Reference"))

        // Count bar lines to ensure all 120 notes are preserved across multiple lines
        let barCount = abc.components(separatedBy: "|").count - 1
        XCTAssertGreaterThan(barCount, 25, "All 120 notes must be transcribed into measures without 32-note cap")

        // Test SymbolicPlanner starter template with multiple sections
        let lyrics = """
        [verse 1]
        Line one of the verse
        Line two of the verse
        [chorus]
        This is the chorus line
        Singing loud and fine
        [verse 2]
        Another line of verse
        Walking on the earth
        [outro]
        Fading out now
        """
        let template = SymbolicPlanner().generateStarterTemplate(title: "Complete Song", genreTags: "pop", lyrics: lyrics)
        XCTAssertTrue(template.contains("% verse 1"))
        XCTAssertTrue(template.contains("% chorus"))
        XCTAssertTrue(template.contains("% verse 2"))
        XCTAssertTrue(template.contains("% outro"))
        XCTAssertTrue(template.contains("w: Line-one-of-the-verse |"))
        XCTAssertTrue(template.contains("w: This-is-the-chorus-line |"))
        XCTAssertTrue(template.contains("w: Fading-out-now |"))
    }

    func testKeyTransposition() {
        let planner = SymbolicPlanner()
        let original = """
        X: 1
        T: Test Transpose
        K: C
        "C" C2 E2 G2 | "G" D2 F2 B2 |
        """

        // Transpose up 2 semitones: C -> D, G -> A
        let transposed = planner.transpose(abc: original, semitones: 2)
        XCTAssertTrue(transposed.contains("K: D"))
        XCTAssertTrue(transposed.contains("\"D\""))
        XCTAssertTrue(transposed.contains("\"A\""))
    }

    func testMajorMinorModulation() {
        let planner = SymbolicPlanner()
        let original = """
        X: 1
        T: Test Mode
        K: C
        "C" c2 e2 g2 | "G" d2 b2 |
        """

        // Convert Major to Minor
        let minor = planner.modulateMode(abc: original, transform: .majorToMinor)
        XCTAssertTrue(minor.contains("K: Cm"))
        XCTAssertTrue(minor.contains("\"Cm\""))
        XCTAssertTrue(minor.contains("\"Gm\""))
        XCTAssertTrue(minor.contains("_e2"))
        XCTAssertTrue(minor.contains("_b2"))

        // Convert back Minor to Major
        let major = planner.modulateMode(abc: minor, transform: .minorToMajor)
        XCTAssertTrue(major.contains("K: C"))
        XCTAssertTrue(major.contains("\"C\""))
    }

    func testLyricRealignment() {
        let planner = SymbolicPlanner()
        let original = """
        X: 1
        T: Test Lyrics
        K: C
        "C" C2 E2 G2 c2 |
        w: Old-lyr-ics-here |
        """

        let rewritten = planner.rewriteLyrics(abc: original, newLyrics: "Silver moon in the sky")
        XCTAssertFalse(rewritten.contains("Old-lyr-ics-here"))
        XCTAssertTrue(rewritten.contains("Silver-moon-in-the"))
    }

    func testAudioReferenceManager() async throws {
        let manager = AudioReferenceManager()
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_sine_440.wav")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // Create 1 second 440Hz synthetic sine wave mono at 44100 Hz (also tests resampling from 44.1k to 16k)
        let sampleRate: Double = 44100.0
        let duration: Double = 1.0
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let channel = buffer.floatChannelData![0]
        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            channel[i] = Float(sin(2.0 * .pi * 440.0 * t))
        }

        do {
            let audioFile = try AVAudioFile(forWriting: tempURL, settings: format.settings)
            try audioFile.write(from: buffer)
        }

        // Resample test
        let resampled = try manager.loadAndResampleAudio(url: tempURL)
        XCTAssertEqual(resampled.format.sampleRate, 16000)
        XCTAssertEqual(resampled.format.channelCount, 1)

        // Pitch tracking & ABC generation test
        let analysis = try await manager.analyzeReference(url: tempURL)
        XCTAssertGreaterThan(analysis.durationSeconds, 0.8)
        XCTAssertFalse(analysis.abcNotation.isEmpty)
        XCTAssertFalse(analysis.referenceTokens.isEmpty)
        XCTAssertEqual(analysis.windowCount, 1)
        XCTAssertFalse(analysis.labNotation.isEmpty)
        XCTAssertFalse(analysis.chordsLabNotation.isEmpty)
        XCTAssertFalse(analysis.structureLabNotation.isEmpty)
    }

    func testSlidingWindowPlan() {
        let manager = AudioReferenceManager.shared

        // Test 1: Short track (20s) -> 1 single window
        let plan20 = manager.buildSlidingWindowPlan(totalDuration: 20.0, windowSeconds: 30.0, hopSeconds: 20.0, overlapSeconds: 10.0)
        XCTAssertEqual(plan20.count, 1)
        XCTAssertEqual(plan20[0].startSecond, 0.0)
        XCTAssertEqual(plan20[0].endSecond, 20.0)
        XCTAssertEqual(plan20[0].acceptStart, 0.0)
        XCTAssertEqual(plan20[0].acceptEnd, 20.0)

        // Test 2: Arbitrarily long track (100s) -> Multi-window plan
        let plan100 = manager.buildSlidingWindowPlan(totalDuration: 100.0, windowSeconds: 30.0, hopSeconds: 20.0, overlapSeconds: 10.0)
        XCTAssertGreaterThan(plan100.count, 3)

        // First window starts at 0.0, accepts from 0.0
        XCTAssertEqual(plan100[0].startSecond, 0.0)
        XCTAssertEqual(plan100[0].acceptStart, 0.0)
        XCTAssertEqual(plan100[0].acceptEnd, 25.0)

        // Second window starts at 20.0, accepts from 25.0 to 45.0
        XCTAssertEqual(plan100[1].startSecond, 20.0)
        XCTAssertEqual(plan100[1].acceptStart, 25.0)
        XCTAssertEqual(plan100[1].acceptEnd, 45.0)

        // Last window accepts all the way to 100.0
        XCTAssertEqual(plan100.last?.endSecond, 100.0)
        XCTAssertEqual(plan100.last?.acceptEnd, 100.0)
    }

    func testNoteStitching() {
        let manager = AudioReferenceManager.shared

        // Window 1 notes
        let w1Notes = [
            ExtractedNote(pitch: 60, noteName: "C", octave: 4, startTime: 0.0, duration: 1.0),
            ExtractedNote(pitch: 64, noteName: "E", octave: 4, startTime: 1.0, duration: 1.5) // ends at 2.5s
        ]

        // Window 2 notes: same E4 note continues across seam starting at 2.52s (gap = 20ms < 60ms)
        let w2Notes = [
            ExtractedNote(pitch: 64, noteName: "E", octave: 4, startTime: 2.52, duration: 1.0), // should merge with E4!
            ExtractedNote(pitch: 67, noteName: "G", octave: 4, startTime: 3.6, duration: 0.8)
        ]

        let stitched = manager.stitchNotes(windowsNotes: [w1Notes, w2Notes], maxGapSeconds: 0.060)

        // Originally 4 notes -> after stitching seam-spanning E4 note -> 3 notes
        XCTAssertEqual(stitched.count, 3)
        XCTAssertEqual(stitched[0].pitch, 60)
        XCTAssertEqual(stitched[1].pitch, 64)
        XCTAssertEqual(stitched[1].startTime, 1.0)
        XCTAssertEqual(stitched[1].duration, 2.52) // 1.0 to (2.52 + 1.0) = 2.52 duration
        XCTAssertEqual(stitched[2].pitch, 67)
    }

    func testLABFormatGeneration() {
        let manager = AudioReferenceManager.shared

        let notes = [
            ExtractedNote(pitch: 60, noteName: "C", octave: 4, startTime: 0.0, duration: 0.5),
            ExtractedNote(pitch: 64, noteName: "E", octave: 4, startTime: 0.5, duration: 0.75),
            ExtractedNote(pitch: 67, noteName: "G", octave: 4, startTime: 1.25, duration: 1.0)
        ]

        // 1. Note Timing LAB (.lab)
        let notesLAB = manager.generateLAB(notes: notes)
        XCTAssertTrue(notesLAB.contains("0.000\t0.500\tC4"))
        XCTAssertTrue(notesLAB.contains("0.500\t1.250\tE4"))
        XCTAssertTrue(notesLAB.contains("1.250\t2.250\tG4"))

        // 2. Chords Timing LAB (.lab)
        let chordsLAB = manager.generateChordsLAB(notes: notes, key: "C", bpm: 120)
        XCTAssertTrue(chordsLAB.contains("0.000\t2.000\tC:maj"))

        // 3. Song Structure LAB (.lab)
        let structureLAB = manager.generateStructureLAB(lyrics: "[intro]\nSoft piano\n[verse]\nWalking down the road\n[chorus]\nSinging loud", duration: 60.0)
        XCTAssertTrue(structureLAB.contains("intro"))
        XCTAssertTrue(structureLAB.contains("verse"))
        XCTAssertTrue(structureLAB.contains("chorus"))
    }

    func testEndToEndCoverPipeline() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let state = AppState()

        // Supply reference analysis
        let notes = [
            ExtractedNote(pitch: 60, noteName: "C", octave: 4, startTime: 0.0, duration: 0.5),
            ExtractedNote(pitch: 64, noteName: "E", octave: 4, startTime: 0.5, duration: 0.5),
            ExtractedNote(pitch: 67, noteName: "G", octave: 4, startTime: 1.0, duration: 0.5),
            ExtractedNote(pitch: 72, noteName: "C", octave: 5, startTime: 1.5, duration: 0.5)
        ]
        let analysis = ReferenceAudioAnalysis(
            url: nil,
            fileName: "OriginalHit.wav",
            durationSeconds: 2.0,
            sampleRate: 16000.0,
            estimatedBPM: 120,
            detectedKey: "C",
            notes: notes,
            abcNotation: "X: 1\nT: Original Hit\nK: C\n\"C\" C2 E2 G2 c2 |",
            referenceTokens: [45334, 45350],
            windowCount: 1,
            labNotation: "0.000\t0.500\tC4\n0.500\t1.000\tE4\n1.000\t1.500\tG4\n1.500\t2.000\tC5",
            chordsLabNotation: "0.000\t2.000\tC:maj",
            structureLabNotation: "0.000\t2.000\tintro"
        )
        state.referenceAnalysis = analysis
        state.referenceAudioName = "OriginalHit.wav"

        // Execute 1-click cover pipeline priming with target style
        state.prepareCoverPipeline(targetGenre: "80s synthwave, driving linndrum, analog synth, neon pads, female vocal, 124 bpm")

        // Verify pipeline state
        XCTAssertEqual(state.planningMode, .melodySupplied)
        XCTAssertEqual(state.genreTags, "80s synthwave, driving linndrum, analog synth, neon pads, female vocal, 124 bpm")
        XCTAssertTrue(state.songTitle.contains("OriginalHit"))
        XCTAssertEqual(state.currentScore, analysis.abcNotation)

        // Verify Tri-Format Bundle Export (ABC + MIDI + LAB)
        let exported = try state.exportTranscriptionBundle(directory: tempDir, baseName: "OriginalHit_Cover")
        XCTAssertEqual(exported.count, 5)

        for file in exported {
            XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
            let attr = try FileManager.default.attributesOfItem(atPath: file.path)
            let size = attr[.size] as? Int64 ?? 0
            XCTAssertGreaterThan(size, 0, "Exported bundle file \(file.lastPathComponent) must not be empty")
        }
    }
}
