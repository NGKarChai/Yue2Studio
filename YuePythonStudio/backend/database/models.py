from dataclasses import dataclass, field
from typing import Optional, List, Dict, Any
from datetime import datetime

@dataclass
class AppSetting:
    key: str
    value: str
    updated_at: str = field(default_factory=lambda: datetime.utcnow().isoformat())

@dataclass
class ModelRegistryEntry:
    id: str
    stage: str
    name: str
    repo_id: str
    local_path: str
    status: str
    size_bytes: int = 0
    sha256: str = ""

@dataclass
class GenerationRecord:
    id: str
    title: str
    genre_tags: str
    lyrics: str
    temperature: float
    top_p: float
    cfg_scale: float
    max_tokens: int
    seed: int
    audio_path: str
    duration_seconds: float
    status: str
    created_at: str = field(default_factory=lambda: datetime.utcnow().isoformat())

@dataclass
class PresetGenre:
    id: str
    name: str
    tags: str
    description: str

@dataclass
class PresetLyric:
    id: str
    title: str
    lyrics: str
