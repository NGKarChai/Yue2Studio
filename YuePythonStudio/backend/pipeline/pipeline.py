import os
import time
import uuid
import torch
import numpy as np
from pathlib import Path
from typing import Optional, Callable, Dict, Any, Tuple

from ..config import StudioConfig
from ..database.db import DatabaseManager
from ..database.repository import HistoryRepository
from ..database.models import GenerationRecord
from .mmtokenizer import _MMSentencePieceTokenizer
from .stage1_generator import Stage1Generator
from .stage2_generator import Stage2Generator
from .stage3_vocoder import Stage3Vocoder
from ..audio.processor import AudioProcessor
from ..symbolic.planner import SymbolicPlanner

class YueFullPipeline:
    def __init__(self, config: Optional[StudioConfig] = None):
        self.config = config or StudioConfig()
        self.db = DatabaseManager()
        self.history_repo = HistoryRepository(self.db)

        # Select fastest available device
        if torch.backends.mps.is_available():
            self.device = torch.device("mps")
        elif torch.cuda.is_available():
            self.device = torch.device("cuda:0")
        else:
            self.device = torch.device("cpu")

        models_dir = self.config.models_dir
        self.tokenizer_path = models_dir / "stage1" / "tokenizer.model"
        if not self.tokenizer_path.exists():
            self.tokenizer_path = models_dir.parent / "Models" / "stage1" / "tokenizer.model"

        self._tokenizer: Optional[_MMSentencePieceTokenizer] = None
        self.stage1 = Stage1Generator(models_dir, self.device)
        self.stage2 = Stage2Generator(models_dir, self.device)
        self.stage3 = Stage3Vocoder(models_dir, self.device)

        self.is_cancelled = False

    @property
    def tokenizer(self) -> _MMSentencePieceTokenizer:
        if self._tokenizer is None:
            if not self.tokenizer_path.exists():
                raise FileNotFoundError(f"Tokenizer model not found at {self.tokenizer_path}")
            self._tokenizer = _MMSentencePieceTokenizer(str(self.tokenizer_path))
        return self._tokenizer

    def cancel(self):
        self.is_cancelled = True

    def generate_song(
        self,
        genre_tags: str,
        lyrics: str,
        title: str = "Untitled Song",
        temperature: Optional[float] = None,
        top_p: Optional[float] = None,
        cfg_scale: Optional[float] = None,
        target_seconds: Optional[int] = None,
        max_tokens: Optional[int] = None,
        seed: int = 42,
        stage2_quality: Optional[str] = None,
        stereo_width: float = 0.5,
        apply_mastering: bool = True,
        cot_mode: str = "off",
        custom_abc: Optional[str] = None,
        progress_callback: Optional[Callable[[Dict[str, Any]], None]] = None
    ) -> Tuple[GenerationRecord, str]:
        self.is_cancelled = False
        start_time = time.time()

        temp = temperature if temperature is not None else self.config.default_temperature
        p = top_p if top_p is not None else self.config.default_top_p
        cfg = cfg_scale if cfg_scale is not None else self.config.default_cfg_scale
        
        # Calculate tokens from duration in seconds (100 tokens = 1 second: 50 fps * 2 tracks)
        if target_seconds is not None and target_seconds > 0:
            tokens = int(target_seconds * 100)
        elif max_tokens is not None:
            tokens = max_tokens
        else:
            tokens = self.config.default_max_tokens

        q = stage2_quality if stage2_quality is not None else self.config.stage2_quality

        gen_id = str(uuid.uuid4()).upper()

        def emit(phase: str, frac: float, msg: str):
            if progress_callback:
                progress_callback({
                    "generation_id": gen_id,
                    "phase": phase,
                    "progress_fraction": frac,
                    "message": msg,
                    "elapsed_seconds": round(time.time() - start_time, 1)
                })

        emit("Initializing", 0.02, "Validating parameters and checking weights...")

        # 1. Prepare symbolic CoT prompt if requested
        cot_prompt = ""
        if cot_mode in ("full", "melody"):
            cot_prompt = SymbolicPlanner.build_symbolic_cot_prompt(genre_tags, lyrics, cot_mode, custom_abc)
            emit("Symbolic Planning", 0.05, f"Prepared symbolic composition plan ({cot_mode})")

        # 2. Stage 1: Coarse Token Generation
        emit("Stage 1: Coarse Generation", 0.1, "Synthesizing vocal and instrumental coarse tracks...")
        vocals_cb0, inst_cb0 = self.stage1.generate_coarse_tokens(
            genre_tags=genre_tags,
            lyrics=lyrics,
            tokenizer=self.tokenizer,
            max_new_tokens=tokens,
            temperature=temp,
            top_p=p,
            cfg_scale=cfg,
            cot_prompt=cot_prompt,
            progress_callback=lambda f, m: emit("Stage 1: Coarse Generation", 0.1 + 0.4 * f, m)
        )

        if self.is_cancelled:
            raise InterruptedError("Generation was cancelled by user.")

        if self.config.auto_unload_stage1:
            self.stage1.unload_model()
            emit("Memory Optimization", 0.52, "Unloaded Stage 1 model to conserve unified RAM")

        # 3. Stage 2: Acoustic Refinement
        emit("Stage 2: Acoustic Refinement", 0.55, f"Refining acoustic codebooks (Quality: {q.capitalize()})...")
        vocal_codes = self.stage2.generate_stage2_track(
            cb0_track=vocals_cb0,
            tokenizer=self.tokenizer,
            quality=q,
            progress_callback=lambda f, m: emit("Stage 2: Acoustic Refinement", 0.55 + 0.15 * f, f"Vocal: {m}")
        )
        inst_codes = self.stage2.generate_stage2_track(
            cb0_track=inst_cb0,
            tokenizer=self.tokenizer,
            quality=q,
            progress_callback=lambda f, m: emit("Stage 2: Acoustic Refinement", 0.70 + 0.15 * f, f"Instrumental: {m}")
        )

        self.stage2.unload_model()

        if self.is_cancelled:
            raise InterruptedError("Generation was cancelled by user.")

        # 4. Stage 3: Neural Audio Synthesis
        emit("Stage 3: Neural Synthesis", 0.88, "Decoding acoustic codebooks via X-Codec SoundStream...")
        vocal_audio = self.stage3.decode_codes_to_audio(vocal_codes)
        inst_audio = self.stage3.decode_codes_to_audio(inst_codes)

        self.stage3.unload_model()

        # 5. Spatial Mixing & Mastering
        emit("Mastering & Limiting", 0.95, "Applying stereo panoramic width and soft-knee peak limiter...")
        mixed_audio = AudioProcessor.adjust_stereo_width(vocal_audio, inst_audio, stereo_width)

        if apply_mastering:
            mixed_audio = AudioProcessor.apply_mastering_limiter(mixed_audio, target_peak_dbfs=-2.0)

        # 6. Save Audio File
        parent_generations = self.config.models_dir.parent / "Generations"
        parent_generations.mkdir(parents=True, exist_ok=True)
        timestamp = int(time.time())
        filename = f"song_{timestamp}_{gen_id[:8].lower()}.wav"
        output_path = parent_generations / filename

        sample_rate = 16000 # Native XCodec sample rate
        AudioProcessor.export_wav(mixed_audio, output_path, sample_rate=sample_rate, subtype="PCM_24")

        duration_sec = float(mixed_audio.shape[1] / sample_rate) if mixed_audio.ndim == 2 else float(len(mixed_audio) / sample_rate)

        # 6b. Automatically transcribe melodic note sheet from generated vocal lead
        emit("Note Sheet Transcription", 0.98, "Transcribing vocal melody into visual note sheet...")
        try:
            from ..audio.reference_analyzer import AudioReferenceAnalyzer
            transcribed_abc = AudioReferenceAnalyzer.transcribe_to_abc(vocal_audio, sr=sample_rate, title=title or "Generated Song")
        except Exception:
            transcribed_abc = custom_abc or ""

        # 7. Record to Database
        record = GenerationRecord(
            id=gen_id,
            title=title or "Untitled Song",
            genre_tags=genre_tags,
            lyrics=lyrics,
            temperature=temp,
            top_p=p,
            cfg_scale=cfg,
            max_tokens=tokens,
            seed=seed,
            audio_path=str(output_path),
            duration_seconds=round(duration_sec, 2),
            status="completed"
        )
        self.history_repo.add_record(record)

        emit("Complete", 1.0, f"Generated {duration_sec:.1f}s track in {round(time.time() - start_time, 1)}s")
        return record, transcribed_abc
