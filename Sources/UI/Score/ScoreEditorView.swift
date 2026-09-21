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

    private func exportMIDI() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.midi]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.title = "Export MIDI File"
        panel.nameFieldStringValue = "melody_\(Int(Date().timeIntervalSince1970)).mid"

        panel.begin { response in
            guard response == .OK, let targetURL = panel.url else { return }
            let midiData = self.midiExporter.export(score: self.parser.parse(abcString: self.state.currentScore))
            do {
                try midiData.write(to: targetURL)
                self.exportStatusMessage = "Successfully exported MIDI file to:\n\(targetURL.path)"
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
        panel.nameFieldStringValue = "score_\(Int(Date().timeIntervalSince1970)).musicxml"

        panel.begin { response in
            guard response == .OK, let targetURL = panel.url else { return }
            let xmlString = self.xmlExporter.export(score: self.parser.parse(abcString: self.state.currentScore))
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
        panel.nameFieldStringValue = "score_\(Int(Date().timeIntervalSince1970)).abc"

        panel.begin { response in
            guard response == .OK, let targetURL = panel.url else { return }
            do {
                try self.state.currentScore.write(to: targetURL, atomically: true, encoding: .utf8)
                self.exportStatusMessage = "Successfully exported ABC score to:\n\(targetURL.path)"
                self.showingStatusAlert = true
            } catch {
                self.exportStatusMessage = "Failed to export ABC: \(error.localizedDescription)"
                self.showingStatusAlert = true
            }
        }
    }
}
