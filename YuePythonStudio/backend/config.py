from pathlib import Path
from typing import Dict, Any, Optional
from .database.db import DatabaseManager, DEFAULT_DB_PATH
from .database.repository import SettingsRepository

class StudioConfig:
    def __init__(self, db_path: Optional[Path] = None):
        self.db_manager = DatabaseManager(db_path or DEFAULT_DB_PATH)
        self.settings_repo = SettingsRepository(self.db_manager)

    @property
    def models_dir(self) -> Path:
        val = self.settings_repo.get("model_directory_path")
        if val and Path(val).exists():
            return Path(val)
        # Fallback to parent Models dir
        parent_models = Path(__file__).resolve().parent.parent.parent / "Models"
        if parent_models.exists():
            return parent_models
        return Path("Models").resolve()

    @property
    def default_temperature(self) -> float:
        return float(self.settings_repo.get("default_temperature", "0.9"))

    @property
    def default_top_p(self) -> float:
        return float(self.settings_repo.get("default_top_p", "0.95"))

    @property
    def default_cfg_scale(self) -> float:
        return float(self.settings_repo.get("default_cfg_scale", "1.5"))

    @property
    def default_max_tokens(self) -> int:
        return int(self.settings_repo.get("default_max_tokens", "1600"))

    @property
    def stage2_quality(self) -> str:
        return self.settings_repo.get("stage2_quality", "full")

    @property
    def audio_output_sample_rate(self) -> int:
        return int(self.settings_repo.get("audio_output_sample_rate", "44100"))

    @property
    def auto_unload_stage1(self) -> bool:
        val = self.settings_repo.get("auto_unload_stage1", "true")
        return str(val).lower() in ("true", "1", "yes")

    @property
    def quantization_precision(self) -> str:
        return self.settings_repo.get("quantization_precision", "16-bit")

    @property
    def planning_mode(self) -> str:
        return self.settings_repo.get("planning_mode", "symbolic")

    @property
    def reference_mode(self) -> str:
        return self.settings_repo.get("reference_mode", "melody_only")

    def get_all(self) -> Dict[str, Any]:
        return {
            "model_directory_path": str(self.models_dir),
            "default_temperature": self.default_temperature,
            "default_top_p": self.default_top_p,
            "default_cfg_scale": self.default_cfg_scale,
            "default_max_tokens": self.default_max_tokens,
            "stage2_quality": self.stage2_quality,
            "audio_output_sample_rate": self.audio_output_sample_rate,
            "auto_unload_stage1": self.auto_unload_stage1,
            "quantization_precision": self.quantization_precision,
            "planning_mode": self.planning_mode,
            "reference_mode": self.reference_mode
        }

    def update(self, settings_dict: Dict[str, Any]):
        self.settings_repo.update_multiple(settings_dict)
