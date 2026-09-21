# YuE Python Studio - Architecture Specification

## 1. System Architecture
YuE Python Studio is designed as a modular, high-throughput music generation environment executing on Apple Silicon (`mps`), CUDA, and CPU. It interfaces directly with pre-downloaded PyTorch weights in `Models/` and persists all dynamic settings and history in `storage.sqlite3`.

```
                  ┌─────────────────────────────────────────┐
                  │          FastAPI Studio Server          │
                  │ (REST API & Static Dashboard Frontend)  │
                  └────────────────────┬────────────────────┘
                                       │
                ┌──────────────────────┴──────────────────────┐
                ▼                                             ▼
┌───────────────────────────────┐             ┌───────────────────────────────┐
│     Persistence & State       │             │   Inference Orchestrator      │
│  (DatabaseManager / SQLite)   │             │      (YueFullPipeline)        │
├───────────────────────────────┤             ├───────────────────────────────┤
│ • app_settings                │             │ • Stage 1: Coarse LLaMA Gen   │
│ • preset_genres               │             │ • Stage 2: Codebook Expander  │
│ • preset_lyrics               │             │ • Stage 3: Neural Vocoder     │
│ • generation_history          │             │ • Audio Mastering & Limiting  │
│ • model_registry              │             └───────────────┬───────────────┘
└───────────────────────────────┘                             │
                                                              ▼
                                              ┌───────────────────────────────┐
                                              │  Symbolic & Audio Analysis    │
                                              ├───────────────────────────────┤
                                              │ • F0 PyIN Pitch Tracker       │
                                              │ • Krumhansl-Schmuckler Key    │
                                              │ • ABC Parser & Visualizer     │
                                              │ • MIDI & MusicXML Exporters   │
                                              └───────────────────────────────┘
```

## 2. Pipeline Stages

### 2.1 Stage 1: Dual-Track Autoregressive Generation
- **Backbone**: LLaMA-based causal language model (`YuE-s1-7B-anneal-en-cot` or `stage1-zh`).
- **Prompt Conditioning**: Canonical YuE template with genre tags and lyric segments.
- **Interleaved Generation**: Autoregressively produces interleaved vocal and instrumental acoustic codes for Codebook 0 (50 frames/sec = 100 tokens/sec).
- **Logit Constraints**: `BlockTokenRangeProcessor` strictly restricts sampling to valid audio codec tokens and `<EOA>` (`32002`).

### 2.2 Stage 2: Acoustic Refinement
- **Backbone**: 1B LLaMA model (`YuE-s2-1B-general`).
- **Residual Prediction**: Refines coarse tokens into fine-grained residual vector quantization (RVQ) codebooks.
- **Selectable Quality**:
  - `Draft`: Bypasses stage 2, routing codebook 0 directly to neural decoder.
  - `Balanced`: Refines codebooks 1–3 for ~5x speedup with minimal perceptual loss.
  - `Studio Master`: Full 7-codebook refinement.

### 2.3 Stage 3: Neural Audio Decoder (X-Codec)
- **SoundStream Decoder**: Official X-Codec neural audio decoder reconstructing 16.0 kHz float32 raw PCM from RVQ codebooks.
- **Vocos Upsampler**: Optional high-frequency upsampler converting 16 kHz to 44.1 kHz.

### 2.4 Mastering & Dynamics
- **Stereo Spatial Widener**: Controls vocal centering and instrumental panorama width.
- **Soft-Knee Peak Limiter**: Normalizes signal to -2.0 dBFS true peak without digital saturation or inter-sample clipping.
- **Lossless Export**: Generates 24-bit floating point WAV.

## 3. Compliance Verification
- **Commercial Use (Rule 1)**: All third-party libraries (PyTorch, torchaudio, transformers, soundfile, fastapi, uvicorn, scipy, mido, librosa) are licensed under permissive open-source licenses (MIT, BSD-3, Apache-2.0, ISC).
- **No Hardcoded Data (Rules 3, 4)**: All settings, presets, and history records are dynamically queried from `storage.sqlite3`.
- **Documentation (Rule 5)**: Complete architecture and user documentation placed in `Docs/`.
- **Package Modularity (Rule 6)**: Segregated into `backend.pipeline`, `backend.database`, `backend.symbolic`, `backend.audio`, `backend.server`, and `frontend`.
- **Build Number (Rules 7, 8)**: Build `2026092101` rendered in the GUI footer and exposed at `GET /api/version`.
- **Frontend ID Prefixing (Rule 9)**: All HTML/DOM elements strictly adhere to the `yue_` naming convention.
