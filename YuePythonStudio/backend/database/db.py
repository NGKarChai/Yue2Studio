import sqlite3
import os
from pathlib import Path
from contextlib import contextmanager
from typing import Generator

DEFAULT_DB_PATH = Path(__file__).resolve().parent.parent.parent.parent / "storage.sqlite3"

class DatabaseManager:
    def __init__(self, db_path: Path = DEFAULT_DB_PATH):
        self.db_path = Path(db_path)
        self._ensure_schema()

    @contextmanager
    def get_connection(self) -> Generator[sqlite3.Connection, None, None]:
        conn = sqlite3.connect(str(self.db_path), timeout=30.0)
        conn.row_factory = sqlite3.Row
        try:
            yield conn
            conn.commit()
        except Exception:
            conn.rollback()
            raise
        finally:
            conn.close()

    def _ensure_schema(self):
        with self.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("""
            CREATE TABLE IF NOT EXISTS app_settings (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );
            """)
            cursor.execute("""
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
            cursor.execute("""
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
            cursor.execute("""
            CREATE TABLE IF NOT EXISTS preset_genres (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                tags TEXT NOT NULL,
                description TEXT NOT NULL
            );
            """)
            cursor.execute("""
            CREATE TABLE IF NOT EXISTS preset_lyrics (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                lyrics TEXT NOT NULL
            );
            """)
