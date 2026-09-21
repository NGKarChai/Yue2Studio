import Foundation

/// Pure native Swift MusicXML 4.0 serializer
public final class MusicXMLExporter: @unchecked Sendable {
    public init() {}

    /// Converts an ABCScore into standard MusicXML 4.0 XML string
    public func export(score: ABCScore) -> String {
        let divisions = 4 // 4 divisions per quarter note

        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 4.0 Partwise//EN" "http://www.musicxml.org/dtds/partwise.dtd">
        <score-partwise version="4.0">
          <work>
            <work-title>\(escapeXml(score.title))</work-title>
          </work>
          <identification>
            <creator type="composer">\(escapeXml(score.composer))</creator>
            <encoding>
              <software>YuE Studio 2.0</software>
              <encoding-date>\(currentIsoDate())</encoding-date>
            </encoding>
          </identification>
          <part-list>
            <score-part id="P1">
              <part-name>Lead Melody</part-name>
            </score-part>
          </part-list>
          <part id="P1">

        """

        for (mIdx, measure) in score.measures.enumerated() {
            xml += "    <measure number=\"\(mIdx + 1)\">\n"

            if mIdx == 0 {
                // Measure 1 attributes: divisions, key signature, meter, clef, tempo
                xml += """
                      <attributes>
                        <divisions>\(divisions)</divisions>
                        <key>
                          <fifths>\(keyFifths(score.keySignature))</fifths>
                          <mode>\(score.keySignature.lowercased().contains("m") ? "minor" : "major")</mode>
                        </key>
                        <time>
                          <beats>\(score.meter.beats)</beats>
                          <beat-type>\(score.meter.beatType)</beat-type>
                        </time>
                        <clef>
                          <sign>G</sign>
                          <line>2</line>
                        </clef>
                      </attributes>
                      <direction placement="above">
                        <direction-type>
                          <metronome>
                            <beat-unit>quarter</beat-unit>
                            <per-minute>\(Int(score.tempoBpm))</per-minute>
                          </metronome>
                        </direction-type>
                        <sound tempo=\"\(Int(score.tempoBpm))\"/>
                      </direction>

                """
            }

            for note in measure.notes {
                // If there's a chord symbol on this note, write harmony
                if let chord = note.chord {
                    xml += formatHarmony(chord)
                }

                let durationDivisions = max(1, Int(note.durationBeats * Double(divisions)))
                let noteType = noteTypeString(beats: note.durationBeats)

                if let pitch = note.pitch {
                    xml += "      <note>\n"
                    xml += "        <pitch>\n"
                    xml += "          <step>\(pitch.step)</step>\n"
                    if pitch.alter != 0 {
                        xml += "          <alter>\(pitch.alter)</alter>\n"
                    }
                    xml += "          <octave>\(pitch.octave)</octave>\n"
                    xml += "        </pitch>\n"
                    xml += "        <duration>\(durationDivisions)</duration>\n"
                    xml += "        <type>\(noteType)</type>\n"

                    if let lyric = note.lyricSyllable, !lyric.isEmpty {
                        xml += "        <lyric>\n"
                        xml += "          <text>\(escapeXml(lyric))</text>\n"
                        xml += "        </lyric>\n"
                    }

                    xml += "      </note>\n"
                } else {
                    // Rest
                    xml += "      <note>\n"
                    xml += "        <rest/>\n"
                    xml += "        <duration>\(durationDivisions)</duration>\n"
                    xml += "        <type>\(noteType)</type>\n"
                    xml += "      </note>\n"
                }
            }

            xml += "    </measure>\n"
        }

        xml += """
          </part>
        </score-partwise>
        """

        return xml
    }

    // MARK: - Helpers

    private func formatHarmony(_ chord: String) -> String {
        let upper = chord.uppercased()
        var step = "C"
        var alter = 0
        if let first = upper.first { step = String(first) }
        if upper.contains("#") { alter = 1 }
        if upper.contains("B") && upper.count > 1 && !upper.hasPrefix("B") { alter = -1 }

        let isMinor = upper.contains("M") && !upper.contains("MAJ")
        let kind = isMinor ? "minor" : (upper.contains("7") ? "dominant" : "major")

        var hXml = "      <harmony>\n"
        hXml += "        <root>\n"
        hXml += "          <root-step>\(step)</root-step>\n"
        if alter != 0 {
            hXml += "          <root-alter>\(alter)</root-alter>\n"
        }
        hXml += "        </root>\n"
        hXml += "        <kind>\(kind)</kind>\n"
        hXml += "      </harmony>\n"
        return hXml
    }

    private func keyFifths(_ key: String) -> Int {
        let fifthsMap: [String: Int] = [
            "C": 0, "G": 1, "D": 2, "A": 3, "E": 4, "B": 5, "F#": 6,
            "F": -1, "BB": -2, "EB": -3, "AB": -4, "DB": -5, "GB": -6,
            "AM": 0, "EM": 1, "BM": 2, "F#M": 3, "C#M": 4, "DM": -1, "GM": -2, "CM": -3
        ]
        return fifthsMap[key.uppercased()] ?? 0
    }

    private func noteTypeString(beats: Double) -> String {
        if beats >= 4.0 { return "whole" }
        if beats >= 2.0 { return "half" }
        if beats >= 1.0 { return "quarter" }
        if beats >= 0.5 { return "eighth" }
        return "16th"
    }

    private func escapeXml(_ str: String) -> String {
        return str
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private func currentIsoDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
