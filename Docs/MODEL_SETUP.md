# Model Setup & Weight Acquisition Guide

## 1. Directory Structure
The application looks for model weights in the path configured in the **Model Manager** (Settings). By default, this is the `./Models` directory inside the project root:

```
Models/
├── stage1/
│   ├── config.json
│   ├── tokenizer.json
│   ├── tokenizer_config.json
│   └── model.safetensors (or quantized weights)
├── stage2/
│   ├── config.json
│   └── model.safetensors
└── xcodec/
    ├── config.json
    └── decoder.safetensors (or xcodec_decoder.bin)
```

## 2. Supported Formats
- **SafeTensors** (`.safetensors`): Native binary weight tensor format, zero-copy memory mapped.
- **MLX Quantized Weights**: 4-bit (`q4_0`, `q4_1`, `affine_quantized`) or 8-bit weights for fast Apple Silicon Metal matrix multiplication.

## 3. Official Model Sources
The official YuE weights by Multimodal Art Projection (MAP) are hosted on Hugging Face:
- Stage 1 (7B English / Chinese): `m-a-p/YuE-s1-7B-anneal-en-cot` or `m-a-p/YuE-s1-7B-anneal-zh-cot`
- Stage 2 (1B Refiner): `m-a-p/YuE-s2-1B-general`
- Neural Codec: `m-a-p/xcodec_mini_infer`

## 4. Setting a Custom Model Path
1. Open the application.
2. Navigate to **Model Manager** in the left sidebar.
3. Click **Browse...** to select any external SSD, local directory, or network volume.
4. The path is automatically saved in the local SQLite database (`app_settings` table).
5. The application will scan and validate all required stage weights in the selected folder.
