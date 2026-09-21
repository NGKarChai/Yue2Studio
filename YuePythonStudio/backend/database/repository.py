import json
from typing import List, Optional, Dict, Any
from datetime import datetime
from .db import DatabaseManager
from .models import AppSetting, PresetGenre, PresetLyric, GenerationRecord, ModelRegistryEntry

class SettingsRepository:
    def __init__(self, db: DatabaseManager):
        self.db = db

    def get_all(self) -> Dict[str, str]:
        with self.db.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT key, value FROM app_settings")
            return {row["key"]: row["value"].strip("'\"") for row in cursor.fetchall()}

    def get(self, key: str, default: Optional[str] = None) -> Optional[str]:
        with self.db.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT value FROM app_settings WHERE key = ?", (key,))
            row = cursor.fetchone()
            if row:
                return row["value"].strip("'\"")
            return default

    def set(self, key: str, value: str):
        now = datetime.utcnow().isoformat()
        with self.db.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("""
            INSERT INTO app_settings (key, value, updated_at)
            VALUES (?, ?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
            """, (key, str(value), now))

    def update_multiple(self, settings_dict: Dict[str, Any]):
        for k, v in settings_dict.items():
            self.set(k, str(v))


class PresetsRepository:
    def __init__(self, db: DatabaseManager):
        self.db = db

    def get_genres(self) -> List[PresetGenre]:
        with self.db.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT id, name, tags, description FROM preset_genres ORDER BY id ASC")
            return [PresetGenre(id=r["id"], name=r["name"], tags=r["tags"], description=r["description"]) for r in cursor.fetchall()]

    def get_lyrics(self) -> List[PresetLyric]:
        with self.db.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT id, title, lyrics FROM preset_lyrics ORDER BY id ASC")
            return [PresetLyric(id=r["id"], title=r["title"], lyrics=r["lyrics"]) for r in cursor.fetchall()]

    def add_genre(self, id: str, name: str, tags: str, description: str):
        with self.db.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("INSERT OR REPLACE INTO preset_genres (id, name, tags, description) VALUES (?, ?, ?, ?)",
                           (id, name, tags, description))

    def add_lyric(self, id: str, title: str, lyrics: str):
        with self.db.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("INSERT OR REPLACE INTO preset_lyrics (id, title, lyrics) VALUES (?, ?, ?)",
                           (id, title, lyrics))


class HistoryRepository:
    def __init__(self, db: DatabaseManager):
        self.db = db

    def list_all(self, limit: int = 50) -> List[GenerationRecord]:
        with self.db.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("""
            SELECT id, title, genre_tags, lyrics, temperature, top_p, cfg_scale, max_tokens, seed, audio_path, duration_seconds, status, created_at
            FROM generation_history
            ORDER BY created_at DESC
            LIMIT ?
            """, (limit,))
            return [
                GenerationRecord(
                    id=r["id"],
                    title=r["title"],
                    genre_tags=r["genre_tags"],
                    lyrics=r["lyrics"],
                    temperature=float(r["temperature"]),
                    top_p=float(r["top_p"]),
                    cfg_scale=float(r["cfg_scale"]),
                    max_tokens=int(r["max_tokens"]),
                    seed=int(r["seed"]),
                    audio_path=r["audio_path"],
                    duration_seconds=float(r["duration_seconds"]),
                    status=r["status"],
                    created_at=r["created_at"]
                )
                for r in cursor.fetchall()
            ]

    def get_by_id(self, gen_id: str) -> Optional[GenerationRecord]:
        with self.db.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT * FROM generation_history WHERE id = ?", (gen_id,))
            r = cursor.fetchone()
            if not r:
                return None
            return GenerationRecord(
                id=r["id"],
                title=r["title"],
                genre_tags=r["genre_tags"],
                lyrics=r["lyrics"],
                temperature=float(r["temperature"]),
                top_p=float(r["top_p"]),
                cfg_scale=float(r["cfg_scale"]),
                max_tokens=int(r["max_tokens"]),
                seed=int(r["seed"]),
                audio_path=r["audio_path"],
                duration_seconds=float(r["duration_seconds"]),
                status=r["status"],
                created_at=r["created_at"]
            )

    def add_record(self, record: GenerationRecord):
        with self.db.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("""
            INSERT OR REPLACE INTO generation_history
            (id, title, genre_tags, lyrics, temperature, top_p, cfg_scale, max_tokens, seed, audio_path, duration_seconds, status, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                record.id, record.title, record.genre_tags, record.lyrics,
                record.temperature, record.top_p, record.cfg_scale, record.max_tokens,
                record.seed, record.audio_path, record.duration_seconds, record.status, record.created_at
            ))

    def update_status(self, gen_id: str, status: str, audio_path: Optional[str] = None, duration_seconds: Optional[float] = None):
        with self.db.get_connection() as conn:
            cursor = conn.cursor()
            if audio_path is not None and duration_seconds is not None:
                cursor.execute("""
                UPDATE generation_history
                SET status = ?, audio_path = ?, duration_seconds = ?
                WHERE id = ?
                """, (status, audio_path, duration_seconds, gen_id))
            else:
                cursor.execute("""
                UPDATE generation_history
                SET status = ?
                WHERE id = ?
                """, (status, gen_id))


class ModelRegistryRepository:
    def __init__(self, db: DatabaseManager):
        self.db = db

    def list_all(self) -> List[ModelRegistryEntry]:
        with self.db.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT id, stage, name, repo_id, local_path, status, size_bytes, sha256 FROM model_registry")
            return [
                ModelRegistryEntry(
                    id=r["id"],
                    stage=r["stage"],
                    name=r["name"],
                    repo_id=r["repo_id"],
                    local_path=r["local_path"],
                    status=r["status"],
                    size_bytes=int(r["size_bytes"]),
                    sha256=r["sha256"]
                )
                for r in cursor.fetchall()
            ]

    def register(self, entry: ModelRegistryEntry):
        with self.db.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("""
            INSERT OR REPLACE INTO model_registry
            (id, stage, name, repo_id, local_path, status, size_bytes, sha256)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """, (entry.id, entry.stage, entry.name, entry.repo_id, entry.local_path, entry.status, entry.size_bytes, entry.sha256))
