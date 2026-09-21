import Foundation

/// Planning mode for YuE2 composition pipeline matching official vanch007/mlx-Yue specification
public enum PlanningMode: String, CaseIterable, Identifiable, Sendable {
    case fullGenerated = "Full + Generated Score"
    case fullSupplied = "Full + Supplied ABC Score"
    case melodyGenerated = "Melody + Generated Score"
    case melodySupplied = "Melody + Supplied ABC Score"
    case direct = "Off (Direct Generation)"

    // Backward compatibility aliases
    public static var fullPlan: PlanningMode { .fullGenerated }
    public static var melodyCover: PlanningMode { .melodySupplied }
    public static var directAudio: PlanningMode { .direct }

    public var id: String { rawValue }

    /// Chain-of-Thought mode: "full", "melody", or "off"
    public var cot: String {
        switch self {
        case .fullGenerated, .fullSupplied:
            return "full"
        case .melodyGenerated, .melodySupplied:
            return "melody"
        case .direct:
            return "off"
        }
    }

    /// Whether this mode conditions generation on user-supplied or transcribed ABC score
    public var isSupplied: Bool {
        return self == .fullSupplied || self == .melodySupplied
    }

    /// Official YuE2 prompt instruction directive
    public var instruction: String {
        switch cot {
        case "off":
            return "Generate music with codec tokens from the given conditions."
        case "melody":
            return "Generate a melody-only ABC transcription without chord symbols, then generate music with codec tokens from the given conditions."
        case "full":
            return "Generate a chord-annotated ABC transcription, then generate music with codec tokens from the given conditions."
        default:
            return "Generate music with codec tokens from the given conditions."
        }
    }

    public var description: String {
        switch self {
        case .fullGenerated:
            return "Fully automated song writing, score planning, and 48kHz audio generation from text prompt & lyrics."
        case .fullSupplied:
            return "Compose songs conditioned on user-supplied ABC notation (melody + chords)."
        case .melodyGenerated:
            return "Automatic lead-sheet melody generation and vocal/melody arrangement."
        case .melodySupplied:
            return "Condition acoustic synthesis on an exact melody line from your supplied ABC score or transcribed audio."
        case .direct:
            return "Generate music directly from style and lyrics without a symbolic score (includes vocals)."
        }
    }
}

/// Manages YuE2 Symbolic Planning, score generation, and cover mode preparation
public final class SymbolicPlanner: @unchecked Sendable {
    private let parser: ABCParser
    private let midiExporter: MIDIExporter
    private let xmlExporter: MusicXMLExporter

    public init() {
        self.parser = ABCParser()
        self.midiExporter = MIDIExporter()
        self.xmlExporter = MusicXMLExporter()
    }

    /// Formats prompt for Symbolic Planning according to official YuE2 specification
    public func formatPlanningPrompt(genreTags: String, lyrics: String, mode: PlanningMode) -> String {
        return "\(mode.instruction)\n[Tags]\n\(genreTags)\n[Lyrics]\n\(lyrics)\n"
    }

    /// Extracts ABC notation block from model generation output
    public func extractABCScore(from text: String) -> String {
        // Find start of ABC block ("X:" or "T:" or "M:")
        if let xIdx = text.range(of: "X:")?.lowerBound {
            return String(text[xIdx...])
        }
        if let tIdx = text.range(of: "T:")?.lowerBound {
            return "X: 1\n" + String(text[tIdx...])
        }
        return text
    }

