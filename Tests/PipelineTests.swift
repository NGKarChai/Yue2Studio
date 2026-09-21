import XCTest
import MLX
import MLXNN
import AVFoundation
import Accelerate
@testable import Yue2Studio

final class PipelineTests: XCTestCase {
    override func setUpWithError() throws {
        Device.setDefault(device: Device(.gpu))
    }

    func testPromptFormatter() {
        let tags = "pop, female vocal"
        let lyrics = "[verse]\nSinging in the morning light\n\n[chorus]\nEchoes in the night"
        let formatted = PromptFormatter.format(genreTags: tags, lyrics: lyrics)

        XCTAssertTrue(formatted.contains("[Genre] English, pop, female vocal"))
        XCTAssertTrue(formatted.contains("Generate music from the given lyrics segment by segment."))
        XCTAssertTrue(formatted.contains("[start_of_segment]"))
        XCTAssertTrue(formatted.contains("[verse]\nSinging in the morning light"))

        let sections = PromptFormatter.extractSections(from: lyrics)
        XCTAssertEqual(sections, ["verse", "chorus"])

        let segments = PromptFormatter.splitIntoSegments(lyrics: lyrics)
        XCTAssertEqual(segments.count, 2)
    }

    func testSampler() {
        let logits = MLXArray([Float]([1.0, 2.0, 5.0, 0.5]))
        let params = SamplingParameters(temperature: 0.8, topP: 0.95, seed: 123)
        let sampled = Sampler.sample(logits: logits, params: params)
        XCTAssertTrue(sampled >= 0 && sampled < 4)
    }

    func testSamplerTopPAccuracy() {
        let original = MLXArray([Float]([1.0, 10.0, 3.0, 8.0, 2.0]))
        let probs = MLX.softmax(original, axis: -1)
        eval(probs)

        let sortedIndices = MLX.argSort(-probs, axis: -1)
        eval(sortedIndices)

        let sortedProbs = probs[sortedIndices]
        eval(sortedProbs)

        let cumProbs = MLX.cumsum(sortedProbs, axis: -1)
        eval(cumProbs)

        let maskCondition = cumProbs .> 0.9
        eval(maskCondition)

        let shiftedMask = MLX.concatenated([MLXArray([false]), maskCondition[0..<4]], axis: -1)
        eval(shiftedMask)

        let filteredSorted = MLX.where(shiftedMask, MLXArray(-Float.infinity), original[sortedIndices])
        eval(filteredSorted)

        let restoreIndices = MLX.argSort(sortedIndices, axis: -1)
        eval(restoreIndices)

        let restored = filteredSorted[restoreIndices]
        eval(restored)

        // Index 1 (value 10.0) and index 3 (value 8.0) must NOT be -infinity
        XCTAssertFalse(restored[1].item(Float.self).isInfinite, "Token with highest prob should survive top-p")
        XCTAssertFalse(restored[3].item(Float.self).isInfinite, "Token with 2nd highest prob should survive top-p")
    }

    func testTopPSamplingAndWindowedPenalty() {
        let logits = MLXArray([Float]([5.0, 2.0, 1.0, 0.1]))
        let past = [0, 0, 0, 0] // token 0 repeated
        let params = SamplingParameters(
            temperature: 0.7,
            topP: 0.9,
            repetitionPenalty: 1.5,
            seed: 42
        )
        let sampled = Sampler.sample(logits: logits, params: params, pastTokens: past)
        XCTAssertTrue(sampled >= 0 && sampled < 4)
    }

    func testAudioBufferUtilsMakeBufferAndResample() {
        let sampleRate: Double = 24000.0
        let frameCount = 24000 // 1 second
        var left = [Float](repeating: 0, count: frameCount)
        var right = [Float](repeating: 0, count: frameCount)
        for i in 0..<frameCount {
            let t = Float(i) / Float(sampleRate)
            left[i] = sin(2.0 * .pi * 440.0 * t) * 0.5
            right[i] = sin(2.0 * .pi * 880.0 * t) * 0.5
        }

        guard let buffer = AudioBufferUtils.makeBuffer(channels: [left, right], sampleRate: sampleRate) else {
            XCTFail("makeBuffer should succeed")
            return
        }
        XCTAssertEqual(buffer.format.sampleRate, 24000.0)
        XCTAssertEqual(buffer.format.channelCount, 2)
        XCTAssertEqual(buffer.frameLength, 24000)

        let extracted = AudioBufferUtils.channelArrays(from: buffer)
        XCTAssertEqual(extracted.count, 2)
        XCTAssertEqual(extracted[0].count, 24000)

        let resampled = AudioBufferUtils.resample(buffer: buffer, targetSampleRate: 48000.0)
        XCTAssertEqual(resampled.format.sampleRate, 48000.0)
        XCTAssertEqual(resampled.format.channelCount, 2)
        XCTAssertGreaterThan(resampled.frameLength, 47000)
    }

    func testMasteringLimiterLoudnessAndPeakCatching() {
        var limiter = MasteringLimiter(settings: MasteringLimiter.Settings(
            targetRMS: 0.18,
            ceiling: 0.891,
            knee: 0.72
        ))

        // Signal with peaks exceeding 1.0
        let n = 48000
        var left = [Float](repeating: 0, count: n)
        var right = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Float(i) / 48000.0
            left[i] = sin(2.0 * .pi * 440.0 * t) * 1.5
            right[i] = cos(2.0 * .pi * 440.0 * t) * 1.5
        }
        var channels = [left, right]
        limiter.process(&channels)

        for ch in channels {
            for s in ch {
                XCTAssertLessThanOrEqual(abs(s), 0.895, "Peak limiter must strictly clamp to ceiling")
            }
        }
    }
}
