import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Visual and code editor for ABC music notation, notes inspection, and export
public struct ScoreEditorView: View {
    @Bindable var state: AppState
    @State private var viewMode: Int = 0 // 0: Visual Sheet Music, 1: ABC Code
    @State private var exportStatusMessage: String?
    @State private var showingStatusAlert = false

    private let parser = ABCParser()
    private let midiExporter = MIDIExporter()
    private let xmlExporter = MusicXMLExporter()

    public init(state: AppState) {
        self.state = state
    }

    public var body: some View {
        VStack(spacing: 12) {
            // Header Bar
            HStack {
                Label("Musical Notes & Sheet Score", systemImage: "music.note.list")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                Picker("View", selection: $viewMode) {
                    Text("Sheet Music").tag(0)
                    Text("ABC Code").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)

                Menu {
                    Button {
                        exportMIDI()
                    } label: {
                        Label("Export MIDI (.mid)", systemImage: "pianokeys")
                    }

                    Button {
                        exportMusicXML()
                    } label: {
                        Label("Export MusicXML (.musicxml)", systemImage: "doc.text")
                    }

                    Button {
                        exportABC()
                    } label: {
                        Label("Export ABC Score (.abc)", systemImage: "arrow.down.doc")
                    }

                    Button {
                        exportLAB()
                    } label: {
                        Label("Export Timing Labels (.lab)", systemImage: "clock")
                    }

                    Divider()

                    Button {
                        exportBundle()
                    } label: {
                        Label("Export Complete Bundle (ABC + MIDI + LAB)", systemImage: "archivebox")
                    }
                } label: {
                    Label("Export Notes", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 4)

            // Content Area
            if viewMode == 0 {
                // Visual Sheet Music Representation
                ScrollView(.horizontal, showsIndicators: true) {
                    let parsedScore = parser.parse(abcString: state.currentScore)
                    HStack(alignment: .top, spacing: 16) {
                        // Score Metadata Card
                        VStack(alignment: .leading, spacing: 6) {
                            Text(parsedScore.title)
                                .font(.title3.bold())
                            Text(parsedScore.composer)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Divider()
                            HStack(spacing: 12) {
                                Label("Key: \(parsedScore.keySignature)", systemImage: "music.quarternote.3")
                                Label("Meter: \(parsedScore.meter.beats)/\(parsedScore.meter.beatType)", systemImage: "metronome")
                                Label("\(Int(parsedScore.tempoBpm)) BPM", systemImage: "speedometer")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding()
                        .frame(width: 240)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                        // Measures Rendered Horizontally
                        ForEach(parsedScore.measures) { measure in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Bar \(measure.measureNumber)")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Divider()
                                }

                                HStack(spacing: 12) {
                                    ForEach(measure.notes) { note in
                                        VStack(spacing: 4) {
                                            // Chord Label
                                            if let chord = note.chord {
                                                Text(chord)
                                                    .font(.caption.bold())
                                                    .foregroundStyle(.blue)
                                            } else {
                                                Text(" ")
                                                    .font(.caption)
                                            }

                                            // Note Graphic / Pitch representation
                                            ZStack {
                                                RoundedRectangle(cornerRadius: 6)
                                                    .fill(note.isRest ? Color.secondary.opacity(0.15) : Color.blue.opacity(0.15))
                                                    .frame(width: 38, height: 48)

                                                if let pitch = note.pitch {
                                                    VStack(spacing: 1) {
                                                        Text("\(pitch.step)\(pitch.alter == 1 ? "♯" : (pitch.alter == -1 ? "♭" : ""))")
                                                            .font(.system(.body, design: .rounded).bold())
                                                            .foregroundStyle(.primary)
                                                        Text("oct \(pitch.octave)")
                                                            .font(.system(size: 9))
                                                            .foregroundStyle(.secondary)
                                                    }
                                                } else {
                                                    Image(systemName: "pause.fill")
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                            }

                                            // Duration & Lyric
                                            Text(String(format: "%.1f", note.durationBeats))
                                                .font(.system(size: 9))
                                                .foregroundStyle(.secondary)

                                            if let lyric = note.lyricSyllable {
                                                Text(lyric)
                                                    .font(.caption2)
                                                    .foregroundStyle(.primary)
                                                    .lineLimit(1)
                                            }
                                        }
                                    }
                                }
                                .padding(8)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                    .padding(4)
                }
                .frame(minWidth: 0, maxWidth: .infinity)
                .frame(minHeight: 140, maxHeight: 180)
            } else {
                // Monospace ABC Notation Editor
                TextEditor(text: $state.currentScore)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 140, maxHeight: 180)
                    .padding(6)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    )
            }
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .alert("Notes Export", isPresented: $showingStatusAlert) {
            Button("OK") {}
        } message: {
            Text(exportStatusMessage ?? "")
        }
    }

    // MARK: - Export Handlers

    private func getEffectiveScore() -> String {
        let trimmed = self.state.currentScore.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            let generated = self.state.symbolicPlanner.generateStarterTemplate(
                title: self.state.songTitle,
                genreTags: self.state.genreTags,
                lyrics: self.state.lyrics
            )
            self.state.currentScore = generated
            return generated
        }
        return self.state.currentScore
    }

    private func exportMIDI() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.midi]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.title = "Export MIDI File"
        panel.nameFieldStringValue = "\(state.songTitle.replacingOccurrences(of: " ", with: "_")).mid"

        panel.begin { response in
            guard response == .OK, let targetURL = panel.url else { return }
            let scoreStr = self.getEffectiveScore()
            let midiData = self.midiExporter.export(score: self.parser.parse(abcString: scoreStr))
            do {
                try midiData.write(to: targetURL)
                self.exportStatusMessage = "Successfully exported standard playable MIDI file to:\n\(targetURL.path)"
                self.showingStatusAlert = true
            } catch {
                self.exportStatusMessage = "Failed to export MIDI: \(error.localizedDescription)"
                self.showingStatusAlert = true
            }
        }
    }

    private func exportMusicXML() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.xml]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.title = "Export MusicXML Sheet Music"
        panel.nameFieldStringValue = "\(state.songTitle.replacingOccurrences(of: " ", with: "_")).musicxml"

        panel.begin { response in
            guard response == .OK, let targetURL = panel.url else { return }
            let scoreStr = self.getEffectiveScore()
            let xmlString = self.xmlExporter.export(score: self.parser.parse(abcString: scoreStr))
            do {
                try xmlString.write(to: targetURL, atomically: true, encoding: .utf8)
                self.exportStatusMessage = "Successfully exported MusicXML score to:\n\(targetURL.path)"
                self.showingStatusAlert = true
            } catch {
                self.exportStatusMessage = "Failed to export MusicXML: \(error.localizedDescription)"
                self.showingStatusAlert = true
            }
        }
    }

