import SwiftUI
import AVFoundation

public struct HistoryView: View {
    @Bindable var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Generation Library")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                Text("\(appState.historyRecords.count) Songs")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if appState.historyRecords.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "music.note.list")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No generations in library yet.")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Generate a song from the Studio to build your library.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(appState.historyRecords) { record in
                        historyRow(for: record)
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding(20)
    }

    private func historyRow(for record: GenerationRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(record.title)
                    .font(.headline)

                Spacer()

                Text(formatTimestamp(record.createdAt))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Text(record.genreTags)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)

            HStack(spacing: 16) {
                Label(String(format: "%.1f s", record.durationSeconds), systemImage: "clock")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Label("Seed: \(record.seed)", systemImage: "number")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Spacer()

                Button("Load in Player") {
                    loadAudio(for: record)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(role: .destructive, action: {
                    appState.generationRepo.delete(id: record.id)
                    appState.historyRecords = appState.generationRepo.getAll()
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
    }

    private func loadAudio(for record: GenerationRecord) {
        let fileURL = URL(fileURLWithPath: record.audioPath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            print("[HistoryView] File does not exist at \(record.audioPath)")
            return
        }

        do {
            let audioFile = try AVAudioFile(forReading: fileURL)
            let format = audioFile.processingFormat
            let frameCount = AVAudioFrameCount(audioFile.length)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
            try audioFile.read(into: buffer)

            appState.activeAudioBuffer = buffer
            appState.songTitle = record.title
            appState.genreTags = record.genreTags
            appState.lyrics = record.lyrics
            appState.audioPlayer.load(buffer: buffer)
            appState.currentTab = .studio
        } catch {
            print("[HistoryView] Failed to load audio buffer: \(error)")
        }
    }

    private func formatTimestamp(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: isoString) {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        return isoString
    }
}
