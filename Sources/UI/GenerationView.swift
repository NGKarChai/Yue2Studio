import SwiftUI

public struct GenerationView: View {
    @Bindable var appState: AppState
    @State private var showInspector: Bool = true

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        GeometryReader { geometry in
            let inspectorWidth: CGFloat = 340
            let rightPanelWidth: CGFloat = showInspector ? inspectorWidth : 0
            let leftPanelWidth = showInspector
                ? max(320, geometry.size.width - rightPanelWidth - 1)
                : geometry.size.width

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

                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showInspector.toggle()
                                }
                            }) {
                                Label(showInspector ? "Parameters" : "Show Parameters", systemImage: showInspector ? "sidebar.right" : "slider.horizontal.3")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .help("Toggle Parameter Inspector")
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

                    // Instrumental Only Checkbox Bar
                    HStack(spacing: 10) {
                        Toggle(isOn: $appState.isInstrumentalOnly) {
                            HStack(spacing: 6) {
                                Image(systemName: appState.isInstrumentalOnly ? "guitars.fill" : "mic.fill")
                                    .foregroundColor(appState.isInstrumentalOnly ? .green : .accentColor)
                                    .font(.subheadline)
                                Text("Instrumental Only (No Vocals)")
                                    .font(.subheadline)
                                    .fontWeight(appState.isInstrumentalOnly ? .semibold : .regular)
                            }
                        }
                        .toggleStyle(.checkbox)
                        .help("Check to generate pure instrumental music. Automatically suppresses all vocal prompts and formats arrangement for instrumental accompaniment.")

                        if appState.isInstrumentalOnly {
                            Text("• Pure Instrumental Mode Active")
                                .font(.caption2)
                                .foregroundColor(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.12))
                                .cornerRadius(4)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 2)

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
                                tagButton("[inst]")
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

                    // Composition & Planning Mode Selector (All 5 Official YuE2 Modes)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .center) {
                            Text("YUE2 GENERATION MODE")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.secondary)

                            Spacer()

                            Picker("Mode", selection: $appState.planningMode) {
                                ForEach(PlanningMode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(minWidth: 260)
                        }

                        HStack(spacing: 6) {
                            Image(systemName: "music.note.list")
                                .font(.caption2)
                                .foregroundColor(.accentColor)
                            Text(appState.planningMode.description)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(8)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    // Audio Reference & Cover Song Creation Studio (active when supplied mode or reference audio loaded)
                    if appState.planningMode.isSupplied || appState.referenceAudioURL != nil {
                        CoverStudioView(appState: appState)
                    }

                    // YuE2 Symbolic Score Viewer & Editor (active in all modes with symbolic score)
                    if appState.planningMode != .direct {
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
                        audioBuffer: appState.activeAudioBuffer,
                        onExtractInstrumental: {
                            appState.extractInstrumentalFromActiveBuffer()
                        }
                    )
                }
                .padding(16)
                .frame(width: leftPanelWidth, alignment: .leading)
            }
            .frame(width: leftPanelWidth, height: geometry.size.height)

            if showInspector {
                Divider()

                // Right Panel: Parameter Inspector (fixed comfortable width, never clipped)
                ScrollView(.vertical, showsIndicators: true) {
                    ParameterView(appState: appState)
                }
                .frame(width: rightPanelWidth, height: geometry.size.height)
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
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
