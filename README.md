# Yue2Studio 🎵

**Native macOS Full-Song AI Music Generation Studio powered by Apple Silicon & MLX Swift**

[![Platform: macOS 14.0+](https://img.shields.io/badge/Platform-macOS%2014.0%2B-blue.svg)](#)
[![Hardware: Apple Silicon](https://img.shields.io/badge/Hardware-Apple%20Silicon%20(M1%2FM2%2FM3%2FM4)-black.svg)](#)
[![Engine: MLX Swift](https://img.shields.io/badge/Engine-MLX%20Swift%20%2F%20Metal-orange.svg)](#)
[![Build: 2026092301](https://img.shields.io/badge/Build-2026092301-brightgreen.svg)](#)
[![License: Apache 2.0 / MIT](https://img.shields.io/badge/License-Commercial%20Friendly-green.svg)](#)

---

## Overview

**Yue2Studio** is a standalone, native macOS application designed for high-fidelity, full-song AI music creation. Built with SwiftUI and **MLX Swift**, it runs locally on Apple Silicon unified memory with **ZERO Python dependencies** required during inference.

The studio features the cutting-edge **YuE2-3B Continuous Flow Matching** engine paired with a **48 kHz Stability AI Oobleck VAE decoder**, delivering studio-quality vocal clarity, instrumental separation, and sub-realtime synthesis speeds (< 1.0x RTF).

---

## 📦 Model Source URLs & Weight Acquisition

Yue2Studio requires weights for inference. All supported models are freely accessible on Hugging Face:

### 1. Primary Engine: YuE2-3B (Flow Matching + 48 kHz VAE) — *Recommended*

This is the primary native engine for fast, high-fidelity 48 kHz stereo music generation.

| Component | Hugging Face Repository | Source URL | Size |
| :--- | :--- | :--- | :--- |
| **YuE2-3B Generator** | `vanch007/mlx-Yue2-3B` | [https://huggingface.co/vanch007/mlx-Yue2-3B](https://huggingface.co/vanch007/mlx-Yue2-3B) | ~5.2 GB |
| **YuE2 48kHz VAE Decoder** | `m-a-p/YuE2-Vae` | [https://huggingface.co/m-a-p/YuE2-Vae](https://huggingface.co/m-a-p/YuE2-Vae) | ~506 MB |

#### Download via `huggingface-cli`:
```bash
# 1. Download YuE2-3B MLX weights (8-bit AR + BF16 NAR)
huggingface-cli download vanch007/mlx-Yue2-3B --local-dir Models/yue2-3b

# 2. Download YuE2 48kHz Oobleck VAE weights
huggingface-cli download m-a-p/YuE2-Vae --local-dir Models/yue2-vae
```

> **Note**: You can also download weights directly inside the application using the integrated **Model Manager** with live progress tracking.

---

### 2. Legacy Engine: YuE v1 (7B + 1B + X-Codec) — *Optional*

The original discrete autoregressive token weights published by Multimodal Art Projection (MAP):

| Stage | Hugging Face Repository | Source URL |
| :--- | :--- | :--- |
| **Stage 1 (7B English)** | `m-a-p/YuE-s1-7B-anneal-en-cot` | [https://huggingface.co/m-a-p/YuE-s1-7B-anneal-en-cot](https://huggingface.co/m-a-p/YuE-s1-7B-anneal-en-cot) |
| **Stage 1 (7B Chinese)** | `m-a-p/YuE-s1-7B-anneal-zh-cot` | [https://huggingface.co/m-a-p/YuE-s1-7B-anneal-zh-cot](https://huggingface.co/m-a-p/YuE-s1-7B-anneal-zh-cot) |
| **Stage 2 (1B Refiner)** | `m-a-p/YuE-s2-1B-general` | [https://huggingface.co/m-a-p/YuE-s2-1B-general](https://huggingface.co/m-a-p/YuE-s2-1B-general) |
| **Stage 3 (X-Codec Mini)** | `m-a-p/xcodec_mini_infer` | [https://huggingface.co/m-a-p/xcodec_mini_infer](https://huggingface.co/m-a-p/xcodec_mini_infer) |

#### Download via `huggingface-cli`:
```bash
huggingface-cli download m-a-p/YuE-s1-7B-anneal-en-cot --local-dir Models/stage1
huggingface-cli download m-a-p/YuE-s2-1B-general --local-dir Models/stage2
huggingface-cli download m-a-p/xcodec_mini_infer --local-dir Models/xcodec
```

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
1. Mount the disk image (`Yue2Studio-2026092301.dmg` or `Yue2Studio.dmg`).
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

- **Current Build**: `2026092301`
- **Target OS**: macOS 14.0+ (Sonoma) / macOS 15.0+ (Sequoia)
- **Architecture**: Apple Silicon (arm64)
- **Licensing**: All dependencies are open-source and free for commercial use.
