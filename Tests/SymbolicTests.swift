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

        // 2. Planning prompt formatting
        let fullPrompt = planner.formatPlanningPrompt(
            genreTags: "acoustic ballad",
            lyrics: "Softly weeping",
            mode: .fullPlan
        )
        XCTAssertTrue(fullPrompt.contains("cot=\"full\""))

        let coverPrompt = planner.formatPlanningPrompt(
            genreTags: "rock cover",
            lyrics: "Never gonna give you up",
            mode: .melodyCover
        )
        XCTAssertTrue(coverPrompt.contains("cot=\"melody\""))

        // 3. Extract score
        let rawOutput = "Here is your plan:\nX: 1\nT: Song\nK: C\n\"C\" c2 e2 |"
        let extracted = planner.extractABCScore(from: rawOutput)
        XCTAssertTrue(extracted.hasPrefix("X: 1"))
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
    }
}
