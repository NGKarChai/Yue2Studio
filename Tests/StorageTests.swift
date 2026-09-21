import XCTest
@testable import Yue2Studio

final class StorageTests: XCTestCase {
    var tempDBPath: String!
    var database: SQLiteDatabase!

    override func setUpWithError() throws {
        let tempDir = NSTemporaryDirectory()
        tempDBPath = (tempDir as NSString).appendingPathComponent("test_\(UUID().uuidString).sqlite3")
        database = try SQLiteDatabase(path: tempDBPath)
        try Schema.migrate(database: database)
    }

    override func tearDownWithError() throws {
        database = nil
        try? FileManager.default.removeItem(atPath: tempDBPath)
    }

    func testSettingsPersistence() throws {
        let repo = SettingsRepository(database: database)
        repo.set(key: .modelDirectoryPath, value: "/custom/models/path")
        XCTAssertEqual(repo.get(key: .modelDirectoryPath), "/custom/models/path")

        repo.set(key: .quantizationPrecision, value: "8-bit")
        XCTAssertEqual(repo.get(key: .quantizationPrecision), "8-bit")
    }

    func testGenerationRecordPersistence() throws {
        let repo = GenerationRepository(database: database)
        let record = GenerationRecord(
            title: "Test Song",
            genreTags: "pop, synth",
            lyrics: "[verse]\nHello world",
            temperature: 0.85,
            topP: 0.90,
            cfgScale: 1.5,
            maxTokens: 500,
            seed: 42,
            audioPath: "/path/to/audio.wav",
            durationSeconds: 15.0
        )

        try repo.insert(record: record)
        let all = repo.getAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.title, "Test Song")
        XCTAssertEqual(all.first?.seed, 42)

        repo.delete(id: record.id)
        XCTAssertEqual(repo.getAll().count, 0)
    }

    func testPresetLoading() throws {
        let presetRepo = PresetRepository(database: database)
        let genres = presetRepo.getGenres()
        let lyrics = presetRepo.getLyrics()

        XCTAssertFalse(genres.isEmpty, "Initial genres should be seeded from database")
        XCTAssertFalse(lyrics.isEmpty, "Initial lyrics should be seeded from database")
    }
}
