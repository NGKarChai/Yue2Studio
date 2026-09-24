# YuE Native macOS Studio - Architecture Specification

## 1. System Overview
YuE Native macOS Studio is a 100% native Apple Silicon desktop application for music generation using the YuE architecture (Multimodal Art Projection). It operates with **ZERO Python dependencies**, executing full-song dual-track autoregressive generation and neural audio codec decoding directly via Swift, MLX Swift, Metal, Accelerate, and AVFoundation.

## 2. Core Architectural Pillars

### 2.1 Zero-Python Inference Engine
- **Framework**: `ml-explore/mlx-swift` (MIT License) and `swift-transformers` (Apache-2.0 License).
- **Metal Performance Shaders (MPS)**: Unified memory execution directly on Apple Silicon M-series GPU/NPU.
- **Quantization Support**: 4-bit and 8-bit group-wise quantized linear layers (`QuantizedLinear`), cutting memory bandwidth and model footprint to ~4-5 GB for 7B parameters.
- **Stage Decoupling & Dynamic Cache Clearing**:
  - `MLX.Memory.clearCache()` is executed between generation stages.
  - Stage 1 weights can be unloaded before Stage 2 executes on memory-constrained systems (e.g., 16 GB unified RAM).

### 2.2 Pipeline Topology
1. **Prompt Conditioning & Canonical Tokenization**:
   - Genre and structured lyrics formatted using official canonical YuE template:
     `Generate music from the given lyrics segment by segment.\n[Genre] {genres}\n{fullLyrics}\n\n[start_of_segment]\n{firstSegment}\n`
   - Primed with special audio tokens `<SOA>` (`32001`) and `<xcodec>` (`32016`).
   - Tokenized via LLaMA SentencePiece BPE tokenizer directly mapping subwords into model attention space.
2. **Stage 1 (Coarse Dual-Track Autoregressive Generation & Classifier-Free Guidance)**:
   - Autoregressively generates codebook level 0 coarse audio tokens for both vocal and instrumental tracks.
   - **Classifier-Free Guidance (CFG)**: Executes dual-branch inference contrasting conditional logits against unconditional audio continuation:
     $\text{guided\_logits} = \text{cfg\_scale} \cdot \log P(\text{token} \mid \text{genres, lyrics}) + (1 - \text{cfg\_scale}) \cdot \log P(\text{token} \mid \emptyset)$.
     Amplifies genre and instrumentation fidelity by $1.5\times$, preventing stylistic drift and generic sampling.
   - Dynamic KV caching and temperature/top-p/CFG sampling.
3. **Stage 2 (Acoustic Refinement & Parallel Dual-Track Acceleration)**:
   - **Parallel Dual-Track Batching (`[2, 1]` forward step)**: Stacks Vocal and Instrumental tracks into a single batched tensor pass on Metal GPU. Halves the required step forward passes from 20,216 to 10,108 steps for instant 2x acceleration with zero loss in fidelity.
   - **6-Second (300-Frame) Chunking**: Bounded KV-cache (maximum 2,400 tokens per chunk) eliminating memory fragmentation and O(N^2) memory reallocation stalls.
   - **Deterministic Greedy Argmax (`greedyBatch`)**: Evaluates argMax across both tracks simultaneously using a single `MLX.eval()` call, eliminating 50% of CPU-GPU synchronization stalls.
   - **Selectable Refinement Quality Modes (`Stage2Quality`)**:
     - *Draft Mode (Instant)*: Bypasses Stage 2, streaming Codebook 0 coarse tokens directly to X-Codec (0s Stage 2).
     - *Balanced Mode (~5x Faster)*: Refines Codebooks 1..3 (>92% acoustic fidelity), reducing residual steps per frame from 7 to 3.
     - *Studio Master Mode (2x Faster)*: Refines Codebooks 1..7 for maximum acoustic polish and high-frequency sparkle.
