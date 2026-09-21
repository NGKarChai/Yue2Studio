# YuE Native macOS Studio - User Guide

## 1. Quick Start
### Building & Running
From the terminal in the project directory:
```bash
# Option 1: Open the local application bundle directly (recommended)
open Yue2Studio.app

# Option 2: Run via Swift Package Manager
swift run Yue2Studio
```
No installation to `/Applications` is required. The binary runs directly from the project folder.

## 2. Interface Overview
- **Sidebar**:
  - **Studio**: Main creative workspace with genre tags, lyrics editor, and generation controls.
  - **Models**: Weight directory configuration, status check, and downloader.
  - **Library**: Historical generation archive with instant playback and export options.
  - **Settings**: Audio device output, default inference precision (4-bit / 8-bit / 16-bit), and memory management options.
- **Footer**:
  - Displays the current Build Number (`2026092101`), active model directory, and real-time unified memory usage.

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

## 5. Audio Reference & Cover Song Creation Studio

YuE2 Studio provides native audio track reference conditioning and cover creation tools:

### 5.1 Uploading Audio References
- Click **Upload Reference Audio Track** in the Cover Studio card or drag-and-drop any audio file (`.wav`, `.mp3`, `.m4a`, `.flac`, `.aiff`).
- The app automatically resamples the input to 16.0 kHz Float32 and uses Apple `Accelerate` `vDSP` normalized autocorrelation to track pitch contours ($F_0$) and detect the key signature.

### 5.2 Conditioning Modes
- **Melody Only (Vocal)**: Extracts the vocal melody line into a clean ABC score and conditions YuE Stage 1 using `cot="melody"`. The vocal melody is preserved while the instrumental accompaniment, genre, rhythm, and arrangement are completely transformed according to your prompt.
- **Full Reference (Song)**: Encodes the full audio track into Stage 1 reference codec tokens (`[start_of_reference] ... [end_of_reference]`), guiding YuE to capture overall acoustic timbre, vocal nuance, and arrangement from the original.

### 5.3 Key & Modal Manipulation
- **Semitone Pitch Transposition**: Use the slider or `-` / `+` buttons to shift the key signature, chords, and melody up or down by $\pm 12$ semitones. Perfect for adapting a vocal melody to a different singer's range (e.g. female to male vocal range).
- **Major $\leftrightarrow$ Minor Modal Modulation**:
  - `Major -> Minor (Melancholic)`: Flattens the 3rd, 6th, and 7th scale degrees and transforms major chords to minor triads (`C` $\to$ `Cm`, `G` $\to$ `Gm`), turning uplifting pop songs into moody, melancholic ballads.
  - `Minor -> Major (Uplifting)`: Elevates minor melodies into bright, triumphant major keys.
- **Extract Melody to Score**: Transcribes detected audio pitches into editable ABC notation and interactive sheet music.
- **Align Lyrics to Melody**: Strips previous lyrics and syllabically aligns your new structured lyrics under each melodic note.

## 6. YuE2 Symbolic Planning & Sheet Music Score

YuE2 introduces **Symbolic Planning**, which separates musical composition from acoustic rendering:

### 6.1 Composition Modes
Select your desired mode using the **Composition & Planning Mode** picker in the Studio tab:
1. **Symbolic Plan (Full Score)**: Plans melody, chord progression, key signature, tempo, and rhythm in standard **ABC notation** before synthesizing acoustic latents.
2. **Zero-Shot Cover** *(Recommended for Covers)*: Uses your reference melody or custom ABC score and prompts YuE2 to arrange and sing a cover in any target genre or vocal style.
3. **Direct Audio (Fast)**: Bypasses symbolic planning and generates acoustic audio directly.

### 6.2 Musical Notes Viewer & Sheet Music
In **Symbolic Plan** or **Zero-Shot Cover** mode:
- **Sheet Music View**: Renders the musical score visually:
  - Displays Key Signature, Meter / Time Signature (e.g. 4/4), and Tempo (BPM).
  - Shows chord symbols (e.g., `"C"`, `"G"`, `"Am"`, `"F"`) placed above measures.
  - Displays melodic notes with pitch steps (A–G), sharps (♯), flats (♭), octaves, note durations, rests, and aligned lyrical syllables.
- **ABC Code Editor**: Switch to the **ABC Code** tab to edit the raw ABC score directly. Changes are automatically updated in the visual score and fed into the audio synthesizer.

## 7. Exporting Musical Notes
Click the **Export Notes** menu in the Score header to export the composition to standard file formats:
- **Export MIDI (`.mid`)**:
  - Standard MIDI File (SMF Format 1) with Conductor Track (Tempo, Meter, Key), Melodic Lead Track (480 ticks/quarter resolution), and Polyphonic Chord Accompaniment.
  - Ready for import into Logic Pro, GarageBand, Ableton Live, FL Studio, or Pro Tools.
- **Export MusicXML (`.musicxml`)**:
  - Standard MusicXML 4.0 file format compatible with MuseScore, Sibelius, Finale, and Dorico.
- **Export ABC Score (`.abc`)**:
  - Plaintext ABC music score format for easy sharing, archival, and web notation.

## 8. Audio Playback and Export
- Once generation finishes, the song appears in the **Waveform Player**.
- Use the scrubber to seek anywhere in the audio track.
- Click **Export Audio** to save the synthesized track as `.wav` (Lossless 44.1kHz / 24-bit).
