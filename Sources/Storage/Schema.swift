import Foundation
import SQLite3

public struct Schema {
    public static func migrate(database: SQLiteDatabase) throws {
        // App Settings table
        try database.execute(sql: """
            CREATE TABLE IF NOT EXISTS app_settings (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );
        """)

        // Model Registry table
        try database.execute(sql: """
            CREATE TABLE IF NOT EXISTS model_registry (
                id TEXT PRIMARY KEY,
                stage TEXT NOT NULL,
                name TEXT NOT NULL,
                repo_id TEXT NOT NULL,
                local_path TEXT NOT NULL,
                status TEXT NOT NULL,
                size_bytes INTEGER NOT NULL DEFAULT 0,
                sha256 TEXT NOT NULL DEFAULT ''
            );
        """)

        // Generation History table
        try database.execute(sql: """
            CREATE TABLE IF NOT EXISTS generation_history (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                genre_tags TEXT NOT NULL,
                lyrics TEXT NOT NULL,
                temperature REAL NOT NULL,
                top_p REAL NOT NULL,
                cfg_scale REAL NOT NULL,
                max_tokens INTEGER NOT NULL,
                seed INTEGER NOT NULL,
                audio_path TEXT NOT NULL,
                duration_seconds REAL NOT NULL,
                status TEXT NOT NULL,
                created_at TEXT NOT NULL
            );
        """)

        // Genre Presets table
        try database.execute(sql: """
            CREATE TABLE IF NOT EXISTS preset_genres (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                tags TEXT NOT NULL,
                description TEXT NOT NULL
            );
        """)

        // Lyric Templates table
        try database.execute(sql: """
            CREATE TABLE IF NOT EXISTS preset_lyrics (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                lyrics TEXT NOT NULL
            );
        """)

        // Populate initial default presets if empty
        try seedInitialDatabaseRecords(database: database)
        try ensureYuE2RegistryEntries(database: database)
        try purgeLegacyModelRegistryEntries(database: database)
    }

    private static func purgeLegacyModelRegistryEntries(database: SQLiteDatabase) throws {
        try database.execute(sql: """
            DELETE FROM model_registry WHERE id IN ('stage1-7b-en', 'stage1-7b-zh', 'stage2-1b', 'xcodec');
        """)
    }

