# YuE2-3B Native macOS Architecture Specification

## 1. Executive Summary
Yue2Studio natively supports the **YuE2-3B** architecture (`vanch007/mlx-Yue2-3B` & `m-a-p/YuE2-Vae`).
This engine runs directly in **MLX Swift** on Apple Silicon unified memory with **ZERO Python runtime dependencies**.

Unlike YuE v1 (which uses 7B + 1B discrete autoregressive token models and a 16 kHz neural vocoder), YuE2-3B replaces Stage 2 and Stage 3 with **Continuous Flow Matching (NAR)** and a **Stability AI 48 kHz Oobleck VAE decoder**.

---

## 2. Architecture Comparison

| Pipeline Component | YuE v1 Engine | YuE2-3B Engine |
| :--- | :--- | :--- |
| **Model Size** | 7B (Stage 1) + 1B (Stage 2) | **3B unified parameter model** |
| **Quantized Memory Footprint** | ~5–10 GB | **~2.66 GB (8-bit) / ~4.3 GB (BF16)** |
| **Acoustic Synthesis** | Discrete Codebook Autoregression (7 Codebooks) | **Non-Autoregressive Continuous Flow Matching (NAR)** |
| **Solver Steps** | Thousands of discrete token generation steps | **8 Steps (Fast Mode) / 32 Steps (Studio Master)** |
| **Real-Time Factor (RTF)** | ~2.5–4.0x RTF | **< 1.0x RTF (Faster than real-time)** |
| **Audio Vocoder** | 16 kHz X-Codec RVQ + Vocos | **48.0 kHz Stability AI Oobleck VAE** |
| **Channels & Quality** | Mono upsampled to stereo | **Native 48 kHz Floating-Point Stereo** |

---

## 3. Core Engine Components in MLX Swift

### 3.1 Qwen3-based AR Planner (`YuE2ARModel.swift`)
- **Backbone**: 28 hidden layers, 2048 hidden dimension, 16 Query attention heads, 8 Key/Value attention heads (Grouped Query Attention).
- **Head Dimension**: 128 with Rotary Position Embeddings (RoPE $\theta = 1\,000\,000$).
- **Vocabulary**: 184,704 tokens.
- **Semantic Projection Slice**: Semantic token decoding mapped to indices `[151852:184621]`.
- **Planning**: Generates structured ABC notation scores and semantic acoustic tokens.

### 3.2 NAR Acoustic Flow Matching (`YuE2NARFlowMatching.swift`)
- **Latent Dimension**: 64 continuous latent channels running at 25 Hz.
- **Timestep Embedder**: 256-dimensional FP32 sinusoidal positional frequencies fed into a 2-layer SiLU MLP.
- **Sigmoid Timestep Warping**:
  $$\sigma(t) = \frac{1}{1 + e^{-t}}, \quad t_{\text{shifted}} = \frac{\text{shift} \cdot \sigma(t)}{1 + (\text{shift} - 1) \cdot \sigma(t)}$$
- **ODE Integration**:
  - Starts with pure Gaussian noise $x_0 \sim \mathcal{N}(0, I)$ of shape `[1, T, 64]`.
  - Midpoint Euler solver computes velocity evaluations $v_1$ and $v_2$ per step, advancing the continuous latent trajectory toward $t=0.0$.
  - Supports **32 steps** for studio master reproduction or **8 steps** for sub-realtime synthesis.

### 3.3 48 kHz Oobleck VAE Decoder (`OobleckVAEDecoder.swift`)
- **Architecture**: Port of the Stability AI continuous audio VAE (`m-a-p/YuE2-Vae`).
- **Activation**: Periodic `SnakeBeta` activation:
  $$f(x) = x + \frac{\sin^2(x \cdot e^\alpha)}{e^\beta + 10^{-9}}$$
- **Transposed Convolution Upsamplers**: Reverse strides `[8, 5, 4, 2]` upsampling 320x with exact odd-stride parity handling (`output_length = frames * stride - (stride % 2)`).
- **Output**: 48.0 kHz 32-bit floating-point stereo buffer converted directly into `AVAudioPCMBuffer` without disk serialization stalls.

---

## 4. How to Acquire & Use YuE2-3B Weights

1. Download or clone the Hugging Face repositories:
   ```bash
   # YuE2-3B Generator Weights (MLX converted)
   huggingface-cli download vanch007/mlx-Yue2-3B --local-dir Models/yue2-3b

   # YuE2 48kHz Oobleck VAE Decoder
   huggingface-cli download m-a-p/YuE2-Vae --local-dir Models/yue2-vae
   ```

2. Open **Yue2Studio.app**:
   - Go to **Model Manager** in the left sidebar.
   - Set **Selected Model Architecture** to **YuE2-3B (Flow Matching + Oobleck 48kHz)**.
   - Point the **YuE2-3B Weights** folder to `Models/yue2-3b`.
   - Point the **YuE2 48kHz VAE** folder to `Models/yue2-vae`.

3. Generate in the **Studio**:
   - Switch between **8 Steps** (for rapid drafting) and **32 Steps** (for master render) in the **Sampling & Inference** panel.
   - Click **Generate Music**.