    /// Extracts structure/section tags like [intro], [verse], [chorus] from lyrics
    public func extractStructureTags(lyrics: String) -> [String] {
        let lines = lyrics.components(separatedBy: .newlines)
        var tags: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                let tag = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                if !tag.isEmpty {
                    tags.append(tag)
                }
            }
        }
        return tags
    }

    /// Parses an ABC string into structured ABCScore
    public func parseScore(abc: String) -> ABCScore {
        return parser.parse(abcString: abc)
    }

    /// Exports score to standard MIDI file data
    public func exportMIDI(from abc: String) -> Data {
        let score = parser.parse(abcString: abc)
        return midiExporter.export(score: score)
    }

    /// Exports score to standard MusicXML string
    public func exportMusicXML(from abc: String) -> String {
        let score = parser.parse(abcString: abc)
        return xmlExporter.export(score: score)
    }

    /// Generates a starter template ABC score tailored to genre tags and entire lyrics structure
    public func generateStarterTemplate(title: String, genreTags: String, lyrics: String) -> String {
        let isMinor = genreTags.lowercased().contains("minor") || genreTags.lowercased().contains("sad") || genreTags.lowercased().contains("dark")
        let key = isMinor ? "Am" : "C"
        let chords = isMinor ? ["Am", "F", "C", "G"] : ["C", "G", "Am", "F"]

        var lines: [String] = [
            "X: 1",
            "T: \(title.isEmpty ? "YuE2 Melody Plan" : title)",
            "C: YuE2 AI Composer",
            "M: 4/4",
            "L: 1/8",
            "Q: 1/4=120",
            "K: \(key)"
        ]

        let lyricLines = lyrics
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var barCount = 0
        var currentBars: [String] = []
        var currentLyrics: [String] = []

        for line in lyricLines {
            if line.hasPrefix("[") && line.hasSuffix("]") {
                if !currentBars.isEmpty {
                    lines.append(currentBars.joined(separator: " ") + " |")
                    lines.append("w: " + currentLyrics.joined(separator: " | ") + " |")
                    currentBars.removeAll()
                    currentLyrics.removeAll()
                }
                let secName = line.replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")
                lines.append("% " + secName)
                continue
            }

            let c1 = chords[(barCount * 2) % chords.count]
            let c2 = chords[(barCount * 2 + 1) % chords.count]
            let m1 = "\"\(c1)\" c2 e2 g2 c2"
            let m2 = "\"\(c2)\" d2 f2 a2 d2"
            let syllables = line.components(separatedBy: .whitespaces).joined(separator: "-")

            currentBars.append("| \(m1) | \(m2)")
            currentLyrics.append("\(syllables)")
            barCount += 1

            // Wrap every 2 lines (4 measures) into standard ABC line
            if currentBars.count >= 2 {
                lines.append(currentBars.joined(separator: " ") + " |")
                lines.append("w: " + currentLyrics.joined(separator: " | ") + " |")
                currentBars.removeAll()
                currentLyrics.removeAll()
            }
        }

        if !currentBars.isEmpty {
            lines.append(currentBars.joined(separator: " ") + " |")
            lines.append("w: " + currentLyrics.joined(separator: " | ") + " |")
        }

        if barCount == 0 {
            lines.append("| \"\(chords[0])\" c2 e2 g2 c2 | \"\(chords[1])\" d2 f2 a2 d2 |")
            lines.append("| \"\(chords[2])\" e2 g2 b2 e2 | \"\(chords[3])\" f2 a2 c'2 f2 |")
        }

        return lines.joined(separator: "\n")
    }

    /// Transposes all notes, chords, and key signature in an ABC score by N semitones
    public func transpose(abc: String, semitones: Int) -> String {
        guard semitones != 0 else { return abc }

        let noteNamesSharp = ["C", "^C", "D", "^D", "E", "F", "^F", "G", "^G", "A", "^A", "B"]
        let chordRoots = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

        let lines = abc.components(separatedBy: .newlines)
        var resultLines: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // 1. Transpose Key Signature: K: <Key>
            if trimmed.hasPrefix("K:") {
                let keyContent = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
                let isMinor = keyContent.hasSuffix("m") || keyContent.hasSuffix("min")
                let rawRoot = isMinor ? String(keyContent.prefix(while: { $0 != "m" })) : keyContent

                var rootIdx = 0
                for (idx, r) in chordRoots.enumerated() {
                    if rawRoot.uppercased().hasPrefix(r) {
                        rootIdx = idx
                        break
                    }
                }

                let newRootIdx = (rootIdx + semitones % 12 + 12) % 12
                let newKey = chordRoots[newRootIdx] + (isMinor ? "m" : "")
                resultLines.append("K: \(newKey)")
                continue
            }

            // Keep headers and lyric lines as-is
            if trimmed.hasPrefix("X:") || trimmed.hasPrefix("T:") || trimmed.hasPrefix("C:") ||
               trimmed.hasPrefix("M:") || trimmed.hasPrefix("L:") || trimmed.hasPrefix("Q:") ||
               trimmed.hasPrefix("w:") {
                resultLines.append(line)
                continue
            }

            // 2. Transpose notes and chords inside music lines
            var modifiedLine = ""
            var i = line.startIndex

            while i < line.endIndex {
                // Chord transposing: "C", "Am", "G7"
                if line[i] == "\"" {
                    guard let endQuote = line[line.index(after: i)...].firstIndex(of: "\"") else {
                        modifiedLine.append(line[i])
                        i = line.index(after: i)
                        continue
                    }

                    let chordStr = String(line[line.index(after: i)..<endQuote])
                    var chordRoot = ""
                    var chordSuffix = ""

                    for r in chordRoots.sorted(by: { $0.count > $1.count }) {
                        if chordStr.hasPrefix(r) {
                            chordRoot = r
                            chordSuffix = String(chordStr.dropFirst(r.count))
                            break
                        }
                    }

                    if !chordRoot.isEmpty, let rIdx = chordRoots.firstIndex(of: chordRoot) {
                        let newRIdx = (rIdx + semitones % 12 + 12) % 12
                        modifiedLine.append("\"\(chordRoots[newRIdx])\(chordSuffix)\"")
                    } else {
                        modifiedLine.append("\"\(chordStr)\"")
                    }

                    i = line.index(after: endQuote)
                    continue
                }

                // Melodic Note Transposition: C..B, c..b with optional accidentals and octaves
                var accidental = 0
                if line[i] == "^" {
                    accidental = 1
                    i = line.index(after: i)
                    if i < line.endIndex && line[i] == "^" { accidental = 2; i = line.index(after: i) }
                } else if line[i] == "_" {
                    accidental = -1
                    i = line.index(after: i)
                    if i < line.endIndex && line[i] == "_" { accidental = -2; i = line.index(after: i) }
                } else if line[i] == "=" {
                    i = line.index(after: i)
                }

                if i < line.endIndex {
                    let ch = line[i]
                    let upper = String(ch).uppercased()
                    let baseNotes: [String: Int] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]

                    if let baseSemi = baseNotes[upper] {
                        var oct = ch.isLowercase ? 5 : 4
                        i = line.index(after: i)

                        // Octave modifiers
                        while i < line.endIndex && (line[i] == "'" || line[i] == ",") {
                            if line[i] == "'" { oct += 1 }
                            if line[i] == "," { oct -= 1 }
                            i = line.index(after: i)
                        }

                        // Duration digits
                        var durStr = ""
                        while i < line.endIndex && (line[i].isNumber || line[i] == "/") {
                            durStr.append(line[i])
                            i = line.index(after: i)
                        }

                        let midiPitch = 12 * (oct + 1) + baseSemi + accidental
                        let newMidiPitch = midiPitch + semitones
                        let newOct = (newMidiPitch / 12) - 1
                        let newSemi = (newMidiPitch % 12 + 12) % 12

                        var newNoteStr = noteNamesSharp[newSemi]
                        if newOct >= 5 {
                            newNoteStr = newNoteStr.lowercased()
                            if newOct > 5 {
                                newNoteStr += String(repeating: "'", count: newOct - 5)
                            }
                        } else if newOct < 4 {
                            newNoteStr += String(repeating: ",", count: 4 - newOct)
                        }
                        modifiedLine.append("\(newNoteStr)\(durStr)")
                        continue
                    }
                }

                modifiedLine.append(line[i])
                i = line.index(after: i)
            }

            resultLines.append(modifiedLine)
        }

        return resultLines.joined(separator: "\n")
    }

    /// Modulates musical mode between Major and Minor (e.g. converting a happy track into a melancholic ballad)
    public func modulateMode(abc: String, transform: ModeTransform) -> String {
        guard transform != .none else { return abc }

        let lines = abc.components(separatedBy: .newlines)
        var resultLines: [String] = []

        let isToMinor = (transform == .majorToMinor)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Convert Key Signature
            if trimmed.hasPrefix("K:") {
                let keyContent = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
                if isToMinor {
                    let root = keyContent.replacingOccurrences(of: "m", with: "")
                    resultLines.append("K: \(root)m")
                } else {
                    let root = keyContent.replacingOccurrences(of: "m", with: "")
                    resultLines.append("K: \(root)")
                }
                continue
            }

            // Convert chord symbols and flatten/sharpen 3rd, 6th, and 7th degrees
            var modified = line
            if isToMinor {
                // Flatten 3rd, 6th, and 7th in C Major: E -> _E, A -> _A, B -> _B
                modified = modified
                    .replacingOccurrences(of: "\"C\"", with: "\"Cm\"")
                    .replacingOccurrences(of: "\"F\"", with: "\"Fm\"")
                    .replacingOccurrences(of: "\"G\"", with: "\"Gm\"")
                    .replacingOccurrences(of: " e", with: " _e")
                    .replacingOccurrences(of: " E", with: " _E")
                    .replacingOccurrences(of: " a", with: " _a")
                    .replacingOccurrences(of: " A", with: " _A")
                    .replacingOccurrences(of: " b", with: " _b")
                    .replacingOccurrences(of: " B", with: " _B")
            } else {
                // Minor to Major: Remove flats, change minor chords to major
                modified = modified
                    .replacingOccurrences(of: "\"Am\"", with: "\"A\"")
                    .replacingOccurrences(of: "\"Cm\"", with: "\"C\"")
                    .replacingOccurrences(of: "\"Dm\"", with: "\"D\"")
                    .replacingOccurrences(of: "\"Em\"", with: "\"E\"")
                    .replacingOccurrences(of: "_e", with: "e")
                    .replacingOccurrences(of: "_E", with: "E")
                    .replacingOccurrences(of: "_a", with: "a")
                    .replacingOccurrences(of: "_A", with: "A")
                    .replacingOccurrences(of: "_b", with: "b")
                    .replacingOccurrences(of: "_B", with: "B")
            }
            resultLines.append(modified)
        }

        return resultLines.joined(separator: "\n")
    }

    /// Rewrites lyrics over existing musical measures, automatically splitting words into syllables
    public func rewriteLyrics(abc: String, newLyrics: String) -> String {
        let lines = abc.components(separatedBy: .newlines)
        var resultLines: [String] = []

        // Strip existing lyric lines (w:)
        for l in lines {
            if !l.trimmingCharacters(in: .whitespaces).hasPrefix("w:") {
                resultLines.append(l)
            }
        }

        let lyricWords = newLyrics
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty && !$0.hasPrefix("[") }

        guard !lyricWords.isEmpty else {
            return resultLines.joined(separator: "\n")
        }

        // Insert w: lines under musical measure lines
        var finalLines: [String] = []
        var wordIdx = 0

        for l in resultLines {
            finalLines.append(l)
            let trimmed = l.trimmingCharacters(in: .whitespaces)

            // If this line contains musical measures and is not a header
            if (trimmed.contains("|") || trimmed.contains("\"")) &&
               !trimmed.hasPrefix("X:") && !trimmed.hasPrefix("T:") &&
               !trimmed.hasPrefix("C:") && !trimmed.hasPrefix("M:") &&
               !trimmed.hasPrefix("L:") && !trimmed.hasPrefix("Q:") &&
               !trimmed.hasPrefix("K:") {

                // Count notes in this line
                let notesInLine = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty && !$0.contains("|") && !$0.contains("\"") }
                let noteCount = max(2, notesInLine.count)

                var syllablesForLine: [String] = []
                for _ in 0..<noteCount {
                    if wordIdx < lyricWords.count {
                        syllablesForLine.append(lyricWords[wordIdx])
                        wordIdx += 1
                    } else {
                        syllablesForLine.append("la")
                    }
                }
                finalLines.append("w: " + syllablesForLine.joined(separator: "-") + " |")
            }
        }

        return finalLines.joined(separator: "\n")
    }
}
