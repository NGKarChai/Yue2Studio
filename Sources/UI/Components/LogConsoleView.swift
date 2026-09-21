import SwiftUI

public struct LogConsoleView: View {
    let progress: PipelineProgress

    public init(progress: PipelineProgress) {
        self.progress = progress
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("GENERATION TELEMETRY")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)

                Spacer()

                // Phase badge
                Text(progress.phase.rawValue)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(phaseColor(for: progress.phase).opacity(0.15))
                    .foregroundColor(phaseColor(for: progress.phase))
                    .cornerRadius(6)
            }

            ProgressView(value: progress.progressFraction)
                .progressViewStyle(.linear)

            HStack {
                Text(progress.statusMessage.isEmpty ? "Ready" : progress.statusMessage)
                    .font(.callout)
                    .foregroundColor(.primary)

                Spacer()

                if progress.speed > 0 {
                    Text(String(format: "%.1f tok/s", progress.speed))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }

    private func phaseColor(for phase: PipelinePhase) -> Color {
        switch phase {
        case .idle: return .gray
        case .loadingModels: return .orange
        case .stage1Generating: return .purple
        case .stage2Refining: return .blue
        case .decodingAudio: return .teal
        case .complete: return .green
        case .failed: return .red
        }
    }
}
