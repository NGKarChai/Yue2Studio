import SwiftUI

public struct BuildFooterView: View {
    @Bindable var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        HStack(spacing: 16) {
            // Status Indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(appState.isGenerating ? Color.green : (appState.isModelsReady ? Color.blue : Color.orange))
                    .frame(width: 8, height: 8)
                Text(appState.isGenerating ? "Inference Active" : (appState.isModelsReady ? "Models Ready" : "Models Incomplete"))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Divider().frame(height: 12)

            // Model Directory Path
            HStack(spacing: 4) {
                Image(systemName: "folder")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(appState.modelDirectoryPath)
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Unified Memory Usage
            HStack(spacing: 4) {
                Image(systemName: "memorychip")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(appState.memoryStats.displayString)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Divider().frame(height: 12)

            // Build Number per user rule 7 & 8
            HStack(spacing: 4) {
                Text("Build:")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(AppState.buildNumber)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(NSColor.separatorColor)),
            alignment: .top
        )
    }
}
