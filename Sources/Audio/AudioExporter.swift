import Foundation
import AVFoundation

public struct AudioExporter {
    public enum AudioFormat: String, CaseIterable, Identifiable {
        case wav = "WAV"
        case aac = "AAC"
        case flac = "FLAC"

        public var id: String { rawValue }
        public var fileExtension: String {
            switch self {
            case .wav: return "wav"
            case .aac: return "m4a"
            case .flac: return "flac"
            }
        }
    }

    /// Export an AVAudioPCMBuffer to a specified file URL
    public static func export(
        buffer: AVAudioPCMBuffer,
        to destinationURL: URL,
        format: AudioFormat = .wav
    ) throws {
        let parentDir = destinationURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentDir.path) {
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        var settings: [String: Any] = [:]

        switch format {
        case .wav:
            settings = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: buffer.format.sampleRate,
                AVNumberOfChannelsKey: buffer.format.channelCount,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
        case .aac:
            settings = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: buffer.format.sampleRate,
                AVNumberOfChannelsKey: buffer.format.channelCount,
                AVEncoderBitRateKey: 256000
            ]
        case .flac:
            settings = [
                AVFormatIDKey: kAudioFormatFLAC,
                AVSampleRateKey: buffer.format.sampleRate,
                AVNumberOfChannelsKey: buffer.format.channelCount,
                AVLinearPCMBitDepthKey: 24
            ]
        }

        let audioFile = try AVAudioFile(forWriting: destinationURL, settings: settings)
        try audioFile.write(from: buffer)
        print("[AudioExporter] Successfully exported audio to \(destinationURL.path)")
    }
}