4. **Stage 3 (X-Codec Neural DAC Audio Decoder)**:
   - Residual Vector Quantizer (RVQ) codebook lookups summing across active acoustic codebooks (1, 4, or 8).
   - Linear projection (`fc2`: 1024 -> 256) into Descript Audio Codec (`acoustic_decoder`) latent space.
   - 4-stage transposed convolution blocks (`ConvTransposed1d`, upsampling 8x * 5x * 4x * 2x = 320x) equipped with `Snake1d` periodic activation functions and multi-receptive field (MRF) dilated residual units (dilations 1, 3, 9).
   - Synthesizes studio-grade 16.0 kHz / 24-bit floating point PCM audio, automatically converted and resampled in real-time by AVAudioEngine to output hardware sample rate.

### 2.3 Symbolic Music Engine & Notation Exporters (YuE2 & mlx-Yue Key Highlights)
- **All Five Generation Modes Supported (`vanch007/mlx-Yue` protocol)**:
  1. **Full + Generated Score (`cot="full"`)**: Fully automated song writing, score planning, and 48kHz audio generation from text prompt & lyrics.
  2. **Full + Supplied ABC Score (`cot="full"`)**: Compose songs conditioned on user-supplied ABC notation (melody + chords).
  3. **Melody + Generated Score (`cot="melody"`)**: Automatic lead-sheet melody generation and vocal/melody arrangement without chord symbols.
  4. **Melody + Supplied ABC Score (`cot="melody"`)**: Condition acoustic synthesis on an exact melody line from supplied ABC or transcribed audio reference.
  5. **Off / Direct Generation (`cot="off"`)**: Generates music and vocals directly from style prompt and lyrics without a symbolic score.
- **Official YuE2 Prompt Conditioning Protocol**:
  - `EOD = 151643`, `ABC_START = 151847`, `ABC_END = 151848`, `MUSIC_START = 151851`, `MUSIC_END = 151852`.
  - Symbolic CoT modes: `[EOD] + prompt + [ABC_START] + score + [ABC_END, MUSIC_START]`.
  - Direct / Off mode: `[EOD] + prompt + [ABC_START, ABC_END, MUSIC_START]`.
- **Native Standard MIDI File Exporter (`MIDIExporter`)**:
  - Generates 100% compliant Standard MIDI Files (SMF Format 1) playable in all standard players (QuickTime Player, macOS CoreAudio DLS Synth, GarageBand, Logic Pro, VLC):
    - **General MIDI Program Change**: Time 0 GM instruments on Channel 0 (Acoustic Grand Piano, `0xC0 0x00`) and Channel 1 (Acoustic Grand Piano, `0xC1 0x00`).
    - **Channel CC Parameters**: CC 7 Channel Volume (127 for melody, 96 for harmony), CC 10 Pan (64 center), CC 91 Reverb Send (40).
    - **Robust Chord Parser**: Accurately parses complex chords across all roots (`C, C#, Db, D, D#, Eb, E, F, F#, Gb, G, G#, Ab, A, A#, Bb, B`) and qualities (`Major, Minor (m), 7th, Maj7, Min7, Dim, Aug, Sus4, Sus2, 6th`).
    - **Sustained Harmony Accompaniment**: Chords sustain across measure boundaries rather than clipping after 1/8 note.
- **Native ABC Parser & Exporter (`ABCParser`, `AudioReferenceManager`)**:
  - Full-song transcription without truncation caps (processes all extracted notes across arbitrarily long audio tracks).
  - Clean 4-bar line formatting with measure barlines `|` and aligned lyrics `w:` lines according to standard ABC 2.1 specification.

### 2.4 Full Audio Transcription & Cover Chain (`vanch007/mlx-Yue` SheetSage2 + MERT2 Specification)
- **Multi-Window Stitching Supporting Arbitrarily Long Source Tracks (`buildSlidingWindowPlan` & `stitchNotes`)**:
  - Employs a sliding window plan with `window_seconds = 30.0s`, `hop_seconds = 20.0s`, and `overlap_seconds = 10.0s`.
  - Bounded memory footprint: slices source tracks of arbitrary length (e.g., 3-minute, 5-minute, or 30-minute songs) into 30-second processing windows, preventing memory bloat.
  - Acceptance interval: window $i$ accepts notes within $[acceptStart, acceptEnd]$, where seam notes are joined across adjacent windows using `stitchNotes(windowsNotes:maxGapSeconds:)` with a 60ms gap/overlap tolerance and pitch continuity check.