    private static func seedInitialDatabaseRecords(database: SQLiteDatabase) throws {
        let stmt = try database.prepare(sql: "SELECT COUNT(*) FROM preset_genres;")
        defer { stmt.reset() }
        var genreCount: Int64 = 0
        if stmt.step() == SQLITE_ROW {
            genreCount = stmt.columnInt64(index: 0)
        }

        if genreCount == 0 {
            try database.transaction {
                let insertGenre = try database.prepare(sql: """
                    INSERT INTO preset_genres (id, name, tags, description) VALUES (?, ?, ?, ?);
                """)
                defer { insertGenre.reset() }

                let initialGenres: [(String, String, String, String)] = [
                    ("g1", "Modern Pop / Melodic", "female vocal, modern pop, uplifting melody, synth chords, punchy drums, 120 bpm", "Upbeat contemporary pop with female vocals"),
                    ("g2", "Acoustic Ballad", "acoustic guitar, warm piano, soft male vocal, emotional, intimate reverb, 75 bpm", "Gentle acoustic guitar ballad"),
                    ("g3", "Synthwave / Cyberpunk", "analog synthesizer, 80s drum machine, driving bassline, vocoder vocal, retro wave, 115 bpm", "Retro-futuristic electronic synthwave"),
                    ("g4", "Cinematic Orchestral", "grand symphonic orchestra, soaring strings, epic brass, choral backing, dramatic, 90 bpm", "Epic cinematic soundtrack theme"),
                    ("g5", "R&B / Soul Groove", "smooth electric piano, funky bassline, soul vocal, laid back groove, rimshot, 88 bpm", "Smooth mellow R&B groove"),
                    ("g6", "Pure Instrumental / Piano", "instrumental, solo piano, gentle acoustic, emotional melody, cinematic, warm reverb, no vocals, 85 bpm", "Pure acoustic piano instrumental background music"),
                    ("g7", "Lo-Fi Instrumental Beats", "instrumental, lo-fi hip hop, chill beats, rhodes piano, vinyl crackle, mellow bass, no vocals, 80 bpm", "Chill instrumental lo-fi background beats")
                ]

                for item in initialGenres {
                    insertGenre.reset()
                    try insertGenre.bind(index: 1, value: item.0)
                    try insertGenre.bind(index: 2, value: item.1)
                    try insertGenre.bind(index: 3, value: item.2)
                    try insertGenre.bind(index: 4, value: item.3)
                    insertGenre.step()
                }

                let insertLyrics = try database.prepare(sql: """
                    INSERT INTO preset_lyrics (id, title, lyrics) VALUES (?, ?, ?);
                """)
                defer { insertLyrics.reset() }

                let initialLyrics: [(String, String, String)] = [
                    (
                        "l1",
                        "Morning Light",
                        """
                        [verse]
                        Sunlight creeping through the blind
                        Leaving yesterday behind
                        Step into another day
                        Finding words I want to say

                        [chorus]
                        Hear the music rising high
                        Painting colors in the sky
                        We are singing through the rain
                        """
                    ),
                    (
                        "l3",
                        "Pure Instrumental Arrangement",
                        """
                        [intro]
                        [inst]
                        [solo]
                        [inst]
                        [outro]
                        """
                    )
                ]

                for item in initialLyrics {
                    insertLyrics.reset()
                    try insertLyrics.bind(index: 1, value: item.0)
                    try insertLyrics.bind(index: 2, value: item.1)
                    try insertLyrics.bind(index: 3, value: item.2)
                    insertLyrics.step()
                }

                // Initial model registry metadata
                let insertModel = try database.prepare(sql: """
                    INSERT OR IGNORE INTO model_registry (id, stage, name, repo_id, local_path, status, size_bytes, sha256)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?);
                """)
                defer { insertModel.reset() }

                let initialModels: [(String, String, String, String, String, String, Int64, String)] = [
                    ("yue2-3b", "yue2", "YuE2-3B Flow Matching Generator", "vanch007/mlx-Yue2-3B", "Models/yue2-3b", "not_downloaded", 2800000000, ""),
                    ("yue2-vae", "yue2_vae", "YuE2 48kHz Oobleck VAE Decoder", "m-a-p/YuE2-Vae", "Models/yue2-vae", "not_downloaded", 600000000, "")
                ]

                for item in initialModels {
                    insertModel.reset()
                    try insertModel.bind(index: 1, value: item.0)
                    try insertModel.bind(index: 2, value: item.1)
                    try insertModel.bind(index: 3, value: item.2)
                    try insertModel.bind(index: 4, value: item.3)
                    try insertModel.bind(index: 5, value: item.4)
                    try insertModel.bind(index: 6, value: item.5)
                    try insertModel.bind(index: 7, value: item.6)
                    try insertModel.bind(index: 8, value: item.7)
                    insertModel.step()
                }
            }
        }
    }

    private static func ensureYuE2RegistryEntries(database: SQLiteDatabase) throws {
        let insertModel = try database.prepare(sql: """
            INSERT OR IGNORE INTO model_registry (id, stage, name, repo_id, local_path, status, size_bytes, sha256)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        """)
        defer { insertModel.reset() }

        let yue2Models: [(String, String, String, String, String, String, Int64, String)] = [
            ("yue2-3b", "yue2", "YuE2-3B Flow Matching Generator", "vanch007/mlx-Yue2-3B", "Models/yue2-3b", "not_downloaded", 2800000000, ""),
            ("yue2-vae", "yue2_vae", "YuE2 48kHz Oobleck VAE Decoder", "m-a-p/YuE2-Vae", "Models/yue2-vae", "not_downloaded", 600000000, "")
        ]

        for item in yue2Models {
            insertModel.reset()
            try insertModel.bind(index: 1, value: item.0)
            try insertModel.bind(index: 2, value: item.1)
            try insertModel.bind(index: 3, value: item.2)
            try insertModel.bind(index: 4, value: item.3)
            try insertModel.bind(index: 5, value: item.4)
            try insertModel.bind(index: 6, value: item.5)
            try insertModel.bind(index: 7, value: item.6)
            try insertModel.bind(index: 8, value: item.7)
            insertModel.step()
        }
    }
}
