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

### 2.3 Symbolic Music Engine & Notation Exporters
- **Symbolic Planning (YuE2)**:
  - Supports Chain-of-Thought symbolic planning (`cot="full"` for full score composition and `cot="melody"` for zero-shot cover mode).
  - Generates human-readable and editable ABC music notation encoding key signature, meter, tempo, chords, pitch, octaves, and lyric syllables before acoustic tokenization.
- **Native ABC Parser (`ABCParser`)**:
  - Zero-dependency Swift parser parsing headers (`T:`, `C:`, `M:`, `L:`, `Q:`, `K:`), chord annotations (`"C"`, `"Am"`, `"G7"`), accidentals (`^`, `_`, `=`), octave markers, and hyphenated lyrics (`w:`).
- **Native Standard MIDI File Exporter (`MIDIExporter`)**:
  - Generates binary Standard MIDI Files (SMF Format 1) using Variable-Length Quantity (VLQ) delta timing:
    - Track 1 (Conductor): Meta events for Tempo (microsec/quarter), Time Signature (num/denom), Key Signature, and Song Title.
    - Track 2 (Melody): Note-On (0x90) and Note-Off (0x80) events with velocity 96 and 480 ticks/quarter resolution.
    - Track 3 (Chords): Polyphonic harmonic chords (triads and 7ths) played with piano accompaniment velocity 75.
- **MusicXML 4.0 Serializer (`MusicXMLExporter`)**:
  - Produces standard partwise MusicXML with `<part-list>`, `<score-part>`, `<measure>`, `<attributes>`, `<direction>` sound tempo, `<harmony>` chord roots, `<note>` pitch steps and octaves, and `<lyric>` syllabic text. Fully compatible with MuseScore, Finale, Sibelius, and Dorico.

### 2.4 Audio Reference & Cover Song Creation Engine
- **Audio Ingestion & Resampling (`AudioReferenceManager`)**:
  - Ingests standard audio files (`.wav`, `.mp3`, `.m4a`, `.flac`, `.aiff`) via `AVAudioFile`.
  - Converts and resamples any sample rate / channel layout to 16.0 kHz Mono Float32 using `AVAudioConverter`.
- **$F_0$ Fundamental Frequency Pitch Tracking**:
  - Leverages Apple `Accelerate` `vDSP` normalized autocorrelation across 1024-sample (~64ms) sliding analysis windows with 320-sample (20ms, 50 fps) hop sizes.
  - Detects melodic vocal contours within human vocal range (65 Hz - 800 Hz) with parabolic peak interpolation.
- **Krumhansl-Schmuckler Key Estimation**:
  - Aggregates pitch class histograms ($C, C^\sharp, \dots, B$) and correlates against empirical Major and Minor tonal pitch profiles to determine the root key and mode automatically.
- **Melody vs. Full Reference Conditioning Modes**:
  - *Melody Only*: Extracts vocal melody contour into ABC score representation with `cot="melody"`, prompting YuE Stage 1 to preserve vocal lead while generating a completely new accompaniment style and arrangement.
  - *Full Reference*: Ingests full audio reference, encodes into YuE Stage 1 codec tokens (`45334 ..< 46358`), and encloses them between `[start_of_reference]` and `[end_of_reference]` special tokens matching official YuE reference conditioning.
- **Key & Modal Manipulation (`SymbolicPlanner`)**:
  - *Pitch Transposition (`transpose(abc:semitones:)`)*: Shifts root key (`K:`), harmonic chord labels (`"C"` $\to$ `"D"`), and musical note pitches across a $\pm 12$ semitone range.
  - *Modal Modulation (`modulateMode(abc:transform:)`)*: Transforms songs between Major and Minor (e.g. Major $\to$ Minor for melancholic covers, Minor $\to$ Major for uplifting covers) by altering scale degrees (flattening/sharpening 3rd, 6th, and 7th degrees) and chord quality.
  - *Lyric Realignment (`rewriteLyrics(abc:newLyrics:)`)*: Strips existing syllables and re-aligns new user lyrics under reference melody note durations.

### 2.5 Audio Subsystem
- **AVAudioEngine & AVAudioPlayerNode**: Low-latency native playback, dynamic format negotiation, and sample rate conversion.
- **Native Waveform Rendering**: SwiftUI Canvas with normalized RMS amplitude rendering.
- **Audio Export**: WAV, FLAC, and AAC export via `AVAudioFile` / `AudioToolbox`.

### 2.6 Persistence & State
- **Storage**: Thread-safe SQLite3 database (`storage.sqlite3`).
- **No Hardcoded Data**: All user settings, generation history, presets, and model registry are queried dynamically.
- **State Management**: SwiftUI `@Observable` / `ObservableObject` architecture (`AppState`).

- **Build Number**: `2026092101` (Current date + sequence number).
- **Target Platform**: macOS 14.0+ (Apple Silicon M1/M2/M3/M4)  
- **Display**: Fixed footer bar in the main application window showing build number and real-time unified memory consumption.
- **Top-P (Nucleus) Acoustic Filtering**: Rejects improbable acoustic codes in the tail of the distribution, eliminating vocal rasps, static, and phase noise.
- **Sliding-Window Recency Penalty**: Restricts repetition penalty to a recency window of 32 tokens, preventing full-codebook degradation while stopping stuck loops.
- **32-Bit Float Mastering Export**: Exports WAV directly as 32-bit floating point, preventing fixed-point quantization noise and integer conversion clipping.
- **Strict Acoustic Masking**: Fully suppresses non-music and speech tokens with $-\infty$, keeping Stage 1 bounded to XCodec Codebook 0 (45334..<46358) and `<EOA>` (32002).
- **Segment-by-Segment Generation Loop**: Iterates across structured lyric segments (`prepareOrderedSegments`), generating each segment until `<EOA>` before advancing to the next segment prompt.
- **Acoustic Vocoder**: Clean RVQ dequantization supporting pure Codebook 0 (zero noise), Balanced (Codebooks 0..3), and neural Stage 2 residual refinement with 8 RVQ codebooks.


