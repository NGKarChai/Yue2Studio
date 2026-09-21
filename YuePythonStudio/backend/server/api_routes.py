import os
import psutil
import torch
import shutil
from pathlib import Path
from typing import Dict, Any, Optional
from fastapi import APIRouter, HTTPException, UploadFile, File, Form, BackgroundTasks
from fastapi.responses import FileResponse, JSONResponse
from pydantic import BaseModel

from .. import BUILD_NUMBER, __version__
from ..config import StudioConfig
from ..database.db import DatabaseManager
from ..database.repository import SettingsRepository, PresetsRepository, HistoryRepository, ModelRegistryRepository
from ..database.models import GenerationRecord
from ..audio.reference_analyzer import AudioReferenceAnalyzer
from ..symbolic.abc_parser import ABCParser
from ..symbolic.midi_exporter import MIDIExporter
from ..symbolic.musicxml_exporter import MusicXMLExporter
from ..symbolic.planner import SymbolicPlanner
from ..pipeline.pipeline import YueFullPipeline

router = APIRouter(prefix="/api")

db = DatabaseManager()
config = StudioConfig()
settings_repo = SettingsRepository(db)
presets_repo = PresetsRepository(db)
history_repo = HistoryRepository(db)
registry_repo = ModelRegistryRepository(db)

pipeline_instance: Optional[YueFullPipeline] = None

def get_pipeline() -> YueFullPipeline:
    global pipeline_instance
    if pipeline_instance is None:
        pipeline_instance = YueFullPipeline(config)
    return pipeline_instance

# Pydantic Request Models
class GenerationRequest(BaseModel):
    title: str = "Untitled Song"
    genre_tags: str
    lyrics: str
    temperature: Optional[float] = None
    top_p: Optional[float] = None
    cfg_scale: Optional[float] = None
    target_seconds: Optional[int] = 15
    max_tokens: Optional[int] = None
    seed: int = 42
    stage2_quality: Optional[str] = None
    stereo_width: float = 0.5
    apply_mastering: bool = True
    cot_mode: str = "off"
    custom_abc: Optional[str] = None

class SettingsUpdateRequest(BaseModel):
    settings: Dict[str, Any]

class TransposeRequest(BaseModel):
    abc_text: str
    semitones: int

class ModulateRequest(BaseModel):
    abc_text: str
    target_mode: str = "minor"

# Active generation progress tracker
active_progress: Dict[str, Any] = {
    "status": "idle",
    "phase": "Idle",
    "progress_fraction": 0.0,
    "message": "",
    "generation_id": None
}

# 1. Version Endpoint (User Rule 8)
@router.get("/version")
def get_version():
    return {
        "build_number": BUILD_NUMBER,
        "version": __version__,
        "status": "ok"
    }

# 2. System Status
@router.get("/system/status")
def get_system_status():
    mem = psutil.virtual_memory()
    mps_avail = torch.backends.mps.is_available()
    cuda_avail = torch.cuda.is_available()
    device_str = "Apple Silicon (MPS)" if mps_avail else ("CUDA GPU" if cuda_avail else "CPU")

    return {
        "build_number": BUILD_NUMBER,
        "device": device_str,
        "total_ram_gb": round(mem.total / (1024**3), 1),
        "used_ram_gb": round(mem.used / (1024**3), 1),
        "free_ram_gb": round(mem.available / (1024**3), 1),
        "ram_percent": mem.percent,
        "models_dir": str(config.models_dir)
    }

# 3. Settings (User Rule 3)
@router.get("/settings")
def get_settings():
    return config.get_all()

@router.post("/settings")
def update_settings(req: SettingsUpdateRequest):
    config.update(req.settings)
    return {"status": "success", "updated": req.settings}

# 4. Presets (User Rule 4)
@router.get("/presets/genres")
def get_preset_genres():
    genres = presets_repo.get_genres()
    return [{"id": g.id, "name": g.name, "tags": g.tags, "description": g.description} for g in genres]

@router.get("/presets/lyrics")
def get_preset_lyrics():
    lyrics = presets_repo.get_lyrics()
    return [{"id": l.id, "title": l.title, "lyrics": l.lyrics} for l in lyrics]

# 5. History
@router.get("/history")
def get_history():
    records = history_repo.list_all()
    return [
        {
            "id": r.id,
            "title": r.title,
            "genre_tags": r.genre_tags,
            "lyrics": r.lyrics,
            "temperature": r.temperature,
            "top_p": r.top_p,
            "cfg_scale": r.cfg_scale,
            "max_tokens": r.max_tokens,
            "seed": r.seed,
            "audio_path": r.audio_path,
            "audio_url": f"/api/audio/file?path={r.audio_path}",
            "duration_seconds": r.duration_seconds,
            "status": r.status,
            "created_at": r.created_at
        }
        for r in records
    ]