    private func exportABC() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.title = "Export ABC Score"
        panel.nameFieldStringValue = "\(state.songTitle.replacingOccurrences(of: " ", with: "_")).abc"

        panel.begin { response in
            guard response == .OK, let targetURL = panel.url else { return }
            let scoreStr = self.getEffectiveScore()
            do {
                try scoreStr.write(to: targetURL, atomically: true, encoding: .utf8)
                self.exportStatusMessage = "Successfully exported complete ABC score to:\n\(targetURL.path)"
                self.showingStatusAlert = true
            } catch {
                self.exportStatusMessage = "Failed to export ABC: \(error.localizedDescription)"
                self.showingStatusAlert = true
            }
        }
    }

    private func exportLAB() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.title = "Export Timing Labels (.lab)"
        panel.nameFieldStringValue = "\(state.songTitle.replacingOccurrences(of: " ", with: "_")).lab"

        panel.begin { response in
            guard response == .OK, let targetURL = panel.url else { return }
            let scoreStr = self.getEffectiveScore()
            let parsedScore = self.parser.parse(abcString: scoreStr)
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
            let labStr = lines.joined(separator: "\n")
            do {
                try labStr.write(to: targetURL, atomically: true, encoding: .utf8)
                self.exportStatusMessage = "Successfully exported timing labels (.lab) to:\n\(targetURL.path)"
                self.showingStatusAlert = true
            } catch {
                self.exportStatusMessage = "Failed to export LAB: \(error.localizedDescription)"
                self.showingStatusAlert = true
            }
        }
    }

    private func exportBundle() {
        let panel = NSOpenPanel()
        panel.title = "Choose Destination Directory for Transcription Bundle"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        panel.begin { response in
            guard response == .OK, let targetDir = panel.url else { return }
            do {
                let exported = try self.state.exportTranscriptionBundle(
                    directory: targetDir,
                    baseName: self.state.songTitle
                )
                let filesList = exported.map { $0.lastPathComponent }.joined(separator: ", ")
                self.exportStatusMessage = "Successfully exported transcription bundle (\(filesList)) to:\n\(targetDir.path)"
                self.showingStatusAlert = true
            } catch {
                self.exportStatusMessage = "Failed to export bundle: \(error.localizedDescription)"
                self.showingStatusAlert = true
            }
        }
    }
}
