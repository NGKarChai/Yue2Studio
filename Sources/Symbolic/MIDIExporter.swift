import Foundation

/// Pure native Swift Standard MIDI File (SMF Format 1) generator
public final class MIDIExporter: @unchecked Sendable {
    public let ticksPerQuarterNote: Int = 480

    public init() {}

    /// Exports an ABCScore to standard MIDI file binary data
    public func export(score: ABCScore) -> Data {
        var midiData = Data()

        // 1. Header Chunk: "MThd" + length (6) + format (1) + ntrks (3) + division (480)
        midiData.append(contentsOf: [0x4D, 0x54, 0x68, 0x64]) // 'MThd'
        midiData.append(contentsOf: uint32Bytes(6))
        midiData.append(contentsOf: uint16Bytes(1)) // Format 1 (multiple simultaneous tracks)
        midiData.append(contentsOf: uint16Bytes(3)) // 3 tracks: Conductor/Tempo, Melody, Harmony
        midiData.append(contentsOf: uint16Bytes(UInt16(ticksPerQuarterNote)))

        // 2. Track 1: Conductor Track (Tempo & Time Signature)
        let track1Data = createConductorTrack(score: score)
        midiData.append(contentsOf: [0x4D, 0x54, 0x72, 0x6B]) // 'MTrk'
        midiData.append(contentsOf: uint32Bytes(UInt32(track1Data.count)))
        midiData.append(track1Data)

        // 3. Track 2: Vocal / Lead Melody Track (Channel 0)
        let track2Data = createMelodyTrack(score: score)
        midiData.append(contentsOf: [0x4D, 0x54, 0x72, 0x6B]) // 'MTrk'
        midiData.append(contentsOf: uint32Bytes(UInt32(track2Data.count)))
        midiData.append(track2Data)

        // 4. Track 3: Chord Accompaniment Track (Channel 1)
        let track3Data = createHarmonyTrack(score: score)
        midiData.append(contentsOf: [0x4D, 0x54, 0x72, 0x6B]) // 'MTrk'
        midiData.append(contentsOf: uint32Bytes(UInt32(track3Data.count)))
        midiData.append(track3Data)

        return midiData
    }

    // MARK: - Track Builders

    private func createConductorTrack(score: ABCScore) -> Data {
        var track = Data()

        // Delta-time 0: Track Name
        track.append(contentsOf: encodeVLQ(0))
        track.append(contentsOf: [0xFF, 0x03]) // Meta: Track Name
        let nameBytes = Array((score.title.isEmpty ? "YuE2 Score" : score.title).utf8)
        track.append(contentsOf: encodeVLQ(nameBytes.count))
        track.append(contentsOf: nameBytes)

        // Delta-time 0: Set Tempo (microsec per quarter note = 60,000,000 / BPM)
        let bpm = max(20.0, min(300.0, score.tempoBpm))
        let microsecPerBeat = UInt32(60_000_000.0 / bpm)
        track.append(contentsOf: encodeVLQ(0))
        track.append(contentsOf: [0xFF, 0x51, 0x03])
        track.append(UInt8((microsecPerBeat >> 16) & 0xFF))
        track.append(UInt8((microsecPerBeat >> 8) & 0xFF))
        track.append(UInt8(microsecPerBeat & 0xFF))

        // Delta-time 0: Time Signature
        track.append(contentsOf: encodeVLQ(0))
        track.append(contentsOf: [0xFF, 0x58, 0x04])
        track.append(UInt8(max(1, score.meter.beats)))
        let denomPower = UInt8(round(log2(Double(max(1, score.meter.beatType)))))
        track.append(denomPower)
        track.append(24) // 24 MIDI clocks per metronome click
        track.append(8)  // 8 32nd-notes per MIDI quarter note

        // End of Track
        track.append(contentsOf: encodeVLQ(0))
        track.append(contentsOf: [0xFF, 0x2F, 0x00])

        return track
    }

