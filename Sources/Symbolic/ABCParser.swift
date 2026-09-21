import Foundation

/// Represents a musical pitch with octave and accidental
public struct ABCPitch: Sendable, Equatable {
    public var step: String // C, D, E, F, G, A, B
    public var octave: Int  // 4 = middle C (C4)
    public var alter: Int   // -1 = flat, 0 = natural, 1 = sharp

    public init(step: String, octave: Int = 4, alter: Int = 0) {
        self.step = step.uppercased()
        self.octave = octave
        self.alter = alter
    }

    /// MIDI note number (60 = C4)
    public var midiNoteNumber: Int {
        let semitones: [String: Int] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]
        let base = semitones[step] ?? 0
        return (octave + 1) * 12 + base + alter
    }
}

/// Represents a musical note or rest in an ABC score
public struct ABCNote: Sendable, Identifiable, Equatable {
    public var id: UUID = UUID()
    public var pitch: ABCPitch? // nil represents a rest ('z' or 'x')
    public var durationBeats: Double // 1.0 = quarter note
    public var chord: String? // e.g. "C", "Am", "G7"
    public var lyricSyllable: String?

    public init(
        pitch: ABCPitch? = nil,
        durationBeats: Double = 1.0,
        chord: String? = nil,
        lyricSyllable: String? = nil
    ) {
        self.pitch = pitch
        self.durationBeats = durationBeats
        self.chord = chord
        self.lyricSyllable = lyricSyllable
    }

    public var isRest: Bool {
        return pitch == nil
    }
}

/// Represents a measure / bar in an ABC score
public struct ABCMeasure: Sendable, Identifiable, Equatable {
    public var id: UUID = UUID()
    public var measureNumber: Int
    public var notes: [ABCNote]

    public init(measureNumber: Int, notes: [ABCNote] = []) {
        self.measureNumber = measureNumber
        self.notes = notes
    }
}

/// Meter/Time Signature representation
public struct ABCMeter: Sendable, Equatable {
    public var beats: Int = 4
    public var beatType: Int = 4

    public init(beats: Int = 4, beatType: Int = 4) {
        self.beats = beats
        self.beatType = beatType
    }
}

/// Structured representation of a parsed ABC music score
public struct ABCScore: Sendable, Equatable {
    public var title: String = "Untitled"
    public var composer: String = "YuE2 AI Composer"
    public var meter: ABCMeter = ABCMeter(beats: 4, beatType: 4)
    public var unitLength: Double = 0.25 // 1/4 or 1/8 note
    public var tempoBpm: Double = 120.0
    public var keySignature: String = "C"
    public var measures: [ABCMeasure] = []

    public init() {}

    public var allNotes: [ABCNote] {
        return measures.flatMap { $0.notes }
    }
}

/// Native Swift ABC music notation parser
public final class ABCParser: @unchecked Sendable {
    public init() {}

