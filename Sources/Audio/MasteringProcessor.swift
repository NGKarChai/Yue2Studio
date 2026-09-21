import Foundation
import Accelerate

/// Second-order IIR section in Direct Form I, using the RBJ cookbook formulas.
public struct Biquad: Sendable {
    public var b0: Double, b1: Double, b2: Double, a1: Double, a2: Double

    /// Butterworth-style high-pass.
    public static func highPass(frequency: Double, sampleRate: Double, q: Double = 0.7071) -> Biquad {
        let w0 = 2.0 * Double.pi * frequency / sampleRate
        let cosW = cos(w0), alpha = sin(w0) / (2.0 * q)
        let a0 = 1.0 + alpha
        return Biquad(
            b0: ((1.0 + cosW) / 2.0) / a0,
            b1: (-(1.0 + cosW)) / a0,
            b2: ((1.0 + cosW) / 2.0) / a0,
            a1: (-2.0 * cosW) / a0,
            a2: (1.0 - alpha) / a0
        )
    }

    /// Butterworth-style low-pass.
    public static func lowPass(frequency: Double, sampleRate: Double, q: Double = 0.7071) -> Biquad {
        let w0 = 2.0 * Double.pi * frequency / sampleRate
        let cosW = cos(w0), alpha = sin(w0) / (2.0 * q)
        let a0 = 1.0 + alpha
        return Biquad(
            b0: ((1.0 - cosW) / 2.0) / a0,
            b1: (1.0 - cosW) / a0,
            b2: ((1.0 - cosW) / 2.0) / a0,
            a1: (-2.0 * cosW) / a0,
            a2: (1.0 - alpha) / a0
        )
    }

    /// Peaking EQ. Negative `gainDB` cuts, positive boosts.
    public static func peaking(frequency: Double, sampleRate: Double, gainDB: Double, q: Double) -> Biquad {
        let a = pow(10.0, gainDB / 40.0)
        let w0 = 2.0 * Double.pi * frequency / sampleRate
        let cosW = cos(w0), alpha = sin(w0) / (2.0 * q)
        let a0 = 1.0 + alpha / a
        return Biquad(
            b0: (1.0 + alpha * a) / a0,
            b1: (-2.0 * cosW) / a0,
            b2: (1.0 - alpha * a) / a0,
            a1: (-2.0 * cosW) / a0,
            a2: (1.0 - alpha / a) / a0
        )
    }

    /// Applies the section in place over `samples`.
    public func process(_ samples: inout [Float]) {
        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
        for i in 0..<samples.count {
            let x0 = Double(samples[i])
            let y0 = b0 * x0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = x0
            y2 = y1; y1 = y0
            samples[i] = Float(y0)
        }
    }
}

/// Corrective mastering for X-Codec output.
///
/// The codec renders at 16 kHz, so there is no content above ~8 kHz and no
/// amount of processing can create any. What the raw output *does* have is a
/// strong low-frequency tilt: measured on real generations, 200 Hz sits some
/// 12-17 dB above the 800-2500 Hz band. That scooped midrange is what makes an
/// otherwise usable mix sound boxy and telephone-like, and unlike the bandwidth
/// limit it is correctable.
///
/// The chain deliberately stops short of the top octave: boosting near the
/// 7.5-8 kHz cliff would amplify codec artifacts rather than musical detail.
public struct MasteringProcessor: Sendable {
    public struct Settings: Sendable {
        public var highPassHz: Double
        public var boxinessHz: Double
        public var boxinessGainDB: Double
        public var bodyHz: Double
        public var bodyGainDB: Double
        public var presenceHz: Double
        public var presenceGainDB: Double

        public init(
            highPassHz: Double = 60.0,
            boxinessHz: Double = 220.0,
            boxinessGainDB: Double = -1.5,
            bodyHz: Double = 1200.0,
            bodyGainDB: Double = 1.0,
            presenceHz: Double = 3200.0,
            presenceGainDB: Double = 2.0
        ) {
            self.highPassHz = highPassHz
            self.boxinessHz = boxinessHz
            self.boxinessGainDB = boxinessGainDB
            self.bodyHz = bodyHz
            self.bodyGainDB = bodyGainDB
            self.presenceHz = presenceHz
            self.presenceGainDB = presenceGainDB
        }
    }

    public let settings: Settings

    public init(settings: Settings = Settings()) {
        self.settings = settings
    }

    /// Builds the chain for `sampleRate`. Bands at or above Nyquist are dropped
    /// rather than wrapped, which would place a filter at a nonsense frequency.
    public func sections(sampleRate: Double) -> [Biquad] {
        let nyquist = sampleRate / 2.0
        var chain: [Biquad] = []

        if settings.highPassHz > 0, settings.highPassHz < nyquist {
            chain.append(.highPass(frequency: settings.highPassHz, sampleRate: sampleRate))
        }
        if settings.boxinessHz < nyquist, settings.boxinessGainDB != 0 {
            chain.append(.peaking(frequency: settings.boxinessHz, sampleRate: sampleRate,
                                  gainDB: settings.boxinessGainDB, q: 1.0))
        }
        if settings.bodyHz < nyquist, settings.bodyGainDB != 0 {
            chain.append(.peaking(frequency: settings.bodyHz, sampleRate: sampleRate,
                                  gainDB: settings.bodyGainDB, q: 0.8))
        }
        // Keep the presence lift clear of the codec's rolloff cliff.
        if settings.presenceHz < nyquist * 0.85, settings.presenceGainDB != 0 {
            chain.append(.peaking(frequency: settings.presenceHz, sampleRate: sampleRate,
                                  gainDB: settings.presenceGainDB, q: 0.9))
        }
        return chain
    }

    /// Processes one channel in place.
    public func process(_ samples: inout [Float], sampleRate: Double) {
        for section in sections(sampleRate: sampleRate) {
            section.process(&samples)
        }
    }
}
