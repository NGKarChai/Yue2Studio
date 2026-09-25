import SwiftUI
import AVFoundation

public struct WaveformPlayerView: View {
    @Bindable var player: AudioPlaybackEngine
    var audioBuffer: AVAudioPCMBuffer?
    var onExport: (() -> Void)?
    var onExtractInstrumental: (() -> Void)?

    @State private var exportFormat: AudioExporter.AudioFormat = .wav
    @State private var showingExportSuccess: Bool = false

    public init(
        player: AudioPlaybackEngine,
        audioBuffer: AVAudioPCMBuffer? = nil,
        onExport: (() -> Void)? = nil,
        onExtractInstrumental: (() -> Void)? = nil
    ) {
        self.player = player
        self.audioBuffer = audioBuffer
        self.onExport = onExport
        self.onExtractInstrumental = onExtractInstrumental
    }

    public var body: some View {
        VStack(spacing: 12) {
            // Waveform Canvas
            GeometryReader { geo in
                Canvas { context, size in
                    drawWaveform(context: context, size: size)
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let fraction = max(0, min(1.0, value.location.x / geo.size.width))
                            player.seek(to: fraction * player.duration)
                        }
                )
            }
            .frame(height: 72)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
            )

            // Controls & Scrubber
            HStack(spacing: 16) {
                // Play / Pause
                Button(action: {
                    if player.isPlaying {
                        player.pause()
                    } else {
                        player.play()
                    }
                }) {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)

                // Stop
                Button(action: {
                    player.stop()
                }) {
                    Image(systemName: "stop.circle")
                        .font(.system(size: 22))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                // Time indicators
                Text(formatTime(player.currentTime))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.primary)

                Slider(value: Binding(
                    get: { player.currentTime },
                    set: { player.seek(to: $0) }
                ), in: 0...max(player.duration, 0.1))
                .controlSize(.small)

                Text(formatTime(player.duration))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)

                Divider().frame(height: 16)

                // Volume
                HStack(spacing: 4) {
                    Image(systemName: player.volume == 0 ? "speaker.slash" : (player.volume > 1.0 ? "speaker.wave.3.fill" : "speaker.wave.2"))
                        .font(.caption)
                        .foregroundColor(player.volume > 1.0 ? .accentColor : .secondary)
                    Slider(value: $player.volume, in: 0...1.5, step: 0.05)
                        .frame(width: 75)
                        .controlSize(.mini)
                        .help("Playback volume: up to 150% (+3.5 dB boost for quiet headphones/speakers)")
                    Text(String(format: "%d%%", Int(player.volume * 100)))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }

                Divider().frame(height: 16)

                // Stereo Width Slider
                HStack(spacing: 4) {
                    Image(systemName: "arrow.left.and.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Slider(value: $player.stereoWidth, in: 0.0...1.0, step: 0.05)
                        .frame(width: 60)
                        .controlSize(.mini)
                        .help("Stereo Width: 0% (Solid Centered Mono) to 100% (Wide Stereo). Lower values eliminate artificial spatial widening.")
                }

                Divider().frame(height: 16)

                // Extract Instrumental Button
                if let onExtract = onExtractInstrumental {
                    Button(action: {
                        onExtract()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "guitars.fill")
                            Text("Extract Instrumental")
                        }
                        .font(.caption)
                    }
                    .disabled(audioBuffer == nil)
                    .help("Cancel center lead vocals and extract a pure instrumental track preserving bass and instruments")
                }

                // Export Button
                Button(action: {
                    exportAudio()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Export WAV")
                    }
                    .font(.caption)
                }
                .disabled(audioBuffer == nil)
            }
        }
        .padding(14)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
    }

    private func drawWaveform(context: GraphicsContext, size: CGSize) {
        let width = size.width
        let height = size.height
        let centerY = height / 2.0
        let barCount = Int(width / 3.5)

        // Draw background center line
        var centerLine = Path()
        centerLine.move(to: CGPoint(x: 0, y: centerY))
        centerLine.addLine(to: CGPoint(x: width, y: centerY))
        context.stroke(centerLine, with: .color(Color.gray.opacity(0.3)), lineWidth: 1)

        guard let buffer = audioBuffer, let channelData = buffer.floatChannelData?[0] else {
            // Draw idle waveform placeholder
            for i in 0..<barCount {
                let x = CGFloat(i) * 3.5 + 1.5
                let idleHeight = CGFloat(sin(Double(i) * 0.2)) * 6 + 10
                let bar = Path(CGRect(x: x, y: centerY - idleHeight / 2, width: 2, height: idleHeight))
                context.fill(bar, with: .color(Color.gray.opacity(0.3)))
            }
            return
        }

        let totalFrames = Int(buffer.frameLength)
        let framesPerBar = max(1, totalFrames / barCount)
        let playbackX = player.duration > 0 ? (CGFloat(player.currentTime / player.duration) * width) : 0

        for i in 0..<barCount {
            let startFrame = i * framesPerBar
            let endFrame = min(startFrame + framesPerBar, totalFrames)

            var maxAmp: Float = 0.0
            for f in startFrame..<endFrame {
                let amp = abs(channelData[f])
                if amp > maxAmp { maxAmp = amp }
            }

            let barHeight = max(2.0, CGFloat(maxAmp) * (height * 0.85))
            let x = CGFloat(i) * 3.5 + 1.5
            let bar = Path(CGRect(x: x, y: centerY - barHeight / 2, width: 2, height: barHeight))

            let isPlayed = x <= playbackX
            context.fill(bar, with: .color(isPlayed ? Color.accentColor : Color.gray.opacity(0.45)))
        }

        // Draw Playhead cursor
        var playhead = Path()
        playhead.move(to: CGPoint(x: playbackX, y: 0))
        playhead.addLine(to: CGPoint(x: playbackX, y: height))
        context.stroke(playhead, with: .color(Color.white), lineWidth: 2)
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    private func exportAudio() {
        guard let buffer = audioBuffer else { return }
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.wav]
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = "YuE_Output.wav"

        if savePanel.runModal() == .OK, let url = savePanel.url {
            try? AudioExporter.export(buffer: buffer, to: url, format: .wav)
        }
    }
}
