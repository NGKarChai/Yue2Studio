# Yue2Studio 🎵

**Native macOS Full-Song AI Music Generation Studio powered by Apple Silicon & MLX Swift**

[![Platform: macOS 14.0+](https://img.shields.io/badge/Platform-macOS%2014.0%2B-blue.svg)](#)
[![Hardware: Apple Silicon](https://img.shields.io/badge/Hardware-Apple%20Silicon%20(M1%2FM2%2FM3%2FM4)-black.svg)](#)
[![Engine: MLX Swift](https://img.shields.io/badge/Engine-MLX%20Swift%20%2F%20Metal-orange.svg)](#)
[![Build: 2026092502](https://img.shields.io/badge/Build-2026092502-brightgreen.svg)](#)
[![License: Apache 2.0 / MIT](https://img.shields.io/badge/License-Commercial%20Friendly-green.svg)](#)

---

## Overview

**Yue2Studio** is a standalone, native macOS application designed for high-fidelity, full-song AI music creation. Built with SwiftUI and **MLX Swift**, it runs locally on Apple Silicon unified memory with **ZERO Python dependencies** required during inference.

Yue2Studio exclusively utilizes the **YuE2-3B Continuous Flow Matching** architecture coupled with a **48 kHz Stability AI Oobleck VAE decoder**. 

> [!NOTE]
> **Why YuE2-3B Only?**  
> The legacy YuE v1 architecture (7B Stage 1 + 1B Stage 2 autoregressive models + 16 kHz X-Codec) is **not used** in this project because it does not perform well on Mac hardware (excessive memory pressure, slow multi-token autoregressive generation times, and phase distortion). YuE2-3B slashes memory usage to ~2.66 GB (8-bit) / ~4.3 GB (BF16), executes with sub-realtime synthesis speed (< 1.0x RTF), and outputs pristine 48.0 kHz floating-point stereo audio.

---

## 📦 Model Source URLs & Weight Acquisition

Yue2Studio exclusively uses the official **YuE2-3B** weights hosted on Hugging Face:

| Component | Architecture | Hugging Face Repository | Source URL | Size |
| :--- | :--- | :--- | :--- | :--- |
| **YuE2-3B Generator** | Qwen3 AR + Continuous Flow Matching (NAR) | `vanch007/mlx-Yue2-3B` | [https://huggingface.co/vanch007/mlx-Yue2-3B](https://huggingface.co/vanch007/mlx-Yue2-3B) | ~5.2 GB |
| **YuE2 48kHz VAE Decoder** | Stability AI 48 kHz Continuous Audio VAE | `m-a-p/YuE2-Vae` | [https://huggingface.co/m-a-p/YuE2-Vae](https://huggingface.co/m-a-p/YuE2-Vae) | ~506 MB |

### Download via `huggingface-cli`:
```bash
# 1. Download YuE2-3B MLX weights (8-bit AR + BF16 NAR flow matching)
huggingface-cli download vanch007/mlx-Yue2-3B --local-dir Models/yue2-3b

# 2. Download YuE2 48kHz Oobleck VAE decoder
huggingface-cli download m-a-p/YuE2-Vae --local-dir Models/yue2-vae
```

### In-App Download
You can also download weights directly inside the application using the integrated **Model Manager** with live progress tracking, speed calculation, and SHA-256 integrity verification.

---

## 🚀 Key Features

- **Pure Native Execution**: Swift 5.10 + Apple MLX Metal backend running directly on Apple Silicon GPUs without Python subprocesses or Docker.
- **Continuous Flow Matching ODE**: Midpoint Euler solver for continuous acoustic latent trajectories with 8-step (Draft) or 32-step (Studio Master) modes.
- **48.0 kHz Floating-Point Stereo**: Direct decoding via Stability AI Oobleck VAE with SnakeBeta activations.
- **Structured Songwriting**: Full lyrical arrangement using structural tags (`[verse]`, `[chorus]`, `[bridge]`, `[intro]`, `[outro]`).
- **Interactive ABC Score Editor**: Real-time sheet music transcription, key transposition, and SVG musical notation rendering.
- **Symbolic Exporters**: Instant export to standard **MIDI** (.mid) and **MusicXML** (.musicxml) for DAWs (Logic Pro, Ableton Live, Cubase).
- **Cover Studio**: Reference audio acoustic feature extraction, pitch transposition, and timbre matching.
- **Local SQLite Persistence**: Zero hardcoded settings; all presets, models, and history records are preserved in `storage.sqlite3`.

---

## 🛠 Quick Start & Installation

### Option 1: Standalone DMG Installer
1. Mount the disk image (`Yue2Studio-2026092302.dmg` or `Yue2Studio.dmg`).
2. Drag `Yue2Studio.app` into `/Applications`.
3. Open `Applications` and launch `Yue2Studio`.

### Option 2: Build & Run from Source (Xcode / Terminal)
```bash
# Clone the repository
git clone https://github.com/NGKarChai/Yue2Studio.git
cd Yue2Studio

# Run the native macOS application via Swift PM
swift run Yue2Studio
```

---

## 📚 Documentation

Detailed documentation is available in the [`Docs/`](Docs/) directory:
- [**User Guide**](Docs/USER_GUIDE.md): Complete guide to prompt engineering, lyric structuring, sampling parameters, and DMG installation.
- [**Model Setup Guide**](Docs/MODEL_SETUP.md): Directory structures, model formats, and weight downloading instructions.
- [**Native Architecture Specification**](Docs/YUE2_3B_NATIVE_ARCHITECTURE.md): Mathematical and pipeline breakdown of YuE2-3B Flow Matching & Oobleck VAE.
- [**System Architecture**](Docs/ARCHITECTURE.md): Core component topology, memory benchmarks, and SQLite database schema.

---

## 📜 Build & Compliance

- **Current Build**: `2026092302`
- **Target OS**: macOS 14.0+ (Sonoma) / macOS 15.0+ (Sequoia)
- **Architecture**: Apple Silicon (arm64)
- **Licensing**: All dependencies are open-source and free for commercial use.
