import Foundation

public enum PipelinePhase: String, Sendable {
    case idle = "Idle"
    case loadingModels = "Loading Models"
    case stage1Generating = "AR Musical Generation"
    case stage2Refining = "Flow Matching Refinement"
    case decodingAudio = "48kHz VAE Neural Synthesis"
    case complete = "Completed"
    case failed = "Failed"
}

public struct PipelineProgress: Sendable {
    public let phase: PipelinePhase
    public let progressFraction: Double
    public let currentStep: Int
    public let totalSteps: Int
    public let speed: Double
    public let statusMessage: String

    public init(
        phase: PipelinePhase = .idle,
        progressFraction: Double = 0.0,
        currentStep: Int = 0,
        totalSteps: Int = 0,
        speed: Double = 0.0,
        statusMessage: String = ""
    ) {
        self.phase = phase
        self.progressFraction = progressFraction
        self.currentStep = currentStep
        self.totalSteps = totalSteps
        self.speed = speed
        self.statusMessage = statusMessage
    }
}
