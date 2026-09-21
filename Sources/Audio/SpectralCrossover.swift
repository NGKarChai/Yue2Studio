import Foundation
import Accelerate

/// Combines the two decode paths the way official YuE v1 finishes a render.
///
/// X-Codec's 16 kHz acoustic decoder is trustworthy in the low band but has
/// nothing above 8 kHz. The Vocos upsampler synthesizes a full 44.1 kHz band
/// from the same quantized features, but its low end is a reconstruction rather
/// than the codec's own output. YuE keeps the best of each: lows come from
/// X-Codec (level-matched to the Vocos render so the seam is inaudible), highs
/// come from Vocos.
///
/// This mirrors `replace_low_freq_with_energy_matched` in YuE's
/// post_process_audio.py, which uses a 5500 Hz crossover.
public struct SpectralCrossover: Sendable {
    public let cutoffHz: Double

    public init(cutoffHz: Double = 5500.0) {
        self.cutoffHz = cutoffHz
    }

    /// - Parameters:
    ///   - low: the 16 kHz X-Codec render, already resampled to `sampleRate`
    ///   - high: the Vocos render at `sampleRate`
    /// - Returns: combined signal, truncated to the shorter of the two
    public func combine(low: [Float], high: [Float], sampleRate: Double) -> [Float] {
        let n = min(low.count, high.count)
        guard n > 0 else { return [] }

        var lowBand = Array(low[0..<n])
        var highRef = Array(high[0..<n])
        var highBand = Array(high[0..<n])

        let lp = Biquad.lowPass(frequency: cutoffHz, sampleRate: sampleRate)
        let hp = Biquad.highPass(frequency: cutoffHz, sampleRate: sampleRate)

        // Isolate each contribution.
        lp.process(&lowBand)   // X-Codec lows
        lp.process(&highRef)   // Vocos lows, used only to measure level
        hp.process(&highBand)  // Vocos highs

        // Match energies across the crossover boundary without ever attenuating
        // the core X-Codec low-band foundation (bass, drums, vocal body, chords).
        let eps: Double = 1e-10
        let aRMS = rms(lowBand) + eps
        let bRMS = rms(highRef) + eps

        let lowScale: Float
        let highScale: Float

        if aRMS < 1e-4 && bRMS < 1e-4 {
            lowScale = 1.0
            highScale = 1.0
        } else if bRMS > aRMS {
            // Vocoder is louder than codec: bring codec lows up to meet vocoder
            lowScale = Float(min(10.0, max(1.0, bRMS / aRMS)))
            highScale = 1.0
        } else {
            // Codec has full healthy energy: preserve codec lows 100% and lift
            // vocoder highs to seamlessly blend at the crossover boundary.
            lowScale = 1.0
            highScale = Float(min(4.0, max(1.0, aRMS / bRMS)))
        }

        var out = [Float](repeating: 0, count: n)
        var sLow = lowScale
        vDSP_vsmul(lowBand, 1, &sLow, &out, 1, vDSP_Length(n))

        var scaledHigh = [Float](repeating: 0, count: n)
        var sHigh = highScale
        vDSP_vsmul(highBand, 1, &sHigh, &scaledHigh, 1, vDSP_Length(n))

        vDSP_vadd(out, 1, scaledHigh, 1, &out, 1, vDSP_Length(n))
        return out
    }

    private func rms(_ x: [Float]) -> Double {
        guard !x.isEmpty else { return 0 }
        var acc: Float = 0
        vDSP_measqv(x, 1, &acc, vDSP_Length(x.count))
        return sqrt(Double(acc))
    }
}
