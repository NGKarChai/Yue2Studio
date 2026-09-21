import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct CoverStudioView: View {
    @Bindable var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header & Reference Mode
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "music.mic.circle.fill")
                        .foregroundColor(.blue)
                        .font(.title3)
                    Text("AUDIO REFERENCE & COVER CREATION")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if appState.referenceAudioURL != nil {
                    Button(action: {
                        appState.clearReferenceAudio()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                            Text("Remove Audio")
                        }
                        .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.red)
                }
            }

            // Audio File Selector / Status
            if let refURL = appState.referenceAudioURL {
                HStack(spacing: 12) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(refURL.lastPathComponent)
                            .font(.callout)
                            .fontWeight(.medium)
                            .lineLimit(1)

                        HStack(spacing: 8) {
                            if let dur = appState.referenceAudioDuration {
                                Text(String(format: "%.1f seconds", dur))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            if let analysis = appState.referenceAnalysis {
                                Text("• Key: \(analysis.detectedKey)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text("• \(analysis.notes.count) notes")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text("• \(analysis.windowCount) window\(analysis.windowCount > 1 ? "s" : "")")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    Spacer()

                    Button("Change File") {
                        chooseReferenceAudio()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                )
            } else {
                Button(action: {
                    chooseReferenceAudio()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.body)
                        Text("Upload Reference Audio Track (.wav, .mp3, .m4a, .flac)")
                            .font(.callout)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
            }

            if appState.isAnalyzingReference {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Tracking pitch contours and detecting notes with vDSP...")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 2)
            }

            // Reference Conditioning Mode: Melody Only vs Full Reference
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Reference Conditioning Mode")
                        .font(.caption)
                    Spacer()
                }

                Picker("Reference Mode", selection: Binding(
                    get: { appState.referenceMode },
                    set: { appState.setReferenceMode($0) }
                )) {
                    Text("🎤 Melody Only (Vocal)").tag(ReferenceMode.melodyOnly)
                    Text("🎼 Full Reference (Song)").tag(ReferenceMode.fullReference)
                }
                .pickerStyle(.segmented)

                Text(appState.referenceMode.description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)

            Divider()

            // Key & Modal Scale Manipulation
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Key & Musical Properties Manipulation")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Spacer()
                    Text("Shift: \(appState.keyShiftSemitones >= 0 ? "+\(appState.keyShiftSemitones)" : "\(appState.keyShiftSemitones)") semitones")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 10) {
                    // Semitone Pitch Stepper
                    Button(action: { appState.applyKeyShift(delta: -1) }) {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Slider(value: Binding(
                        get: { Double(appState.keyShiftSemitones) },
                        set: {
                            let newShift = Int($0)
                            let delta = newShift - appState.keyShiftSemitones
                            if delta != 0 {
                                appState.applyKeyShift(delta: delta)
                            }
                        }
                    ), in: -12...12, step: 1)

                    Button(action: { appState.applyKeyShift(delta: 1) }) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Reset") {
                        let delta = -appState.keyShiftSemitones
                        appState.applyKeyShift(delta: delta)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                // Modal Scale Conversion (Major <-> Minor)
                HStack(spacing: 8) {
                    Text("Mode Shift:")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Picker("Mode Shift", selection: Binding(
                        get: { appState.modeTransform },
                        set: { appState.applyModeTransform($0) }
                    )) {
                        Text("Original Key").tag(ModeTransform.none)
                        Text("Major ➔ Minor (Melancholic)").tag(ModeTransform.majorToMinor)
                        Text("Minor ➔ Major (Uplifting)").tag(ModeTransform.minorToMajor)
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                }
            }

            // Quick Alignment Actions
            HStack(spacing: 10) {
                Button(action: {
                    appState.extractMelodyFromReference()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "music.note.list")
                        Text("Extract Melody to Score")
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(action: {
                    appState.alignLyricsWithMelody()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "text.quote")
                        Text("Align Lyrics to Melody")
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.top, 2)

            Divider()

            // End-to-End Cover Pipeline
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("End-to-End Cover Pipeline", systemImage: "sparkles.rectangle.stack.fill")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)

                    Spacer()

                    Button(action: {
                        exportBundle()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.doc")
                            Text("Export Bundle (ABC + MIDI + LAB)")
                        }
                        .font(.caption2)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Text("Transcribe source audio ➔ Extract melody & structure ➔ Re-synthesize with new styles")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    Button(action: {
                        appState.prepareCoverPipeline()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "bolt.fill")
                            Text("Prime 1-Click Cover Pipeline")
                        }
                        .font(.caption.bold())
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                // Quick Style Morphing Presets
                VStack(alignment: .leading, spacing: 4) {
                    Text("Re-synthesize with Target Style:")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)

                    HStack(spacing: 6) {
                        CoverGenreChip(title: "80s Synthwave", genre: "80s synthwave, retro analog synth, driving linndrum, neon pads, female vocal, 124 bpm", appState: appState)
                        CoverGenreChip(title: "Acoustic Folk", genre: "acoustic folk, fingerpicked warm guitar, soft strings, intimate vocal, authentic warmth, 110 bpm", appState: appState)
                        CoverGenreChip(title: "Cyberpunk EDM", genre: "cyberpunk edm, aggressive bass drop, massive saw synths, sidechained four-on-the-floor, energetic vocal, 128 bpm", appState: appState)
                        CoverGenreChip(title: "Lo-Fi Jazz Pop", genre: "lo-fi jazz pop, mellow rhodes piano, vinyl crackle, gentle drums, relaxed soulful vocal, 85 bpm", appState: appState)
                        CoverGenreChip(title: "Rock Anthem", genre: "modern rock anthem, distorted electric guitars, powerful live drums, soaring passionate vocal, stadium energy, 130 bpm", appState: appState)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.6))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
    }

    private func exportBundle() {
        let panel = NSOpenPanel()
        panel.title = "Choose Destination Directory for Transcription Bundle"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let targetDir = panel.url {
            do {
                _ = try appState.exportTranscriptionBundle(
                    directory: targetDir,
                    baseName: appState.referenceAudioName ?? appState.songTitle
                )
            } catch {
                print("[CoverStudioView] Bundle export failed: \(error)")
            }
        }
    }

    private func chooseReferenceAudio() {
        let panel = NSOpenPanel()
        panel.title = "Choose Audio Reference Track"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            UTType.wav,
            UTType.mp3,
            UTType.audio,
            UTType(filenameExtension: "m4a") ?? .audio,
            UTType(filenameExtension: "flac") ?? .audio
        ]

        if panel.runModal() == .OK, let url = panel.url {
            appState.loadReferenceAudio(url: url)
        }
    }
}

private struct CoverGenreChip: View {
    let title: String
    let genre: String
    let appState: AppState

    var body: some View {
        Button(action: {
            appState.prepareCoverPipeline(targetGenre: genre)
        }) {
            Text(title)
                .font(.system(size: 10))
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
    }
}
