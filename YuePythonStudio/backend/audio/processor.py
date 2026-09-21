import numpy as np
import soundfile as sf
from pathlib import Path
from typing import Tuple, Optional

class AudioProcessor:
    @staticmethod
    def adjust_stereo_width(vocal: np.ndarray, inst: np.ndarray, stereo_width: float = 0.5) -> np.ndarray:
        """
        Mix vocal and instrumental tracks with adjustable stereo panoramic width.
        vocal: 1D array (mono)
        inst: 1D array (mono)
        stereo_width: 0.0 (Pure Mono) to 1.0 (Full Stereo)
        Returns: 2D array of shape (2, N) for [Left, Right] channels.
        """
        # Ensure 1D mono arrays
        if vocal.ndim > 1:
            vocal = vocal.squeeze()
            if vocal.ndim > 1:
                vocal = vocal.flatten()
        if inst.ndim > 1:
            inst = inst.squeeze()
            if inst.ndim > 1:
                inst = inst.flatten()

        # Ensure equal length
        min_len = min(len(vocal), len(inst))
        v = vocal[:min_len]
        i = inst[:min_len]

        # Mono mix
        mono_vocal = v
        mono_inst = i

        if stereo_width <= 0.01:
            # Centered mono
            left = (mono_vocal + mono_inst) * 0.707
            right = left
        else:
            # Vocal sits firmly in phantom center
            v_left = mono_vocal * 0.707
            v_right = mono_vocal * 0.707

            # Instrumental has mild stereo panning based on width
            pan = min(max(stereo_width, 0.0), 1.0)
            # Create decorrelated or Haas/panned instrumental stereo image
            i_left = mono_inst * (0.707 + 0.25 * pan)
            i_right = mono_inst * (0.707 - 0.25 * pan)

            left = v_left + i_left
            right = v_right + i_right

        mix = np.stack([left, right], axis=0)
        return mix

    @staticmethod
    def apply_mastering_limiter(audio: np.ndarray, target_peak_dbfs: float = -2.0) -> np.ndarray:
        """
        Applies a soft-knee peak limiter and normalizes to target_peak_dbfs.
        Eliminates inter-sample clipping and harsh distortion.
        audio: shape (channels, samples) or (samples,)
        """
        audio = audio.astype(np.float32)
        peak = np.max(np.abs(audio))
        if peak < 1e-6:
            return audio

        target_linear = 10.0 ** (target_peak_dbfs / 20.0)

        # Soft saturation curve (tanh soft-knee)
        threshold = 0.8
        normalized = audio / peak
        over_threshold = np.abs(normalized) > threshold

        # Apply smooth compression above threshold
        processed = normalized.copy()
        if np.any(over_threshold):
            sign = np.sign(normalized[over_threshold])
            mag = np.abs(normalized[over_threshold])
            compressed = threshold + (1.0 - threshold) * np.tanh((mag - threshold) / (1.0 - threshold))
            processed[over_threshold] = sign * compressed

        # Scale to target peak
        final_peak = np.max(np.abs(processed))
        if final_peak > 0:
            processed = processed * (target_linear / final_peak)

        return np.clip(processed, -target_linear, target_linear)

    @staticmethod
    def export_wav(audio: np.ndarray, output_path: Path, sample_rate: int = 44100, subtype: str = "PCM_24") -> Path:
        """
        Exports audio array to WAV file.
        audio: shape (samples,) or (channels, samples)
        """
        output_path = Path(output_path)
        output_path.parent.mkdir(parents=True, exist_ok=True)

        if audio.ndim == 2:
            # soundfile expects (samples, channels)
            data_to_write = audio.T if audio.shape[0] <= 2 else audio
        elif audio.ndim > 2:
            data_to_write = audio.reshape(audio.shape[0], -1).T
        else:
            data_to_write = audio

        sf.write(str(output_path), data_to_write, sample_rate, subtype=subtype)
        return output_path
