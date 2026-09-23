# YuE Native macOS Studio - User Guide

## 1. Quick Start & DMG Installation
### Installing on Other Macs via DMG
The application is distributed as a standalone macOS disk image (`.dmg`):
- **DMG Installer File**: `Yue2Studio-2026092301.dmg` (also accessible as `Yue2Studio.dmg`)
- **Installation**:
  1. Double-click `Yue2Studio-2026092301.dmg` to mount the disk image.
  2. Drag the `Yue2Studio` application icon into the `Applications` folder symlink.
  3. Open `Applications` and launch `Yue2Studio`.
- **Gatekeeper First-Launch Tip**:
  If macOS shows a security warning that the developer cannot be verified:
  - Right-click (or Control-click) `Yue2Studio` in the `Applications` folder and select **Open**.
  - Click **Open** in the confirmation dialog. (Only needed once on first launch).
- **Rebuilding the DMG**:
  Run `./scripts/create_dmg.sh` to package a fresh release DMG.

### Running from Project Directory (Development)
```bash
# Option 1: Open the local application bundle directly
open Yue2Studio.app

# Option 2: Run via Swift Package Manager
swift run Yue2Studio
```

## 2. Interface Overview
- **Sidebar**:
  - **Studio**: Main creative workspace with genre tags, lyrics editor, and generation controls.
  - **Models**: Weight directory configuration, status check, and downloader.
  - **Library**: Historical generation archive with instant playback and export options.
  - **Settings**: Audio device output, default inference precision (4-bit / 8-bit / 16-bit), and memory management options.
- **Footer**:
  - Displays the current Build Number (`2026092301`), active model directory, and real-time unified memory usage.

## 3. Formatting Prompts & Lyrics
YuE recognizes structural song tags in lyrics:
- `[verse]`
- `[chorus]`
- `[bridge]`
- `[intro]`
- `[outro]`

### Example Genre Tags
`female vocal, uplifting melodic pop, electric piano, driving drums, synth brass, 120 bpm`

### Example Lyrics
```
[verse]
Waking up under morning light
Chasing shadows into the night
Every step brings a brand new sound
Feet are dancing off the ground

[chorus]
Hear the music rising high
Painting colors in the sky
We are singing through the rain
Nothing holding back the flame
```

## 4. Sampling & Acoustic Hyperparameters
- **Temperature**: Controls creativity and randomness for coarse melody/vocal token generation (default: 0.9).
- **Top-P**: Nucleus sampling cutoff (default: 0.95).
- **CFG Scale**: Classifier-Free Guidance strength (default: 1.5).
- **Max Audio Tokens**: Sets song segment length (e.g. 500-2888 tokens).
- **Stage 2 Refinement Quality**:
  - `🚀 Draft (Instant)`: Bypasses Stage 2 entirely (0s refinement), streaming Codebook 0 coarse tokens straight to the X-Codec neural decoder. Instant acoustic feedback on song structure, lyrics, and melody.
  - `⚡ Balanced (~5x Faster)` *(Default)*: Refines Codebooks 1–3 using parallel dual-track batching. Retains >92% of full acoustic energy and spectral definition while slashing generation time by ~80%.
  - `💎 Studio Master (2x Faster)`: Executes full 7-codebook refinement for vocal and instrumental tracks using parallel dual-track batching. Delivers polished master clarity and high-frequency resolution.
- **Stereo Width (0% to 100%)**:
  - `0% (Solid Mono)`: Locks the lead vocal and backing tracks into a tight, focused center channel. Completely bypasses Apple Spatial Audio / binaural widening effects on macOS and AirPods.
  - `50% (Natural Balanced)`: Anchors lead vocal in the phantom center while giving instruments gentle acoustic stereo depth.
  - `100% (Wide Stereo)`: Full stereo panorama.
- **Headroom & Anti-Clipping Limiter**: Automatically normalizes master audio to -2.0 dBFS true peak with a soft-knee saturation curve, eliminating inter-sample distortion when CoreAudio resamples 16 kHz to 48 kHz hardware output.

## 5. Full Audio Transcription & Cover Chain Studio

YuE2 Studio provides an end-to-end native music transcription and cover song creation suite:

### 5.1 Uploading & Multi-Window Audio Transcription
- Click **Upload Reference Audio Track** in the Cover Studio card or drag-and-drop any audio file (`.wav`, `.mp3`, `.m4a`, `.flac`, `.aiff`).
- **Multi-Window Stitching for Arbitrarily Long Tracks**:
  - Automatically slices long tracks into 30-second sliding windows with 10-second overlaps and bounded memory usage ($O(1)$ memory consumption).
  - Merges seam notes across window boundaries via `stitchNotes` with a 60ms gap/overlap threshold and pitch matching.
  - Automatically detects the key signature using the Krumhansl-Schmuckler harmonic algorithm.