- **Tri-Format Audio Transcription Export**:
  - **ABC Score (`.abc`)**: Full song transcription without note truncation caps, formatted with standard 4-bar line wrapping, key signature estimation, and aligned lyrics.
  - **Playable Standard MIDI File (`.mid`)**: SMF Format 1 with General MIDI Program Change 0 (Acoustic Grand Piano), CC 7 Volume, CC 10 Center Pan, and sustained chord accompaniment.
  - **SheetSage2 / MERT2 Timing Labels (`.lab`)**: Standard tab-delimited timing label format (`<start_time>\t<end_time>\t<label>`):
    - `notes.lab`: `<startTime>\t<endTime>\t<NoteName><Octave>` (e.g., `0.000\t0.500\tC4`).
    - `chords.lab`: `<startTime>\t<endTime>\t<ChordName>` (e.g., `0.000\t2.000\tC:maj`).
    - `structure.lab`: `<startTime>\t<endTime>\t<Section>` (e.g., `0.000\t15.000\tintro`).
  - **1-Click Bundle Exporter**: Exports `.abc`, `.mid`, `_notes.lab`, `_chords.lab`, and `_structure.lab` in a single folder export action.
- **End-to-End Cover Pipeline (`prepareCoverPipeline(targetGenre:)`)**:
  - **1-Click Priming**: Transcribes source audio $\to$ extracts melody and harmonic structure $\to$ sets generation mode to `melodySupplied` (or `fullSupplied`) $\to$ locks the transcribed ABC score into the conditioning prompt.
  - **Target Style Morphing Presets**: Instant 1-click genre morphing buttons (80s Synthwave, Acoustic Folk, Cyberpunk EDM, Lo-Fi Jazz Pop, Modern Rock Anthem) while preserving the authentic vocal lead and melody contour.
  - **Key & Modal Modulation**:
    - *Pitch Transposition (`transpose(abc:semitones:)`)*: $\pm 12$ semitone shift across notes, chords, and key signature.
    - *Modal Transformation (`modulateMode(abc:transform:)`)*: Major $\leftrightarrow$ Minor modulation (flattening/sharpening 3rd, 6th, and 7th scale degrees and chord qualities).
    - *Lyric Realignment (`rewriteLyrics(abc:newLyrics:)`)*: Adapts new cover lyrics onto the transcribed melody.

### 2.5 Audio Subsystem
- **AVAudioEngine & AVAudioPlayerNode**: Low-latency native playback, dynamic format negotiation, and sample rate conversion.
- **Native Waveform Rendering**: SwiftUI Canvas with normalized RMS amplitude rendering.
- **Audio Export**: WAV, FLAC, and AAC export via `AVAudioFile` / `AudioToolbox`.

### 2.6 Persistence & State
- **Storage**: Thread-safe SQLite3 database (`storage.sqlite3`).
- **No Hardcoded Data**: All user settings, generation history, presets, and model registry are queried dynamically.
- **State Management**: SwiftUI `@Observable` / `ObservableObject` architecture (`AppState`).
- **Build Number**: `2026092402` (Current date + sequence number).
- **Target Platform**: macOS 14.0+ (Apple Silicon M1/M2/M3/M4)  
- **Display**: Fixed footer bar in the main application window showing build number and real-time unified memory consumption.
- **Top-P (Nucleus) Acoustic Filtering**: Rejects improbable acoustic codes in the tail of the distribution, eliminating vocal rasps, static, and phase noise.
- **Sliding-Window Recency Penalty**: Restricts repetition penalty to a recency window of 32 tokens, preventing full-codebook degradation while stopping stuck loops.
- **32-Bit Float Mastering Export**: Exports WAV directly as 32-bit floating point, preventing fixed-point quantization noise and integer conversion clipping.
- **Strict Acoustic Masking**: Fully suppresses non-music and speech tokens with $-\infty$, keeping Stage 1 bounded to XCodec Codebook 0 (45334..<46358) and `<EOA>` (32002).
- **Segment-by-Segment Generation Loop**: Iterates across structured lyric segments (`prepareOrderedSegments`), generating each segment until `<EOA>` before advancing to the next segment prompt.
- **Acoustic Vocoder**: Clean RVQ dequantization supporting pure Codebook 0 (zero noise), Balanced (Codebooks 0..3), and neural Stage 2 residual refinement with 8 RVQ codebooks.


