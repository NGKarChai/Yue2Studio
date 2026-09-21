import os
import sys
import torch
import numpy as np
from pathlib import Path
from typing import Optional, Tuple
from omegaconf import OmegaConf

# Ensure xcodec modules can be resolved
CURRENT_DIR = Path(__file__).resolve().parent
XCODEC_DIR = CURRENT_DIR.parent.parent / "xcodec_core"
if str(XCODEC_DIR) not in sys.path:
    sys.path.append(str(XCODEC_DIR))
    sys.path.append(str(XCODEC_DIR / "descriptaudiocodec"))
    sys.path.append(str(XCODEC_DIR / "RepCodec"))

from models.soundstream_hubert_new import SoundStream

class Stage3Vocoder:
    def __init__(self, models_dir: Path, device: torch.device):
        self.models_dir = Path(models_dir)
        self.device = device
        self.codec_model: Optional[SoundStream] = None

    def load_model(self):
        if self.codec_model is not None:
            return

        xcodec_dir = self.models_dir / "xcodec"
        config_path = xcodec_dir / "final_ckpt" / "config.yaml"
        ckpt_path = xcodec_dir / "final_ckpt" / "ckpt_00360000.pth"

        if not config_path.exists():
            # Fallback
            config_path = self.models_dir.parent / "Models" / "xcodec" / "final_ckpt" / "config.yaml"
            ckpt_path = self.models_dir.parent / "Models" / "xcodec" / "final_ckpt" / "ckpt_00360000.pth"

        if not config_path.exists() or not ckpt_path.exists():
            raise FileNotFoundError(f"X-Codec config or checkpoint not found in {xcodec_dir}")

        config = OmegaConf.load(str(config_path))
        model = eval(config.generator.name)(**config.generator.config)
        param_dict = torch.load(str(ckpt_path), map_location="cpu", weights_only=False)
        model.load_state_dict(param_dict["codec_model"], strict=False)
        model.to(self.device)
        model.eval()
        self.codec_model = model

    def decode_codes_to_audio(self, codes: np.ndarray) -> np.ndarray:
        """
        codes: numpy array of shape (8, T) or (1, 8, T) containing RVQ acoustic codes [0..1023]
        Returns: 1D numpy array of float32 audio samples at 16000 Hz.
        """
        self.load_model()
        assert self.codec_model is not None

        if codes.ndim == 2:
            # codes is (8, T) -> unsqueeze to (1, 8, T) -> permute to (8, 1, T)
            codes_tensor = torch.as_tensor(codes.astype(np.int16), dtype=torch.long).unsqueeze(0).permute(1, 0, 2)
        elif codes.ndim == 3 and codes.shape[0] == 1:
            # (1, 8, T) -> permute to (8, 1, T)
            codes_tensor = torch.as_tensor(codes.astype(np.int16), dtype=torch.long).permute(1, 0, 2)
        else:
            codes_tensor = torch.as_tensor(codes.astype(np.int16), dtype=torch.long)

        codes_tensor = codes_tensor.to(self.device)

        with torch.no_grad():
            wav = self.codec_model.decode(codes_tensor)
            # wav shape: (1, 1, samples)
            wav_np = wav.detach().cpu().squeeze().numpy().astype(np.float32)
            if wav_np.ndim > 1:
                wav_np = wav_np.flatten()

        return wav_np

    def unload_model(self):
        if self.codec_model is not None:
            del self.codec_model
            self.codec_model = None
            if self.device.type == "mps":
                torch.mps.empty_cache()
            elif self.device.type == "cuda":
                torch.cuda.empty_cache()