### 5.2 Conditioning Modes
- **Melody Only (Vocal)**: Extracts the vocal melody line into an editable ABC score and conditions generation using `cot="melody"`. The melody is preserved while the instrumental backing, genre, groove, and arrangement are completely transformed according to your target prompt.
- **Full Reference (Song)**: Encodes full audio reference tokens into Stage 1 reference codebooks, guiding YuE to capture overall instrumentation, groove, and vocal style.

### 5.3 1-Click End-to-End Cover Pipeline
- Click **⚡️ Prime 1-Click Cover Pipeline** or choose one of the quick style morphing presets:
  - **80s Synthwave**: Retro analog synths, driving LinnDrum, neon pads, 124 BPM.
  - **Acoustic Folk**: Fingerpicked warm guitar, soft strings, intimate vocal warmth, 110 BPM.
  - **Cyberpunk EDM**: Massive saw synths, aggressive sidechained drops, 128 BPM.
  - **Lo-Fi Jazz Pop**: Mellow Rhodes piano, vinyl crackle, relaxed soulful vocal, 85 BPM.
  - **Rock Anthem**: Distorted electric guitars, live stadium drums, soaring rock vocals, 130 BPM.
- Priming extracts the melody score, sets the generation mode to `Melody + Supplied ABC Score` (`melodySupplied`), sets the song title, and locks the score. Simply hit **Generate Song** to re-synthesize!

### 5.4 Key & Modal Manipulation
- **Semitone Pitch Transposition**: Shift key signature, chords, and melody up or down across a $\pm 12$ semitone range. Perfect for adapting vocals across vocal registers (e.g. female to male vocal range).
- **Major $\leftrightarrow$ Minor Modal Modulation**:
  - `Major -> Minor (Melancholic)`: Flattens the 3rd, 6th, and 7th scale degrees and transforms major chords to minor triads (`C` $\to$ `Cm`, `G` $\to$ `Gm`).
  - `Minor -> Major (Uplifting)`: Elevates minor melodies into bright, triumphant major keys.
- **Extract Melody to Score**: Transcribes detected audio pitches into editable ABC notation and interactive sheet music.
- **Align Lyrics to Melody**: Syllabically aligns your structured lyrics under each transcribed melodic note.

## 6. YuE2 Generation Modes (`vanch007/mlx-Yue` Specification)

YuE2 features 5 official generation modes in the **YuE2 Generation Mode** picker:
1. **Full + Generated Score (`fullGenerated`)**: Fully automated song writing, score planning, and 48kHz audio generation from prompt and lyrics.
2. **Full + Supplied ABC Score (`fullSupplied`)**: Composes audio conditioned on user-supplied ABC notation (melody + chord accompaniment).
3. **Melody + Generated Score (`melodyGenerated`)**: Automatic lead-sheet melody generation without chord symbols, followed by acoustic rendering.
4. **Melody + Supplied ABC Score (`melodySupplied`)**: Conditions acoustic synthesis on an exact melody line from your transcribed reference or custom score.
5. **Off (Direct Generation) (`direct`)**: Generates music and vocals directly from style prompt and lyrics without a symbolic score.

## 7. Tri-Format Audio Transcription & Notes Export
Click the **Export Notes** menu in the Score editor or **Export Bundle (ABC + MIDI + LAB)** in Cover Studio:
- **Export MIDI (`.mid`)**:
  - Standard MIDI File (SMF Format 1) playable in all standard players (QuickTime, GarageBand, Logic Pro, VLC).
  - General MIDI Program Change 0 (Acoustic Grand Piano), CC 7 Volume (127/96), CC 10 Center Pan, and sustained chord accompaniment.
- **Export Timing Labels (`.lab`)**:
  - SheetSage2 & MERT2 compliant tab-delimited timing label format (`<start>\t<end>\t<label>`):
    - `_notes.lab`: Exact note start and end timestamps (e.g., `0.000\t0.500\tC4`).
    - `_chords.lab`: Harmonic progression timeline (e.g., `0.000\t2.000\tC:maj`).
    - `_structure.lab`: Section timing markers (e.g., `0.000\t15.000\tintro`).
- **Export ABC Score (`.abc`)**:
  - Complete ABC score without note truncation, wrapped in standard 4-bar measures.
- **Export Complete Bundle (ABC + MIDI + LAB)**:
  - 1-click export of all 5 transcription files (`.abc`, `.mid`, `_notes.lab`, `_chords.lab`, `_structure.lab`) into your chosen directory.

## 8. Audio Playback and Export
- Once generation finishes, the song appears in the **Waveform Player**.
- Use the scrubber to seek anywhere in the audio track.
- Click **Export Audio** to save the synthesized track as `.wav` (Lossless 44.1kHz / 24-bit).