    private func createMelodyTrack(score: ABCScore) -> Data {
        var track = Data()

        // Delta-time 0: Track Name "Lead Vocal / Melody"
        track.append(contentsOf: encodeVLQ(0))
        track.append(contentsOf: [0xFF, 0x03])
        let trackName = Array("Lead Vocal / Melody".utf8)
        track.append(contentsOf: encodeVLQ(trackName.count))
        track.append(contentsOf: trackName)

        // Delta-time 0: GM Instrument Program Change on Channel 0 (0xC0: 0x00 Acoustic Grand Piano)
        track.append(contentsOf: encodeVLQ(0))
        track.append(contentsOf: [0xC0, 0x00])

        // Delta-time 0: CC 7 Channel Volume (127 Max)
        track.append(contentsOf: encodeVLQ(0))
        track.append(contentsOf: [0xB0, 0x07, 0x7F])

        // Delta-time 0: CC 10 Pan (64 Center)
        track.append(contentsOf: encodeVLQ(0))
        track.append(contentsOf: [0xB0, 0x0A, 0x40])

        // Delta-time 0: CC 91 Reverb Send (40)
        track.append(contentsOf: encodeVLQ(0))
        track.append(contentsOf: [0xB0, 0x5B, 0x28])

        var accumulatedDeltaTicks: Int = 0

        for measure in score.measures {
            for note in measure.notes {
                let noteDurationTicks = max(1, Int(note.durationBeats * Double(ticksPerQuarterNote)))

                if let pitch = note.pitch {
                    let midiNote = UInt8(max(0, min(127, pitch.midiNoteNumber)))
                    let velocity: UInt8 = 100

                    // Note On (Channel 0)
                    track.append(contentsOf: encodeVLQ(accumulatedDeltaTicks))
                    track.append(contentsOf: [0x90, midiNote, velocity])

                    // Note Off (Channel 0)
                    track.append(contentsOf: encodeVLQ(noteDurationTicks))
                    track.append(contentsOf: [0x80, midiNote, 0x00])

                    accumulatedDeltaTicks = 0
                } else {
                    // Rest: accumulate ticks for next note event
                    accumulatedDeltaTicks += noteDurationTicks
                }
            }
        }

        // End of Track
        track.append(contentsOf: encodeVLQ(accumulatedDeltaTicks))
        track.append(contentsOf: [0xFF, 0x2F, 0x00])

        return track
    }

    private func createHarmonyTrack(score: ABCScore) -> Data {
        var track = Data()

        // Delta-time 0: Track Name "Chords / Accompaniment"
        track.append(contentsOf: encodeVLQ(0))
        track.append(contentsOf: [0xFF, 0x03])
        let trackName = Array("Chords / Accompaniment".utf8)
        track.append(contentsOf: encodeVLQ(trackName.count))
        track.append(contentsOf: trackName)

        // Delta-time 0: GM Instrument Program Change on Channel 1 (0xC1: 0x00 Acoustic Grand Piano)
        track.append(contentsOf: encodeVLQ(0))
        track.append(contentsOf: [0xC1, 0x00])

        // Delta-time 0: CC 7 Channel Volume (96)
        track.append(contentsOf: encodeVLQ(0))
        track.append(contentsOf: [0xB1, 0x07, 0x60])

        // Delta-time 0: CC 10 Pan (64 Center)
        track.append(contentsOf: encodeVLQ(0))
        track.append(contentsOf: [0xB1, 0x0A, 0x40])

        var accumulatedDeltaTicks: Int = 0

        for measure in score.measures {
            // Check if measure has any chords
            let chordNotes = measure.notes.enumerated().filter { $0.element.chord != nil }

            if chordNotes.isEmpty {
                // If no chords in this measure, advance accumulated delta by measure duration
                let measureTicks = measure.notes.reduce(0) { $0 + max(1, Int($1.durationBeats * Double(ticksPerQuarterNote))) }
                accumulatedDeltaTicks += (measureTicks > 0 ? measureTicks : ticksPerQuarterNote * 4)
                continue
            }

            // Calculate duration for each chord in the measure so chords sustain properly
            for (idx, (noteIdx, note)) in chordNotes.enumerated() {
                guard let chordName = note.chord, let midiPitches = chordToMidi(chordName) else {
                    continue
                }

                // Determine duration of this chord: until next chord note or end of measure
                let nextNoteIdx = (idx + 1 < chordNotes.count) ? chordNotes[idx + 1].offset : measure.notes.count
                var chordDurationTicks = 0
                for nI in noteIdx..<nextNoteIdx {
                    chordDurationTicks += max(1, Int(measure.notes[nI].durationBeats * Double(ticksPerQuarterNote)))
                }
                chordDurationTicks = max(ticksPerQuarterNote / 2, chordDurationTicks)

                let velocity: UInt8 = 75

                // Play chord notes simultaneously on Channel 1 (0x91)
                for (i, p) in midiPitches.enumerated() {
                    let delta = (i == 0) ? accumulatedDeltaTicks : 0
                    track.append(contentsOf: encodeVLQ(delta))
                    track.append(contentsOf: [0x91, UInt8(max(0, min(127, p))), velocity])
                }

                // Release chord notes simultaneously
                for (i, p) in midiPitches.enumerated() {
                    let delta = (i == 0) ? chordDurationTicks : 0
                    track.append(contentsOf: encodeVLQ(delta))
                    track.append(contentsOf: [0x81, UInt8(max(0, min(127, p))), 0x00])
                }

                accumulatedDeltaTicks = 0
            }
        }

        // End of Track
        track.append(contentsOf: encodeVLQ(accumulatedDeltaTicks))
        track.append(contentsOf: [0xFF, 0x2F, 0x00])

        return track
    }

