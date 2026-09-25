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

    /// Suppresses center-panned vocals while strictly preserving mono bass/sub-bass (< 160 Hz)
    /// and high-frequency stereo shimmer (> 7000 Hz).
    ///
    /// Vocal formants in YuE2 reside almost entirely in the center mid-range (160 Hz - 7000 Hz).
    /// By extracting the stereo side signal and attenuating the center mid channel,
    /// vocals are attenuated by > 28-33 dB without sacrificing low-end kick or wide instruments.
    public static func suppressVocals(
        buffer: AVAudioPCMBuffer,
        vocalCutStrength: Float = 0.98,
        bassCrossoverHz: Double = 160.0,
        highCrossoverHz: Double = 7000.0
    ) -> AVAudioPCMBuffer {
        let chCount = Int(buffer.format.channelCount)
        guard chCount >= 2, let leftData = buffer.floatChannelData?[0], let rightData = buffer.floatChannelData?[1] else {
            return buffer
        }

        let n = Int(buffer.frameLength)
        guard n > 0 else { return buffer }

        let sampleRate = buffer.format.sampleRate
        let leftSamples = Array(UnsafeBufferPointer(start: leftData, count: n))
        let rightSamples = Array(UnsafeBufferPointer(start: rightData, count: n))

        // 1. Isolate Mono Bass (< bassCrossoverHz)
        var lpLeft = leftSamples
        var lpRight = rightSamples
        let lpBass = Biquad.lowPass(frequency: bassCrossoverHz, sampleRate: sampleRate, q: 0.7071)
        var lpFilterLeft = lpBass
        var lpFilterRight = lpBass
        lpFilterLeft.process(&lpLeft)
        lpFilterRight.process(&lpRight)

        // Bass is kept mono and punchy
        var bass = [Float](repeating: 0, count: n)
        for i in 0..<n {
            bass[i] = 0.5 * (lpLeft[i] + lpRight[i])
        }

        // 2. High frequency shimmer (> highCrossoverHz)
        let hpHigh = Biquad.highPass(frequency: highCrossoverHz, sampleRate: sampleRate, q: 0.7071)
        var hpFilterLeft = hpHigh
        var hpFilterRight = hpHigh
        var hpLeft = leftSamples
        var hpRight = rightSamples
        hpFilterLeft.process(&hpLeft)
        hpFilterRight.process(&hpRight)

        // 3. Midrange Vocal Band: remove bass and high
        var vocalLeft = [Float](repeating: 0, count: n)
        var vocalRight = [Float](repeating: 0, count: n)
        for i in 0..<n {
            vocalLeft[i] = leftSamples[i] - lpLeft[i] - hpLeft[i]
            vocalRight[i] = rightSamples[i] - lpRight[i] - hpRight[i]
        }

        // 4. Center-channel suppression in vocal band
        // Mid M = 0.5 * (L + R)
        // L_out = (L - vocalCutStrength * M) * sideBoost
        // R_out = (R - vocalCutStrength * M) * sideBoost
        var outLeft = [Float](repeating: 0, count: n)
        var outRight = [Float](repeating: 0, count: n)

        let cut = min(1.0, max(0.0, vocalCutStrength))
        let sideBoost: Float = 1.15 // Gentle makeup gain for side stereo instruments

        for i in 0..<n {
            let vl = vocalLeft[i]
            let vr = vocalRight[i]
            let m = 0.5 * (vl + vr)
            let cleanVL = (vl - cut * m) * sideBoost
            let cleanVR = (vr - cut * m) * sideBoost

            outLeft[i] = bass[i] + cleanVL + hpLeft[i]
            outRight[i] = bass[i] + cleanVR + hpRight[i]
        }

        // Build output buffer with soft peak limiting
        if let outBuffer = makeBuffer(channels: [outLeft, outRight], sampleRate: sampleRate, targetPeak: 0.95) {
            return outBuffer
        }
        return buffer
    }
}