    /// Parses an ABC notation string into a structured ABCScore
    public func parse(abcString: String) -> ABCScore {
        var score = ABCScore()
        let lines = abcString.components(separatedBy: .newlines)
        var musicLines: [String] = []
        var lyricLines: [String] = []

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("%") { continue }

            if line.hasPrefix("T:") {
                score.title = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("C:") {
                score.composer = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("M:") {
                let mStr = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                let parts = mStr.components(separatedBy: "/")
                if parts.count == 2, let b = Int(parts[0]), let bt = Int(parts[1]) {
                    score.meter = ABCMeter(beats: b, beatType: bt)
                }
            } else if line.hasPrefix("L:") {
                let lStr = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                let parts = lStr.components(separatedBy: "/")
                if parts.count == 2, let num = Double(parts[0]), let denom = Double(parts[1]), denom > 0 {
                    score.unitLength = num / denom
                }
            } else if line.hasPrefix("Q:") {
                let qStr = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if let bpmMatch = qStr.components(separatedBy: "=").last, let bpm = Double(bpmMatch.trimmingCharacters(in: .whitespaces)) {
                    score.tempoBpm = bpm
                } else if let bpm = Double(qStr) {
                    score.tempoBpm = bpm
                }
            } else if line.hasPrefix("K:") {
                score.keySignature = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("w:") {
                lyricLines.append(String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces))
            } else if !line.contains(":") || line.contains("|") {
                musicLines.append(line)
            }
        }

        // Parse measures and notes
        var currentMeasureNum = 1
        var currentNotes: [ABCNote] = []
        var activeChord: String? = nil

        let fullMusic = musicLines.joined(separator: " ")
        var idx = fullMusic.startIndex

        while idx < fullMusic.endIndex {
            let char = fullMusic[idx]

            if char == "|" {
                if !currentNotes.isEmpty {
                    score.measures.append(ABCMeasure(measureNumber: currentMeasureNum, notes: currentNotes))
                    currentMeasureNum += 1
                    currentNotes = []
                }
                idx = fullMusic.index(after: idx)
                continue
            }

            if char == "\"" {
                // Chord symbol: "Am", "C", "G7"
                let startChord = fullMusic.index(after: idx)
                if let endChord = fullMusic[startChord...].firstIndex(of: "\"") {
                    activeChord = String(fullMusic[startChord..<endChord])
                    idx = fullMusic.index(after: endChord)
                    continue
                }
            }

            // Note or rest
            var alter = 0
            if char == "^" {
                alter = 1
                idx = fullMusic.index(after: idx)
                if idx < fullMusic.endIndex && fullMusic[idx] == "^" {
                    alter = 2
                    idx = fullMusic.index(after: idx)
                }
            } else if char == "_" {
                alter = -1
                idx = fullMusic.index(after: idx)
                if idx < fullMusic.endIndex && fullMusic[idx] == "_" {
                    alter = -2
                    idx = fullMusic.index(after: idx)
                }
            } else if char == "=" {
                alter = 0
                idx = fullMusic.index(after: idx)
            }

            guard idx < fullMusic.endIndex else { break }
            let noteChar = fullMusic[idx]

            if ("A"..."G").contains(noteChar) || ("a"..."g").contains(noteChar) || noteChar == "z" || noteChar == "x" {
                let isRest = (noteChar == "z" || noteChar == "x")
                let step = String(noteChar).uppercased()
                var octave = ("a"..."g").contains(noteChar) ? 5 : 4

                idx = fullMusic.index(after: idx)

                // Octave modifiers: ' (higher) or , (lower)
                while idx < fullMusic.endIndex && (fullMusic[idx] == "'" || fullMusic[idx] == ",") {
                    if fullMusic[idx] == "'" { octave += 1 }
                    if fullMusic[idx] == "," { octave -= 1 }
                    idx = fullMusic.index(after: idx)
                }

                // Duration modifier: e.g. 2, 3, /2, /4
                var durationMult: Double = 1.0
                var numStr = ""
                while idx < fullMusic.endIndex && fullMusic[idx].isNumber {
                    numStr.append(fullMusic[idx])
                    idx = fullMusic.index(after: idx)
                }
                if let mult = Double(numStr), mult > 0 {
                    durationMult = mult
                }

                if idx < fullMusic.endIndex && fullMusic[idx] == "/" {
                    idx = fullMusic.index(after: idx)
                    var denomStr = ""
                    while idx < fullMusic.endIndex && fullMusic[idx].isNumber {
                        denomStr.append(fullMusic[idx])
                        idx = fullMusic.index(after: idx)
                    }
                    let denom = Double(denomStr) ?? 2.0
                    if denom > 0 {
                        durationMult /= denom
                    }
                }

                let noteBeats = durationMult * (score.unitLength * 4.0) // Normalize to quarter note beats
                let pitch = isRest ? nil : ABCPitch(step: step, octave: octave, alter: alter)
                let note = ABCNote(pitch: pitch, durationBeats: noteBeats, chord: activeChord)
                currentNotes.append(note)
                activeChord = nil // Reset active chord after applying to note
            } else {
                idx = fullMusic.index(after: idx)
            }
        }

        if !currentNotes.isEmpty {
            score.measures.append(ABCMeasure(measureNumber: currentMeasureNum, notes: currentNotes))
        }

        // Align lyrics
        if !lyricLines.isEmpty {
            let allSyllables = lyricLines
                .joined(separator: " ")
                .components(separatedBy: .whitespaces)
                .flatMap { $0.components(separatedBy: "-") }
                .filter { !$0.isEmpty && $0 != "|" }

            var sylIdx = 0
            for mIdx in 0..<score.measures.count {
                for nIdx in 0..<score.measures[mIdx].notes.count {
                    if !score.measures[mIdx].notes[nIdx].isRest && sylIdx < allSyllables.count {
                        score.measures[mIdx].notes[nIdx].lyricSyllable = allSyllables[sylIdx]
                        sylIdx += 1
                    }
                }
            }
        }

        return score
    }
}
