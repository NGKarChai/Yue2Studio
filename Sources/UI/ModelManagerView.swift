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
                Text("Model Storage & Weight Manager")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Configure local model directories or download required stage weights directly into the application folder. YuE executes natively on Apple Silicon with zero Python dependencies.")
                    .font(.callout)
                    .foregroundColor(.secondary)

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Active Weights Directory")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            Image(systemName: "folder")
                                .foregroundColor(.secondary)
                            Text(appState.modelDirectoryPath)
                                .font(.system(.body, design: .monospaced))
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                        )
                    }

                    VStack(spacing: 4) {
                        Text(" ")
                            .font(.caption)
                        HStack {
                            Button("Browse...") {
                                selectCustomDirectory()
                            }
                            Button("Reset to ./Models") {
                                appState.setModelDirectory(newPath: "Models")
                            }
                        }
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
        let download = appState.downloadManager.activeDownloads[item.id]
        let stageURL = URL(fileURLWithPath: appState.modelDirectoryPath).appendingPathComponent(item.stage)
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

    private func selectCustomDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Model Folder"

        if panel.runModal() == .OK, let url = panel.url {
            appState.setModelDirectory(newPath: url.path)
        }
    }

    private func triggerDownload(for item: ModelItem) {
        let destURL = URL(fileURLWithPath: appState.modelDirectoryPath).appendingPathComponent(item.stage)
        appState.downloadManager.downloadStage(id: item.id, name: item.name, to: destURL)
    }
}
