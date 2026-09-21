import Foundation
import AVFoundation
import Accelerate

/// Shared audio buffer manipulation and format conversion utilities.
public enum AudioBufferUtils {
    /// Reads an AVAudioPCMBuffer back out as per-channel float arrays.
    public static func channelArrays(from buffer: AVAudioPCMBuffer) -> [[Float]] {
        let n = Int(buffer.frameLength)
        let ch = Int(buffer.format.channelCount)
        guard let data = buffer.floatChannelData, n > 0 else { return [] }
        return (0..<ch).map { c in Array(UnsafeBufferPointer(start: data[c], count: n)) }
    }

    /// Builds a float PCM buffer from per-channel sample arrays, optionally peak-normalizing.
    /// Pass `targetPeak: nil` to leave levels untouched.
    public static func makeBuffer(
        channels: [[Float]],
        sampleRate: Double,
        targetPeak: Float? = nil
    ) -> AVAudioPCMBuffer? {
        guard let first = channels.first, !first.isEmpty else { return nil }
        let chCount = channels.count
        let frames = AVAudioFrameCount(first.count)

        let layoutTag: AudioChannelLayoutTag = (chCount == 1) ? kAudioChannelLayoutTag_Mono : kAudioChannelLayoutTag_Stereo
        guard let layout = AVAudioChannelLayout(layoutTag: layoutTag) else { return nil }
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            interleaved: false,
            channelLayout: layout
        )
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames

        if let target = targetPeak {
            let ceil = target
            let kn = ceil * 0.85
            let headroom = ceil - kn

            for c in 0..<chCount {
                guard let dst = buffer.floatChannelData?[c] else { continue }
                let count = min(Int(frames), channels[c].count)
                for i in 0..<count {
                    let v = channels[c][i]
                    let mag = abs(v)
                    if mag <= kn {
                        dst[i] = v
                    } else {
                        let excess = mag - kn
                        let comp = headroom * tanhf(excess / headroom)
                        dst[i] = (v >= 0 ? 1.0 : -1.0) * (kn + comp)
                    }
                }
            }
        } else {
            for c in 0..<chCount {
                guard let dst = buffer.floatChannelData?[c] else { continue }
                let count = min(Int(frames), channels[c].count)
                dst.initialize(from: channels[c], count: count)
            }
        }
        return buffer
    }

    /// High-precision polyphase sinc resampling using AVAudioConverter.
    public static func resample(
        buffer: AVAudioPCMBuffer,
        targetSampleRate: Double = 48000.0
    ) -> AVAudioPCMBuffer {
        guard buffer.format.sampleRate != targetSampleRate else { return buffer }
        guard let targetLayout = buffer.format.channelLayout else { return buffer }

        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            interleaved: false,
            channelLayout: targetLayout
        )

        guard let converter = AVAudioConverter(from: buffer.format, to: targetFormat) else {
            return buffer
        }

        converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue
        let ratio = targetSampleRate / buffer.format.sampleRate
        let targetCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 1024)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: targetCapacity) else {
            return buffer
        }

        var error: NSError?
        var consumed = false
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if !consumed {
                consumed = true
                outStatus.pointee = .haveData
                return buffer
            } else {
                outStatus.pointee = .noDataNow
                return nil
            }
        }

        if let error = error {
            print("[AudioBufferUtils] Resample error: \(error)")
            return buffer
        }
        return outputBuffer
    }
}
