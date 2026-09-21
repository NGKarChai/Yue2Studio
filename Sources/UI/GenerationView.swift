import SwiftUI

public struct GenerationView: View {
    @Bindable var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        HStack(spacing: 0) {
            // Left Panel: Studio Inputs & Audio Player in ScrollView
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 14) {
                    // Model Missing Warning Banner
                    if !appState.isModelsReady {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.title3)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Model Weights Not Downloaded")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                Text("Full generation requires stage weights in '\(appState.modelDirectoryPath)'. You can download weights in Model Manager or click Demo Preview to test the audio player right away.")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Button("Model Manager") {
                                appState.currentTab = .models
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(10)
                        .background(Color.orange.opacity(0.12))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                        )
                    }

                    // Song Title & Presets bar
                    HStack {
                        TextField("Song Title", text: $appState.songTitle)
                            .font(.headline)
                            .textFieldStyle(.roundedBorder)

                        Spacer()

                        // Presets Menu (from SQLite database)
                        Menu {
                            Section("Genre Presets") {
                                ForEach(appState.presetGenres) { preset in
                                    Button(preset.name) {
                                        appState.applyPresetGenre(preset)
                                    }
                                }
                            }
                            Section("Lyric Templates") {
                                ForEach(appState.presetLyrics) { preset in
                                    Button(preset.title) {
                                        appState.applyPresetLyric(preset)
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                Text("Presets")
                            }
                            .font(.caption)
                        }
                    }

                    // Genre & Style Tags Input
                    VStack(alignment: .leading, spacing: 6) {
                        Text("GENRE & STYLE TAGS")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)

                        TextField("e.g. female vocal, modern melodic pop, piano, 120 bpm", text: $appState.genreTags)
                            .textFieldStyle(.roundedBorder)
                            .font(.callout)
                    }

                    // Structured Lyrics Editor (bounded height so it doesn't push controls away)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("STRUCTURED LYRICS")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.secondary)

                            Spacer()

                            // Tag insert buttons
                            HStack(spacing: 4) {
                                tagButton("[verse]")
                                tagButton("[chorus]")
                                tagButton("[bridge]")
                                tagButton("[intro]")
                                tagButton("[outro]")
                            }
                        }

                        TextEditor(text: $appState.lyrics)
                            .font(.system(.body, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .frame(minHeight: 120, maxHeight: 180)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                            )
                    }

                    // Composition & Planning Mode Selector
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("COMPOSITION & PLANNING MODE")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.secondary)

                            Spacer()

                            Text(appState.planningMode.description)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        Picker("Mode", selection: $appState.planningMode) {
                            ForEach(PlanningMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    // Audio Reference & Cover Song Creation Studio
                    if appState.planningMode == .melodyCover || appState.referenceAudioURL != nil {
                        CoverStudioView(appState: appState)
                    }

                    // YuE2 Symbolic Score Viewer & Editor (when in Symbolic Plan or Zero-Shot Cover mode)
                    if appState.planningMode != .directAudio {
                        ScoreEditorView(state: appState)
                    }

                    // Action Bar: Generate Full Song & Demo Preview Buttons
                    HStack(spacing: 12) {
                        if appState.isGenerating {
                            Button(role: .destructive, action: {
                                appState.cancelGeneration()
                            }) {
                                HStack {
                                    Image(systemName: "stop.fill")
                                    Text("Cancel Generation")
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                        } else {
                            Button(action: {
                                appState.startGeneration()
                            }) {
                                HStack {
                                    Image(systemName: "wand.and.stars")
                                    Text("Generate Full Song")
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)

                            Button(action: {
                                appState.startDemoSynthesis()
                            }) {
                                HStack {
                                    Image(systemName: "play.badge.sparkle")
                                    Text("Demo Preview")
                                }
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .help("Test audio engine, waveform display, and WAV export immediately without downloading full 7B model weights.")
                        }
                    }

                    // Live Telemetry Log View
                    if appState.isGenerating || appState.currentProgress.phase != .idle {
                        LogConsoleView(progress: appState.currentProgress)
                    }

                    // Waveform Player
                    WaveformPlayerView(
                        player: appState.audioPlayer,
                        audioBuffer: appState.activeAudioBuffer
                    )
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity)

            Divider()

            // Right Panel: Parameter Inspector (fixed comfortable width, never clipped)
            ScrollView(.vertical, showsIndicators: true) {
                ParameterView(appState: appState)
            }
            .frame(width: 320)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .alert("Model Weights Required", isPresented: $appState.showMissingModelsAlert) {
            Button("Open Model Manager") {
                appState.currentTab = .models
            }
            Button("Run Demo Preview") {
                appState.startDemoSynthesis()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(appState.missingModelsMessage)
        }
    }

    private func tagButton(_ tag: String) -> some View {
        Button(action: {
            if !appState.lyrics.isEmpty && !appState.lyrics.hasSuffix("\n") {
                appState.lyrics += "\n"
            }
            appState.lyrics += "\(tag)\n"
        }) {
            Text(tag)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
    }
}
