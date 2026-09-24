import Foundation
import SQLite3

public final class SettingsRepository: Sendable {
    private let db: SQLiteDatabase

    public enum Key: String, CaseIterable {
        case modelDirectoryPath = "model_directory_path"
        case quantizationPrecision = "quantization_precision"
        case defaultTemperature = "default_temperature"
        case defaultTopP = "default_top_p"
        case defaultCFGScale = "default_cfg_scale"
        case defaultMaxTokens = "default_max_tokens"
        case autoUnloadStage1 = "auto_unload_stage1"
        case audioOutputSampleRate = "audio_output_sample_rate"
        case stage2Quality = "stage2_quality"
        case planningMode = "planning_mode"
        case referenceMode = "reference_mode"
        case keyShiftSemitones = "key_shift_semitones"
        case masteringEnabled = "mastering_enabled"
        case upsampleEnabled = "upsample_enabled"
        case levelingEnabled = "leveling_enabled"
        case masteringTargetRMS = "mastering_target_rms"
        case masteringCeilingDB = "mastering_ceiling_db"
        case playerMonitoringVolume = "player_monitoring_volume"
        case engineType = "engine_type"
        case yue2ModelDirectory = "yue2_model_directory"
        case yue2VAEDirectory = "yue2_vae_directory"
        case yue2FlowSteps = "yue2_flow_steps"
        case yue2CfgScale = "yue2_cfg_scale"
        case isInstrumentalOnly = "is_instrumental_only"
    }

    public init(database: SQLiteDatabase) {
        self.db = database
        ensureDefaults()
    }

    private func ensureDefaults() {
        let defaults: [Key: String] = [
            .modelDirectoryPath: "Models",
            .quantizationPrecision: "4-bit",
            .defaultTemperature: "0.9",
            .defaultTopP: "0.95",
            .defaultCFGScale: "1.5",
            .defaultMaxTokens: "1600",
            .autoUnloadStage1: "true",
            .audioOutputSampleRate: "44100",
            .stage2Quality: "full",
            .planningMode: "melody_cover",
            .referenceMode: "melody_only",
            .keyShiftSemitones: "0",
            .masteringEnabled: "true",
            .upsampleEnabled: "true",
            .levelingEnabled: "true",
            .masteringTargetRMS: "0.18",
            .masteringCeilingDB: "-1.0",
            .playerMonitoringVolume: "1.0",
            .engineType: "yue1",
            .yue2ModelDirectory: "Models/yue2-3b",
            .yue2VAEDirectory: "Models/yue2-vae",
            .yue2FlowSteps: "32",
            .yue2CfgScale: "1.0",
            .isInstrumentalOnly: "false"
        ]

        for (key, defaultValue) in defaults {
            if let existing = get(key: key) {
                // If max_tokens was left at the legacy 600 default, upgrade it to 1600
                if key == .defaultMaxTokens && existing == "600" {
                    set(key: key, value: defaultValue)
                }
            } else {
                set(key: key, value: defaultValue)
            }
        }
    }

    public func get(key: Key) -> String? {
        do {
            let stmt = try db.prepare(sql: "SELECT value FROM app_settings WHERE key = ?;")
            defer { stmt.reset() }
            try stmt.bind(index: 1, value: key.rawValue)
            if stmt.step() == SQLITE_ROW {
                return stmt.columnString(index: 0)
            }
        } catch {
            print("[SettingsRepository] Error fetching \(key): \(error)")
        }
        return nil
    }

    public func set(key: Key, value: String) {
        do {
            let stmt = try db.prepare(sql: """
                INSERT INTO app_settings (key, value, updated_at) VALUES (?, ?, ?)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at;
            """)
            defer { stmt.reset() }
            let now = ISO8601DateFormatter().string(from: Date())
            try stmt.bind(index: 1, value: key.rawValue)
            try stmt.bind(index: 2, value: value)
            try stmt.bind(index: 3, value: now)
            stmt.step()
        } catch {
            print("[SettingsRepository] Error saving \(key): \(error)")
        }
    }
}
