import SwiftUI

public struct SettingsView: View {
    @Bindable var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        Form {
            Section("Storage & Database") {
                LabeledContent("SQLite Database Path") {
                    Text(appState.database.path)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                LabeledContent("Generations Directory") {
                    Text("Generations/")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                LabeledContent("YuE2-3B Models Path") {
                    Text(appState.yue2ModelDirectory)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                LabeledContent("YuE2-VAE Path") {
                    Text(appState.yue2VAEDirectory)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }

            Section("Apple Silicon & Unified Memory") {
                LabeledContent("System RAM") {
                    Text(appState.memoryStats.displayString)
                        .foregroundColor(.secondary)
                }

                LabeledContent("Compute Backend") {
                    Text("Apple Silicon Metal GPU (Accelerated)")
                        .foregroundColor(.secondary)
                }
            }

            Section("Audio Engine") {
                LabeledContent("Synthesis Sample Rate") {
                    Text("48,000 Hz (Master Studio Quality, 32-bit Float)")
                        .foregroundColor(.secondary)
                }

                LabeledContent("Channels") {
                    Text("Stereo (2 Channels)")
                        .foregroundColor(.secondary)
                }

                LabeledContent("Neural Vocoder") {
                    Text("YuE2 Oobleck 48kHz VAE Decoder")
                        .foregroundColor(.secondary)
                }
            }

            Section("Application Info") {
                LabeledContent("Build Number") {
                    Text(AppState.buildNumber)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.semibold)
                }

                LabeledContent("Runtime Engine") {
                    Text("Native Swift + Apple MLX + Metal (Zero Python)")
                        .foregroundColor(.secondary)
                }

                LabeledContent("Architecture") {
                    Text("YuE2-3B Flow Matching ODE")
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
}
