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
            }

            Section("Apple Silicon & Unified Memory") {
                LabeledContent("System RAM") {
                    Text(appState.memoryStats.displayString)
                        .foregroundColor(.secondary)
                }

                Toggle("Auto-Unload Stage 1 after coarse tokens", isOn: Binding(
                    get: { appState.autoUnloadStage1 },
                    set: {
                        appState.autoUnloadStage1 = $0
                        appState.settingsRepo.set(key: .autoUnloadStage1, value: $0 ? "true" : "false")
                    }
                ))
                .help("Releases 7B model weights and KV-cache from unified memory before running acoustic refinement, preventing memory pressure on 16GB–24GB Apple Silicon Macs.")
            }

            Section("Audio Engine") {
                LabeledContent("Synthesis Sample Rate") {
                    Text("44,100 Hz (CD Quality, 24-bit Float)")
                        .foregroundColor(.secondary)
                }

                LabeledContent("Channels") {
                    Text("Stereo (2 Channels)")
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
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
}