    // MARK: - Helpers

    /// Converts chord name (e.g. "C", "Am", "Bm", "G7", "F#m", "Bb", "Ebmaj7") to 3-4 MIDI pitch numbers (octave 3)
    public func chordToMidi(_ chord: String) -> [Int]? {
        let roots: [String: Int] = [
            "C": 48, "C#": 49, "DB": 49,
            "D": 50, "D#": 51, "EB": 51,
            "E": 52,
            "F": 53, "F#": 54, "GB": 54,
            "G": 55, "G#": 56, "AB": 56,
            "A": 57, "A#": 58, "BB": 58,
            "B": 59
        ]

        let trimmed = chord.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let firstChar = String(trimmed.prefix(1)).uppercased()
        guard ["A", "B", "C", "D", "E", "F", "G"].contains(firstChar) else { return nil }

        var root = firstChar
        var remainder = ""

        let afterFirst = trimmed.dropFirst()
        if afterFirst.hasPrefix("#") {
            root = firstChar + "#"
            remainder = String(afterFirst.dropFirst())
        } else if afterFirst.hasPrefix("b") || (firstChar != "B" && afterFirst.hasPrefix("B")) {
            root = firstChar + "B"
            remainder = String(afterFirst.dropFirst())
        } else {
            root = firstChar
            remainder = String(afterFirst)
        }

        guard let baseMidi = roots[root] else { return nil }

        let remUpper = remainder.uppercased()
        let isMinor = remUpper.hasPrefix("M") && !remUpper.hasPrefix("MAJ")
        let isDim = remUpper.contains("DIM")
        let isAug = remUpper.contains("AUG") || remUpper.contains("+")
        let isSus4 = remUpper.contains("SUS4")
        let isSus2 = remUpper.contains("SUS2")

        let thirdOffset: Int
        let fifthOffset: Int

        if isDim {
            thirdOffset = 3
            fifthOffset = 6
        } else if isAug {
            thirdOffset = 4
            fifthOffset = 8
        } else if isSus4 {
            thirdOffset = 5
            fifthOffset = 7
        } else if isSus2 {
            thirdOffset = 2
            fifthOffset = 7
        } else if isMinor {
            thirdOffset = 3
            fifthOffset = 7
        } else {
            thirdOffset = 4
            fifthOffset = 7
        }

        var pitches = [baseMidi, baseMidi + thirdOffset, baseMidi + fifthOffset]

        if remUpper.contains("7") {
            let seventhOffset: Int
            if isDim && remUpper.contains("DIM7") {
                seventhOffset = 9
            } else if remUpper.contains("MAJ7") {
                seventhOffset = 11
            } else {
                seventhOffset = 10 // Dominant or Minor 7th
            }
            pitches.append(baseMidi + seventhOffset)
        } else if remUpper.contains("6") {
            pitches.append(baseMidi + 9)
        }

        return pitches
    }

    /// Encodes an integer as a MIDI Variable-Length Quantity (VLQ)
    private func encodeVLQ(_ value: Int) -> [UInt8] {
        var val = value
        var buffer: [UInt8] = []
        buffer.append(UInt8(val & 0x7F))
        val >>= 7

        while val > 0 {
            buffer.insert(UInt8((val & 0x7F) | 0x80), at: 0)
            val >>= 7
        }

        return buffer
    }

    private func uint32Bytes(_ val: UInt32) -> [UInt8] {
        return [
            UInt8((val >> 24) & 0xFF),
            UInt8((val >> 16) & 0xFF),
            UInt8((val >> 8) & 0xFF),
            UInt8(val & 0xFF)
        ]
    }

    private func uint16Bytes(_ val: UInt16) -> [UInt8] {
        return [
            UInt8((val >> 8) & 0xFF),
            UInt8(val & 0xFF)
        ]
    }
}
