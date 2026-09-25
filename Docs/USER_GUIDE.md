# YuE Native macOS Studio - User Guide

## 1. Quick Start & DMG Installation
### Installing on Other Macs via DMG
The application is distributed as a standalone macOS disk image (`.dmg`):
- **DMG Installer File**: `Yue2Studio-2026092501.dmg` (also accessible as `Yue2Studio.dmg`)
- **Installation**:
  1. Double-click `Yue2Studio-2026092501.dmg` to mount the disk image.
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
  - Displays the current Build Number (`2026092501`), active model directory, and real-time unified memory usage.

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

## 9. Creating Pure Instrumental Music & Removing Vocals

### 9.1 Generating Pure Instrumental Tracks (1-Click Checkbox & In-Model Prompting)
YuE2 is trained on paired lyric-song data. To force the model to compose **pure instrumental music without any vocal singing or humming**:
1. **1-Click "Instrumental Only (No Vocals)" Checkbox (Recommended)**:
   - Check the **Instrumental Only (No Vocals)** checkbox in the Studio tab.
   - When enabled, Yue2Studio automatically:
     - Strips any vocal directives (`vocal`, `singer`, `singing`, `choir`, `voice`, etc.) from your style prompt.
     - Automatically injects `instrumental, pure music, backing track, no vocals, no voice, no singer` conditioning tags.
     - Canonicalizes all section tags in lyrics (`[verse]`, `[chorus]`, `[bridge]`, etc.) into pure structural accompaniment markers (`[inst]`), formatted with blank lines per official YuE specifications.
     - Bypasses vocal melody line injection into symbolic scores so the autoregressive model doesn't generate singing.
     - Automatically executes an acoustic DSP center-channel vocal suppression pass with low-frequency bass (< 160 Hz) and high-frequency shimmer preservation on the decoded 48 kHz stereo buffer.
     - Preserves your setting automatically across sessions in SQLite (`app_settings`).
2. **Genre Style Tags & Presets**:
   - You can also select the built-in **Pure Instrumental / Piano** or **Lo-Fi Instrumental Beats** from the Presets menu.
3. **Lyrics Box Formatting**:
   - When Instrumental Only is checked, you can leave the box as-is or use structural tags (`[intro]`, `[inst]`, `[solo]`, `[outro]`) using the quick-insert buttons.
4. **Generation Mode**:
   - Set **YuE2 Generation Mode** to **Off (Direct Generation)** or **Full + Generated Score**.

### 9.2 Removing Vocals from Already Generated Audio (1-Click Built-in or Post-Processing)
If an existing generated song contains vocals that you wish to remove:

#### Method A: 1-Click "Extract Instrumental" in Yue2Studio (Built-in)
- In the **Waveform Player** at the bottom of the Studio tab, click the **Extract Instrumental** button (guitar icon).
- Or in the **Library** tab, click **Extract Instrumental** next to any track.
- Yue2Studio applies real-time Mid-Side DSP center vocal cancellation (-33 dB attenuation on center vocal formants) while keeping 100% of the punchy mono bass and stereo instrumental panning intact. The clean instrumental version is saved as `[Instrumental] <Song Title>` and loaded immediately.

#### Method B: AI Stem Separation via Demucs (Studio Master Quality)
Meta AI's open-source **Demucs v4** (`htdemucs`) is the gold standard for vocal isolation on Apple Silicon:
```bash
# 1. Install Demucs
pip install -U demucs

# 2. Extract instrumental backing (separates into vocals and no_vocals)
demucs --two-stems=vocals path/to/your_song.wav
```
The resulting `no_vocals.wav` retains 100% of the drums, bass, synths, and guitars with zero vocal bleed.

#### Method C: FFmpeg DSP Mid-Side Cancellation
Because YuE2 outputs 48 kHz stereo with the vocal centered ($L \approx R$) and instruments spread wide:
```bash
# Cancel center vocal channel using Mid-Side processing
ffmpeg -i your_song.wav -af "stereotools=mlev=0:slev=1" instrumental.wav
```
This instantly attenuates the center lead vocal without requiring external models.

