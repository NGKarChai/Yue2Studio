import XCTest
@testable import Yue2Studio

final class ModelSelectionTests: XCTestCase {
    private var root: URL!

    override func setUp() {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("yue-modelsel-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    private func makeCheckpoint(_ name: String, language: String? = nil) {
        let dir = root.appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: dir.appendingPathComponent("model-00001.safetensors").path,
                                       contents: Data([0]))
        if let language {
            try? language.write(to: dir.appendingPathComponent("language.txt"),
                                atomically: true, encoding: .utf8)
        }
    }

    /// Chinese lyrics must pick the Chinese checkpoint when it is installed.
    func testPrefersMatchingLanguageCheckpoint() {
        makeCheckpoint("stage1", language: "en")
        makeCheckpoint("stage1-zh")
        let (dir, lang) = YuEPipeline.selectStage1Directory(modelsDir: root, lyricLanguage: "zh")
        XCTAssertEqual(dir.lastPathComponent, "stage1-zh")
        XCTAssertEqual(lang, "zh")
    }

    /// Without the matching model we must fall back AND report the real language,
    /// so the caller can warn instead of silently producing wrong-language vocals.
    func testFallsBackAndReportsActualLanguage() {
        makeCheckpoint("stage1", language: "en")
        let (dir, lang) = YuEPipeline.selectStage1Directory(modelsDir: root, lyricLanguage: "zh")
        XCTAssertEqual(dir.lastPathComponent, "stage1")
        XCTAssertEqual(lang, "en", "must report the model's language, not the lyrics'")
    }

    /// A directory with no weights in it is not a usable checkpoint.
    func testIgnoresEmptyLanguageDirectory() {
        makeCheckpoint("stage1", language: "en")
        try? FileManager.default.createDirectory(
            at: root.appendingPathComponent("stage1-zh"), withIntermediateDirectories: true)
        let (dir, lang) = YuEPipeline.selectStage1Directory(modelsDir: root, lyricLanguage: "zh")
        XCTAssertEqual(dir.lastPathComponent, "stage1", "an empty folder must not be selected")
        XCTAssertEqual(lang, "en")
    }

    /// The genre prefix must not promise a language the loaded model cannot sing.
    func testGenreTagsDoNotClaimUnsupportedLanguage() {
        let zhLyrics = "在你回家的路口\n那顆期待的大樹"
        let withEnModel = PromptFormatter.enrichGenreTags(
            genreTags: "acoustic pop, guitar", lyrics: zhLyrics, modelLanguage: "en")
        XCTAssertFalse(withEnModel.lowercased().contains("mandarin"),
                       "English model must not be told to sing Mandarin: \(withEnModel)")

        let withZhModel = PromptFormatter.enrichGenreTags(
            genreTags: "acoustic pop, guitar", lyrics: zhLyrics, modelLanguage: "zh")
        XCTAssertTrue(withZhModel.lowercased().contains("mandarin"),
                      "Chinese model should get the Mandarin hint: \(withZhModel)")
    }
}