# 6. Audio Streaming
@router.get("/audio/file")
def get_audio_file(path: str):
    file_path = Path(path)
    if not file_path.exists():
        raise HTTPException(status_code=404, detail="Audio file not found")
    return FileResponse(str(file_path), media_type="audio/wav")

# 7. Generation
@router.get("/generate/progress")
def get_generation_progress():
    return active_progress

@router.post("/generate")
def start_generation(req: GenerationRequest, background_tasks: BackgroundTasks):
    global active_progress
    if active_progress["status"] == "running":
        raise HTTPException(status_code=409, detail="A generation task is already in progress.")

    active_progress = {
        "status": "running",
        "phase": "Starting",
        "progress_fraction": 0.01,
        "message": "Initializing generation pipeline...",
        "generation_id": None
    }

    def run_job():
        global active_progress
        try:
            pipe = get_pipeline()
            def on_progress(p: Dict[str, Any]):
                global active_progress
                active_progress.update({
                    "status": "running",
                    "phase": p["phase"],
                    "progress_fraction": p["progress_fraction"],
                    "message": p["message"],
                    "generation_id": p.get("generation_id")
                })

            rec, note_sheet_abc = pipe.generate_song(
                genre_tags=req.genre_tags,
                lyrics=req.lyrics,
                title=req.title,
                temperature=req.temperature,
                top_p=req.top_p,
                cfg_scale=req.cfg_scale,
                target_seconds=req.target_seconds,
                max_tokens=req.max_tokens,
                seed=req.seed,
                stage2_quality=req.stage2_quality,
                stereo_width=req.stereo_width,
                apply_mastering=req.apply_mastering,
                cot_mode=req.cot_mode,
                custom_abc=req.custom_abc,
                progress_callback=on_progress
            )

            active_progress = {
                "status": "completed",
                "phase": "Completed",
                "progress_fraction": 1.0,
                "message": f"Successfully generated '{rec.title}'!",
                "generation_id": rec.id,
                "audio_url": f"/api/audio/file?path={rec.audio_path}",
                "abc_score": note_sheet_abc
            }
        except Exception as e:
            active_progress = {
                "status": "failed",
                "phase": "Failed",
                "progress_fraction": 0.0,
                "message": str(e),
                "generation_id": None
            }

    background_tasks.add_task(run_job)
    return {"status": "started", "message": "Generation task scheduled in background"}

@router.post("/cancel")
def cancel_generation():
    global active_progress
    pipe = get_pipeline()
    pipe.cancel()
    active_progress = {
        "status": "idle",
        "phase": "Cancelled",
        "progress_fraction": 0.0,
        "message": "Generation cancelled by user",
        "generation_id": None
    }
    return {"status": "cancelled"}

# 8. Reference Audio Analysis
@router.post("/reference/analyze")
async def analyze_reference(file: UploadFile = File(...)):
    temp_dir = Path("/tmp/yue_reference_uploads")
    temp_dir.mkdir(parents=True, exist_ok=True)
    temp_file = temp_dir / file.filename

    with open(temp_file, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)

    try:
        result = AudioReferenceAnalyzer.analyze_audio_file(str(temp_file))
        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to analyze audio: {str(e)}")

# 9. Symbolic Transformations
@router.post("/symbolic/transpose")
def transpose_symbolic(req: TransposeRequest):
    transposed = SymbolicPlanner.transpose_abc(req.abc_text, req.semitones)
    parsed = ABCParser.parse(transposed)
    return {"transposed_abc": transposed, "parsed": parsed}

@router.post("/symbolic/modulate")
def modulate_symbolic(req: ModulateRequest):
    modulated = SymbolicPlanner.modulate_mode(req.abc_text, req.target_mode)
    parsed = ABCParser.parse(modulated)
    return {"modulated_abc": modulated, "parsed": parsed}

# 10. Exporters (MIDI & MusicXML)
@router.post("/export/midi")
def export_midi(abc_text: str = Form(...)):
    out_path = Path("/tmp/yue_exports") / "song_export.mid"
    exported = MIDIExporter.export(abc_text, out_path)
    return FileResponse(str(exported), media_type="audio/midi", filename="song_composition.mid")

@router.post("/export/musicxml")
def export_musicxml(abc_text: str = Form(...)):
    out_path = Path("/tmp/yue_exports") / "song_export.musicxml"
    exported = MusicXMLExporter.export(abc_text, out_path)
    return FileResponse(str(exported), media_type="application/vnd.recordare.musicxml+xml", filename="song_composition.musicxml")
