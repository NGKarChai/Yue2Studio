import SwiftUI
import AppKit

public struct ModelManagerView: View {
    @Bindable var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header & Path Selector
            VStack(alignment: .leading, spacing: 8) {
                Text("YuE2 Model Storage & Weight Manager")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Configure local model directories or download required YuE2 weights directly into the application folder. YuE2 executes natively on Apple Silicon via MLX Flow Matching + 48kHz VAE with zero Python dependencies.")
                    .font(.callout)
                    .foregroundColor(.secondary)

                // YuE2-3B Generator & VAE Configuration
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("YuE2-3B Weights (vanch007/mlx-Yue2-3B)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            HStack {
                                Image(systemName: "folder")
                                    .foregroundColor(.secondary)
                                Text(appState.yue2ModelDirectory)
                                    .font(.system(.body, design: .monospaced))
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(6)
                        }
                        Button("Browse...") {
                            selectDirectory { path in
                                appState.setYuE2ModelDirectory(path)
                            }
                        }
                        .padding(.top, 16)
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("YuE2 48kHz Oobleck VAE (m-a-p/YuE2-Vae)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            HStack {
                                Image(systemName: "waveform")
                                    .foregroundColor(.secondary)
                                Text(appState.yue2VAEDirectory)
                                    .font(.system(.body, design: .monospaced))
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(6)
                        }
                        Button("Browse...") {
                            selectDirectory { path in
                                appState.setYuE2VAEDirectory(path)
                            }
                        }
                        .padding(.top, 16)
                    }
                }
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)

            // Models List
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("PIPELINE STAGE WEIGHTS")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)

                    Spacer()

                    Button(action: {
                        appState.checkModelsAvailability()
                    }) {
                        Label("Rescan Folder", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                }

                ForEach(appState.modelList) { item in
                    modelRow(for: item)
                }
            }

            Spacer()
        }
        .padding(20)
    }

    private func modelRow(for item: ModelItem) -> some View {
        _ = appState.downloadProgressTick
        let download = appState.downloadManager.activeDownloads[item.id]
        let stageURL = appState.directoryURL(for: item)
        let hasWeights = appState.directoryHasWeights(stageURL)
        let sizeOnDisk = appState.directoryWeightSizeString(stageURL)
        let manifest = ModelDownloadManager.stageManifests[item.id]

        return HStack(spacing: 16) {
            Image(systemName: hasWeights ? "checkmark.circle.fill" : (download != nil ? "arrow.down.circle.fill" : "exclamationmark.circle"))
                .font(.title2)
                .foregroundColor(hasWeights ? .green : (download != nil ? .blue : .orange))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(item.name)
                        .font(.headline)

                    Text(item.stage.uppercased())
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(4)

                    if let manifest = manifest {
                        Text(manifest.totalEstimatedSize)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Text("Hugging Face: \(item.repoId)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if hasWeights, let size = sizeOnDisk {
                    Text("Installed on disk: \(size)")
                        .font(.caption2)
                        .foregroundColor(.green)
                } else if let size = sizeOnDisk {
                    Text("Metadata only (\(size)), model weights (.safetensors) missing")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }

                if let dl = download, dl.progressFraction < 1.0 {
                    VStack(alignment: .leading, spacing: 3) {
                        ProgressView(value: dl.progressFraction)
                            .progressViewStyle(.linear)
                        HStack {
                            Text(dl.status)
                                .font(.caption2)
                            Spacer()
                            Text(dl.progressPercentString)
                                .font(.caption2)
                                .fontWeight(.semibold)
                        }
                    }
                    .padding(.top, 4)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Button(action: {
                    if !FileManager.default.fileExists(atPath: stageURL.path) {
                        try? FileManager.default.createDirectory(at: stageURL, withIntermediateDirectories: true)
                    }
                    NSWorkspace.shared.open(stageURL)
                }) {
                    Image(systemName: "folder")
                    Text("Open Folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Open stage folder in Finder to drop existing .safetensors files")

                if hasWeights {
                    Text("Ready")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.green.opacity(0.12))
                        .cornerRadius(6)
                } else {
                    if download != nil && download!.progressFraction < 1.0 {
                        Button("Cancel") {
                            appState.downloadManager.cancelDownload(id: item.id)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        Button("Download Weights") {
                            triggerDownload(for: item)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }


    private func selectDirectory(completion: (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Folder"

        if panel.runModal() == .OK, let url = panel.url {
            completion(url.path)
        }
    }

    private func triggerDownload(for item: ModelItem) {
        let destURL = appState.directoryURL(for: item)
        appState.downloadManager.downloadStage(id: item.id, name: item.name, to: destURL)
    }
}
