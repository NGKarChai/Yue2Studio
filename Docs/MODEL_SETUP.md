# Model Setup & Weight Acquisition Guide

## 1. Supported Architecture: YuE2-3B Only
Yue2Studio exclusively uses the **YuE2-3B** engine (Continuous Flow Matching + 48 kHz Stability AI Oobleck VAE).

> [!NOTE]
> The legacy YuE v1 engine (7B Stage 1, 1B Stage 2, and 16 kHz X-Codec) is **not used** because of poor performance on macOS (excessive memory pressure, long multi-token autoregressive generation times, and phase distortion). YuE2-3B provides sub-realtime synthesis (< 1.0x RTF) and 48 kHz floating-point stereo quality with ~2.66 GB (8-bit) / ~4.3 GB (BF16) memory consumption.

---

## 2. Directory Structure
The application looks for model weights in the path configured in the **Model Manager** (Settings). By default, this is the `./Models` directory inside the project root:

```
Models/
├── yue2-3b/               # YuE2-3B Native Flow Matching Engine (MLX Swift)
│   ├── config.json
│   ├── qwen.tiktoken
│   ├── ar-8bit.safetensors
│   └── nar-bf16.safetensors
└── yue2-vae/              # YuE2 48 kHz Oobleck VAE Decoder
    ├── config.json
    └── model.safetensors
```

---

## 3. Official Model Source URLs

All model weights are hosted on Hugging Face:

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

---

## 4. In-App Model Management & Custom Paths
1. Launch **Yue2Studio**.
2. Navigate to **Model Manager** in the left sidebar.
3. You can either:
   - Click **Download** directly within the app (automatic background progress tracking, speed calculation, and verification).
   - Click **Browse...** to select any external SSD, local directory, or network volume containing pre-downloaded weights.
4. The path is automatically saved in the local SQLite database (`app_settings` table).
5. The application will scan and validate all required weights in the selected folder.
