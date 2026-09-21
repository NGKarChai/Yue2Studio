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
        let nameBytes = Array(score.title.utf8)
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
        track.append(UInt8(score.meter.beats))
        // Denominator as power of 2: e.g. 4 -> 2 (2^2 = 4)
        let denomPower = UInt8(round(log2(Double(score.meter.beatType))))
        track.append(denomPower)
        track.append(24) // 24 MIDI clocks per metronome click
        track.append(8)  // 8 32nd-notes per MIDI quarter note (24 clocks)

        // End of Track
        track.append(contentsOf: encodeVLQ(0))
        track.append(contentsOf: [0xFF, 0x2F, 0x00])

        return track
    }

    private func createMelodyTrack(score: ABCScore) -> Data {
        var track = Data()

        // Delta-time 0: Track Name "Lead Melody"
        track.append(contentsOf: encodeVLQ(0))
        track.append(contentsOf: [0xFF, 0x03])
        let trackName = Array("Lead Vocal / Melody".utf8)
        track.append(contentsOf: encodeVLQ(trackName.count))
        track.append(contentsOf: trackName)

        var accumulatedDeltaTicks: Int = 0

        for measure in score.measures {
            for note in measure.notes {
                let noteDurationTicks = max(1, Int(note.durationBeats * Double(ticksPerQuarterNote)))

                if let pitch = note.pitch {
                    let midiNote = UInt8(max(0, min(127, pitch.midiNoteNumber)))
                    let velocity: UInt8 = 96

                    // Note On (Channel 0)
                    track.append(contentsOf: encodeVLQ(accumulatedDeltaTicks))
                    track.append(contentsOf: [0x90, midiNote, velocity])

                    // Note Off (Channel 0)
                    track.append(contentsOf: encodeVLQ(noteDurationTicks))
                    track.append(contentsOf: [0x80, midiNote, 0x00])

                    accumulatedDeltaTicks = 0
                } else {
                    // Rest: add ticks to accumulated delta for next note
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

        var accumulatedDeltaTicks: Int = 0

        for measure in score.measures {
            for note in measure.notes {
                let noteDurationTicks = max(1, Int(note.durationBeats * Double(ticksPerQuarterNote)))

                if let chordName = note.chord, let midiPitches = chordToMidi(chordName) {
                    let velocity: UInt8 = 75

                    // Play chord notes simultaneously on Channel 1 (0x91)
                    for (i, p) in midiPitches.enumerated() {
                        let delta = (i == 0) ? accumulatedDeltaTicks : 0
                        track.append(contentsOf: encodeVLQ(delta))
                        track.append(contentsOf: [0x91, UInt8(p), velocity])
                    }

                    // Release chord notes simultaneously
                    for (i, p) in midiPitches.enumerated() {
                        let delta = (i == 0) ? noteDurationTicks : 0
                        track.append(contentsOf: encodeVLQ(delta))
                        track.append(contentsOf: [0x81, UInt8(p), 0x00])
                    }

                    accumulatedDeltaTicks = 0
                } else {
                    accumulatedDeltaTicks += noteDurationTicks
                }
            }
        }

        // End of Track
        track.append(contentsOf: encodeVLQ(accumulatedDeltaTicks))
        track.append(contentsOf: [0xFF, 0x2F, 0x00])

        return track
    }

    // MARK: - Helpers

    /// Converts chord name (e.g. "C", "Am", "G7", "F#m") to 3-4 MIDI pitch numbers (octave 3)
    private func chordToMidi(_ chord: String) -> [Int]? {
        let roots: [String: Int] = [
            "C": 48, "C#": 49, "DB": 49,
            "D": 50, "D#": 51, "EB": 51,
            "E": 52,
            "F": 53, "F#": 54, "GB": 54,
            "G": 55, "G#": 56, "AB": 56,
            "A": 57, "A#": 58, "BB": 58,
            "B": 59
        ]

        let upper = chord.uppercased()
        var root = ""
        if upper.count >= 2 && (upper.contains("#") || upper.contains("B")) {
            root = String(upper.prefix(2))
        } else if let first = upper.first {
            root = String(first)
        }

        guard let baseMidi = roots[root] else { return nil }

        let isMinor = upper.contains("M") && !upper.contains("MAJ")
        let thirdOffset = isMinor ? 3 : 4
        let fifthOffset = 7

        var pitches = [baseMidi, baseMidi + thirdOffset, baseMidi + fifthOffset]
        if upper.contains("7") {
            let seventhOffset = isMinor ? 10 : (upper.contains("MAJ7") ? 11 : 10)
            pitches.append(baseMidi + seventhOffset)
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
