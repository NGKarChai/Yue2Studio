# Model Setup & Weight Acquisition Guide

## 1. Directory Structure
The application looks for model weights in the path configured in the **Model Manager** (Settings). By default, this is the `./Models` directory inside the project root:

```
Models/
├── yue2-3b/               # YuE2-3B Native Flow Matching Engine (Recommended)
│   ├── config.json
│   ├── qwen.tiktoken
│   ├── ar-8bit.safetensors
│   └── nar-bf16.safetensors
├── yue2-vae/              # YuE2 48 kHz Oobleck VAE Decoder
│   ├── config.json
│   └── model.safetensors
│
│  # Legacy YuE v1 Models (Optional / Fallback)
├── stage1/
│   ├── config.json
│   ├── tokenizer.json
│   ├── tokenizer_config.json
│   └── model.safetensors
├── stage2/
│   ├── config.json
│   └── model.safetensors
└── xcodec/
    ├── config.json
    └── decoder.safetensors
```

## 2. Supported Formats
- **SafeTensors** (`.safetensors`): Native binary weight tensor format, zero-copy memory mapped.
- **MLX Quantized Weights**: 8-bit (`ar-8bit.safetensors`) and BF16 (`nar-bf16.safetensors`) weights optimized for Apple Silicon Metal acceleration.

## 3. Official Model Source URLs

### 3.1 Primary Native Engine: YuE2-3B (Flow Matching + 48kHz VAE)
YuE2-3B is the native generation engine running via MLX Swift on Apple Silicon:

| Component | Hugging Face Repository | Source URL | Size |
| :--- | :--- | :--- | :--- |
| **YuE2-3B Generator** | `vanch007/mlx-Yue2-3B` | [https://huggingface.co/vanch007/mlx-Yue2-3B](https://huggingface.co/vanch007/mlx-Yue2-3B) | ~5.2 GB |
| **YuE2 48kHz VAE** | `m-a-p/YuE2-Vae` | [https://huggingface.co/m-a-p/YuE2-Vae](https://huggingface.co/m-a-p/YuE2-Vae) | ~506 MB |

#### Download via `huggingface-cli`:
```bash
# Download YuE2-3B MLX weights
huggingface-cli download vanch007/mlx-Yue2-3B --local-dir Models/yue2-3b

# Download YuE2 48kHz Oobleck VAE weights
huggingface-cli download m-a-p/YuE2-Vae --local-dir Models/yue2-vae
```

---

### 3.2 Legacy / Reference Engine: YuE v1 (7B + 1B + X-Codec)
Original discrete autoregressive weights by Multimodal Art Projection (MAP):

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

## 4. In-App Model Management & Custom Paths
1. Launch **Yue2Studio**.
2. Navigate to **Model Manager** in the left sidebar.
3. You can either:
   - Click **Download** directly within the app (automatic background progress tracking).
   - Click **Browse...** to select any external SSD, local directory, or network volume containing pre-downloaded weights.
4. The path is automatically saved in the local SQLite database (`app_settings` table).
5. The application will scan and validate all required weights in the selected folder.
