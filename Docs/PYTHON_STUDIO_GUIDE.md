# YuE Python Studio - User Guide

## 1. Overview
**YuE Python Studio** is a Python desktop/web-based music generation studio reproducing the full capabilities of YuE2 Studio with native Apple Silicon Metal Performance Shaders (`mps`), CUDA, and CPU support.

Unlike experimental Swift/MLX ports, the Python edition utilizes the official PyTorch dual-track autoregressive model and the verified X-Codec neural audio decoder, ensuring high acoustic fidelity and reliable output.

---

## 2. Quick Start

### 2.1 Starting the Studio
Navigate to the `YuePythonStudio` directory and launch using the local virtual environment:

```bash
cd /Users/ngkarchai/Documents/MyProjects/Yue2Studio/YuePythonStudio
.venv/bin/python run_studio.py
```

This will start the local server and automatically open the studio interface in your default browser at:
`http://127.0.0.1:7865`

Options:
- `--port 8080`: Listen on a custom port.
- `--no-browser`: Run in headless/server mode without opening a browser window.

---

## 3. Features & Workflow

### 3.1 Studio Workspace
- **Song Setup**: Enter a song title, descriptive genre/style tags (e.g. `female vocal, modern pop, uplifting melody, 120 bpm`), and structured lyrics split by section markers (`[verse]`, `[chorus]`, `[bridge]`, `[intro]`, `[outro]`).
- **Presets**: Click on preset chips to quickly populate genre tags or use the dropdown to load structured lyric templates from the database.
- **Hyperparameter Controls**:
  - **Target Song Duration** (default: `15s`, range: `5s` to `60s`): Directly specifies the intended song duration in seconds. In YuE (50 fps dual-track audio), 1 second corresponds to exactly 100 tokens.
  - **Temperature** (default: `0.9`): Controls sampling variety.
  - **Top-P** (default: `0.95`): Nucleus sampling cutoff to prevent rasps and out-of-distribution acoustic codes.
  - **CFG Guidance Scale** (default: `1.5`): Classifier-Free Guidance strength to keep the song aligned with prompt tags and lyrics.
  - **Stage 2 Quality**:
    - `Draft`: Instant coarse token decoding (bypasses Stage 2 for immediate feedback).
    - `Balanced` *(Recommended)*: Refines Codebooks 1–3 for ~5x faster generation with >92% acoustic fidelity.
    - `Studio Master`: Full 7-codebook refinement for master polish.
  - **Stereo Width**: Smooth panning adjustment from solid mono (`0.0`) to wide stereo panorama (`1.0`).
  - **Anti-Clipping Limiter**: Soft-knee peak limiter normalizing output to -2.0 dBFS true peak without digital distortion.
  - **Automatic Note Sheet Transcription**: Upon completing generation, the lead vocal melody is automatically transcribed into visual sheet music and made available in the **Symbolic Score** tab for viewing and one-click export to MIDI, MusicXML, and ABC.

### 3.2 Audio Reference & Cover Studio
- **Audio Upload**: Drag and drop any reference audio file (`.wav`, `.mp3`, `.flac`).
- **Pitch & Key Tracking**: Automatically computes $F_0$ pitch trajectory, tempo (BPM), and musical key & mode using Krumhansl-Schmuckler tonal profiles.
- **Transposition**: Shift key signature and melodic notes up/down by $\pm 12$ semitones.
- **Modal Modulation**: Transform between Major (uplifting) and Minor (melancholic).
- **Extract Melody to Score**: Transcribe detected reference audio pitches into standardized ABC notation.
- **Align Lyrics**: Syllabically align your current lyrics under the reference melody notes.

### 3.3 Symbolic Score & Notation Exporters
- **Visual Sheet Music**: Interactive staff rendering clef, key signature, meter, BPM, polyphonic chords, and melodic note heads.
- **ABC Code Editor**: Directly view and edit raw ABC notation.
- **One-Click Exports**:
  - **MIDI (`.mid`)**: Multi-track Standard MIDI File (Conductor Track, Lead Vocal, Piano Chords).
  - **MusicXML (`.musicxml`)**: Partwise MusicXML 4.0 compatible with MuseScore, Finale, Sibelius, and Dorico.
  - **ABC (`.abc`)**: Plain text score for notation programs.

### 3.4 Library & Audio Waveform Player
- **Interactive Scrubber**: Seek anywhere on the interactive canvas waveform.
- **Generation History**: Automatically logged to the SQLite database (`storage.sqlite3`) with audio stem paths and duration.
- **Export**: One-click download of synthesized tracks in lossless 24-bit PCM WAV.

---

## 4. REST API Endpoints

| Method | Endpoint | Description |
|---|---|---|
| `GET` | `/api/version` | Returns active Build Number (`2026092101`) and version |
| `GET` | `/api/system/status` | Real-time device (`MPS`/`CUDA`/`CPU`) and RAM metrics |
| `GET` | `/api/settings` | Retrieve user preferences from SQLite |
| `POST` | `/api/settings` | Update user preferences in SQLite |
| `GET` | `/api/presets/genres` | Query preset genre tags from database |
| `GET` | `/api/presets/lyrics` | Query preset lyrics from database |
| `GET` | `/api/history` | List previous generation records |
| `POST` | `/api/generate` | Start background generation pipeline |
| `POST` | `/api/cancel` | Cancel active generation |
| `POST` | `/api/reference/analyze` | Ingest and analyze reference audio track |
| `POST` | `/api/export/midi` | Generate and download Standard MIDI file |
| `POST` | `/api/export/musicxml` | Generate and download MusicXML 4.0 file |
