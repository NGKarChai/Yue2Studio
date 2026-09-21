import SwiftUI

public struct ParameterView: View {
    @Bindable var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("YUE2 INFERENCE SETTINGS")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)

            // YuE2 Flow Matching Steps
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Flow Matching Steps (ODE)")
                        .font(.caption)
                    Spacer()
                    Text("\(appState.yue2FlowSteps) Steps")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.accentColor)
                }
                Picker("", selection: Binding(
                    get: { appState.yue2FlowSteps },
                    set: { appState.setYuE2FlowSteps($0) }
                )) {
                    Text("8 Steps (Fast)").tag(8)
                    Text("32 Steps (Master)").tag(32)
                }
                .pickerStyle(.segmented)
                Text(appState.yue2FlowSteps == 8 ? "🚀 Fast ODE midpoint integration for quick acoustic feedback." : "💎 Full 32-step acoustic flow matching for maximum studio fidelity at 48 kHz.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Song Duration & Token Budget
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Song Duration / Token Budget")
                        .font(.caption)
                    Spacer()
                    let estSec = Double(appState.maxTokens) / 100.0
                    let frames = Int(estSec * 25.0)
                    if estSec >= 60.0 {
                        let mins = Int(estSec) / 60
                        let secs = Int(estSec) % 60
                        Text("~\(mins)m \(secs)s (\(frames) frames)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text(String(format: "~%.0fs (%d frames)", estSec, frames))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                HStack(spacing: 8) {
                    Slider(value: Binding(
                        get: { Double(appState.maxTokens) },
                        set: { appState.maxTokens = Int($0) }
                    ), in: 200...60000, step: 250)

                    TextField("Tokens", value: $appState.maxTokens, formatter: NumberFormatter())
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 75)
                        .font(.caption)
                }

                let totalSec = Double(appState.maxTokens) / 100.0
                let estGenMin = (totalSec * 0.35) / 60.0
                HStack(spacing: 5) {
                    Image(systemName: "bolt.fill")
                        .font(.caption2)
                        .foregroundColor(.green)
                    Text(String(format: "YuE2 Flow Matching: ~%.1f min generation time for %.0fs audio",
                                max(0.1, estGenMin), totalSec))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 2)
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

            // Sampling Hyperparameters
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Temperature")
                        .font(.caption)
                    Spacer()
                    Text(String(format: "%.2f", appState.temperature))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Slider(value: $appState.temperature, in: 0.1...2.0, step: 0.05)
                Text("Controls musical creativity and harmonic variety.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Top-P (Nucleus)")
                        .font(.caption)
                    Spacer()
                    Text(String(format: "%.2f", appState.topP))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Slider(value: $appState.topP, in: 0.1...1.0, step: 0.05)
                Text("Restricts token sampling to cumulative probability mass.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("CFG Guidance Scale")
                        .font(.caption)
                    Spacer()
                    Text(String(format: "%.2f", appState.cfgScale))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Slider(value: $appState.cfgScale, in: 1.0...5.0, step: 0.1)
                Text("Adherence to prompt and lyric genre constraints.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Divider()

            // Acoustic Mastering & Stereo Output
            VStack(alignment: .leading, spacing: 6) {
                Text("AUDIO OUTPUT & STEREO")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)

                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .foregroundColor(.green)
                    Text("YuE2-3B natively generates 48.0 kHz 32-bit float stereo audio via Oobleck VAE. Zero Python vocoders or external post-processors required.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .background(Color.green.opacity(0.1))
                .cornerRadius(6)

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

                    Text("0% for centered mono. 50% for natural balanced acoustic stereo mix.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(14)
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
}
