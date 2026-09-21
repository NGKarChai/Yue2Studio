import SwiftUI

public struct ParameterView: View {
    @Bindable var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("SAMPLING & INFERENCE")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)

            // Precision Picker
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Quantization Precision")
                        .font(.caption)
                        .foregroundColor(.primary)
                    Spacer()
                    Text(appState.quantizationPrecision)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.accentColor)
                }
                Picker("", selection: Binding(
                    get: { appState.quantizationPrecision },
                    set: { appState.setQuantization(precision: $0) }
                )) {
                    Text("4-bit").tag("4-bit")
                    Text("8-bit").tag("8-bit")
                    Text("16-bit").tag("16-bit")
                }
                .pickerStyle(.segmented)

                Text(precisionDescription)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Temperature Slider
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Temperature")
                        .font(.caption)
                    Spacer()
                    Text(String(format: "%.2f", appState.temperature))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Slider(value: $appState.temperature, in: 0.1...1.5, step: 0.05)
            }

            // Top-P Slider
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Top-P (Nucleus)")
                        .font(.caption)
                    Spacer()
                    Text(String(format: "%.2f", appState.topP))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Slider(value: $appState.topP, in: 0.5...1.0, step: 0.01)
            }

            // CFG Scale Slider
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("CFG Scale")
                        .font(.caption)
                    Spacer()
                    Text(String(format: "%.2f", appState.cfgScale))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Slider(value: $appState.cfgScale, in: 1.0...3.0, step: 0.1)
            }

            // Max Tokens Slider with Direct Entry & Duration Estimate
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Max Audio Tokens")
                        .font(.caption)
                    Spacer()
                    // Stage 1 interleaves a vocal and an instrumental token per
                    // 50 Hz frame, so one second of audio costs 100 tokens.
                    let estSec = Double(appState.maxTokens) / 100.0
                    if estSec >= 60.0 {
                        let mins = Int(estSec) / 60
                        let secs = Int(estSec) % 60
                        Text("\(appState.maxTokens) tokens (~\(mins)m \(secs)s)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text(String(format: "%d tokens (~%.0fs)", appState.maxTokens, estSec))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                HStack(spacing: 8) {
                    Slider(value: Binding(
                        get: { Double(appState.maxTokens) },
                        set: { appState.maxTokens = Int($0) }
                    ), in: 200...36000, step: 128)

                    TextField("Tokens", value: $appState.maxTokens, formatter: NumberFormatter())
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 75)
                        .font(.caption)
                }

                // Long songs are measured in hours, not minutes. Stage 1 decodes one
                // token at a time and Stage 2 runs 7 sequential steps per frame, so
                // surface the cost before the user commits to it.
                if appState.maxTokens > 8000 {
                    let stage1Min = Double(appState.maxTokens) / 10.0 / 60.0
                    let frames = Double(appState.maxTokens) / 2.0
                    let stage2Steps = frames * Double(max(0, appState.stage2Quality.targetCodebooks - 1))
                    let stage2Min = stage2Steps / 40.0 / 60.0
                    let total = stage1Min + stage2Min
                    HStack(spacing: 5) {
                        Image(systemName: "clock")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(String(format: "Rough estimate: ~%.0f min (Stage 1 ~%.0f, Stage 2 ~%.0f at %@)",
                                    total, stage1Min, stage2Min, appState.stage2Quality.rawValue))
                            .font(.caption2)
                            .foregroundColor(total > 60 ? .orange : .secondary)
                    }
                    .padding(.top, 2)
                }

                // The budget is split across lyric sections. Too small a budget cuts
                // every section off mid-phrase, which sounds like a half-finished song
                // rather than a short one, so warn before the user spends the time.
                let sectionCount = PromptFormatter.prepareOrderedSegments(lyrics: appState.lyrics).count
                if sectionCount > 0 {
                    let secondsEach = Double(appState.maxTokens) / 100.0 / Double(sectionCount)
                    if secondsEach < 6.0 {
                        let suggested = min(16384, ((sectionCount * 1000) / 128) * 128 + 128)
                        HStack(alignment: .top, spacing: 5) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.caption2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(format: "%d sections share this budget — about %.1fs each.",
                                            sectionCount, secondsEach))
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                                Text("Sections get cut off mid-phrase below ~6s. Try \(suggested) tokens, or use fewer sections.")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Button("Use \(suggested) tokens") {
                                    appState.maxTokens = suggested
                                }
                                .font(.caption2)
                                .buttonStyle(.link)
                            }
                        }
                        .padding(.top, 2)
                    }
                }
            }

            // Seed & Auto-Seed
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Toggle("Random Seed", isOn: $appState.autoSeed)
                        .font(.caption)
                    Spacer()
                    if !appState.autoSeed {
                        TextField("Seed", value: $appState.seed, formatter: NumberFormatter())
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                }
            }

            Divider()

            // Acoustic Mastering & Stereo Width
            VStack(alignment: .leading, spacing: 6) {
                Text("ACOUSTIC MASTERING & STEREO")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Stereo Width")
                            .font(.caption)
                        Spacer()
                        Text("\(Int(appState.stereoWidth * 100))% (\(stereoWidthLabel))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Slider(value: Binding(
                        get: { appState.stereoWidth },
                        set: { appState.setStereoWidth($0) }
                    ), in: 0.0...1.0, step: 0.05)

                    Text("0% for centered mono (avoids artificial spatial widening on macOS/AirPods). 50% for natural balanced acoustic mix.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Divider()
                    .padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 3) {
                    Toggle("Level & Compress", isOn: Binding(
                        get: { appState.levelingEnabled },
                        set: { appState.setLevelingEnabled($0) }
                    ))
                    .font(.caption)

                    Text("Each section is generated independently, so their levels drift by 10 dB or more and the vocal seems to wander. Levels sections against each other and tames surges.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Divider()
                    .padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 3) {
                    Toggle("44.1 kHz Vocos Upsampler", isOn: Binding(
                        get: { appState.upsampleEnabled },
                        set: { appState.setUpsampleEnabled($0) }
                    ))
                    .font(.caption)

                    Text("The official YuE final stage. X-Codec renders at 16 kHz and stops at 8 kHz; Vocos synthesizes a true 44.1 kHz band from the same features, crossed over at 5.5 kHz. Needs Models/upsampler.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Divider()
                    .padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 3) {
                    Toggle("Corrective EQ", isOn: Binding(
                        get: { appState.masteringEnabled },
                        set: { appState.setMasteringEnabled($0) }
                    ))
                    .font(.caption)

                    Text("X-Codec renders at 16 kHz with a heavy low-end tilt. Cuts sub-bass and 220 Hz boxiness, lifts 1.2 kHz body and 3.2 kHz presence (~8 dB). Turn off for the raw codec output.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // Stage 2 Acoustic Refinement Quality & Speed Mode
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Stage 2 Refinement Quality")
                        .font(.caption)
                    Spacer()
                }

                Picker("Refinement Quality", selection: Binding(
                    get: { appState.stage2Quality },
                    set: { appState.setStage2Quality($0) }
                )) {
                    Text("Draft").tag(Stage2Quality.draft)
                    Text("Balanced").tag(Stage2Quality.balanced)
                    Text("Master").tag(Stage2Quality.full)
                }
                .pickerStyle(.segmented)

                Text(stage2QualityDescription)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Divider()

            // Memory Management Options
            Toggle("Unload Stage 1 to Free RAM", isOn: $appState.autoUnloadStage1)
                .font(.caption)
                .help("Automatically release Stage 1 weights and KV-cache from Apple Silicon unified memory before Stage 2 refinement begins.")
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(14)
    }

    private var stage2QualityDescription: String {
        switch appState.stage2Quality {
        case .draft:
            return "🚀 Draft (Instant): 0s Stage 2 pass-through directly to decoder. Instant preview of lyrics & harmony."
        case .balanced:
            return "⚡ Balanced (5x Faster): Refines Codebooks 1-3 (>92% acoustic fidelity) with parallel dual-track batching."
        case .full:
            return "💎 Studio Master (2x Faster): Full 7-codebook refinement with parallel dual-track batching for master export."
        }
    }

    private var stereoWidthLabel: String {
        if appState.stereoWidth <= 0.05 {
            return "Solid Mono"
        } else if appState.stereoWidth <= 0.35 {
            return "Focused Center"
        } else if appState.stereoWidth <= 0.65 {
            return "Natural Balanced"
        } else {
            return "Wide Stereo"
        }
    }

    private var precisionDescription: String {
        switch appState.quantizationPrecision {
        case "4-bit":
            return "4-bit: Ultra-fast generation, ~6 GB memory"
        case "8-bit":
            return "8-bit: Recommended balance of speed & quality"
        default:
            return "16-bit: Full FP16 precision, ~20 GB memory"
        }
    }
}
