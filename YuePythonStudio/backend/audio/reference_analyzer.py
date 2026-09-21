import numpy as np
import soundfile as sf
import librosa
from pathlib import Path
from typing import Dict, Any, List, Tuple

# Krumhansl-Schmuckler Key Profiles
MAJOR_PROFILE = np.array([6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88])
MINOR_PROFILE = np.array([6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17])
PITCH_NAMES = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]

class AudioReferenceAnalyzer:
    @staticmethod
    def load_audio_mono(audio_path: str, target_sr: int = 16000) -> Tuple[np.ndarray, int]:
        audio_path = str(audio_path)
        y, sr = librosa.load(audio_path, sr=target_sr, mono=True)
        return y, sr

    @classmethod
    def estimate_key(cls, y: np.ndarray, sr: int = 16000) -> Tuple[str, str, float]:
        """
        Estimates the musical key and mode (Major / Minor) using Krumhansl-Schmuckler key-finding.
        Returns: (root_note, mode, correlation_score)
        """
        chroma = librosa.feature.chroma_cqt(y=y, sr=sr)
        chroma_avg = np.mean(chroma, axis=1)

        norm_chroma = chroma_avg - np.mean(chroma_avg)
        std_chroma = np.std(chroma_avg)
        if std_chroma > 1e-6:
            norm_chroma /= std_chroma

        best_corr = -1.0
        best_key = "C"
        best_mode = "Major"

        for i in range(12):
            # Rotate major and minor profiles
            maj_rot = np.roll(MAJOR_PROFILE, i)
            maj_norm = (maj_rot - np.mean(maj_rot)) / np.std(maj_rot)
            maj_corr = np.dot(norm_chroma, maj_norm) / 12.0

            if maj_corr > best_corr:
                best_corr = maj_corr
                best_key = PITCH_NAMES[i]
                best_mode = "Major"

            min_rot = np.roll(MINOR_PROFILE, i)
            min_norm = (min_rot - np.mean(min_rot)) / np.std(min_rot)
            min_corr = np.dot(norm_chroma, min_norm) / 12.0

            if min_corr > best_corr:
                best_corr = min_corr
                best_key = PITCH_NAMES[i]
                best_mode = "Minor"

        return best_key, best_mode, float(best_corr)

    @classmethod
    def track_pitch_f0(cls, y: np.ndarray, sr: int = 16000) -> Tuple[np.ndarray, np.ndarray]:
        """
        Tracks fundamental frequency F0 using probabilistic YIN (pyin).
        Returns: (f0_values_hz, voiced_probabilities)
        """
        f0, voiced_flag, voiced_probs = librosa.pyin(
            y,
            fmin=librosa.note_to_hz('C2'),
            fmax=librosa.note_to_hz('C7'),
            sr=sr,
            frame_length=1024,
            hop_length=320 # 20ms frame = 50 fps
        )
        f0 = np.nan_to_num(f0, nan=0.0)
        return f0, voiced_probs

    @classmethod
    def transcribe_to_abc(cls, y: np.ndarray, sr: int = 16000, title: str = "Reference Melody") -> str:
        """
        Extracts vocal melodic pitch line into standardized ABC notation.
        """
        key, mode, _ = cls.estimate_key(y, sr)
        tempo, _ = librosa.beat.beat_track(y=y, sr=sr)
        bpm = int(round(float(np.atleast_1d(tempo)[0]))) if tempo is not None else 120
        if bpm < 50 or bpm > 200:
            bpm = 120

        f0, voiced_probs = cls.track_pitch_f0(y, sr)

        # Convert valid F0 frames to midi notes
        hop_sec = 320.0 / sr
        notes: List[Tuple[float, float, int]] = [] # (start_time, duration, midi_note)

        current_note = None
        start_time = 0.0

        for idx, freq in enumerate(f0):
            t = idx * hop_sec
            if freq > 65.0: # Human vocal lower bound
                midi = int(round(librosa.hz_to_midi(freq)))
                if current_note is None:
                    current_note = midi
                    start_time = t
                elif abs(midi - current_note) > 1: # Note change
                    dur = t - start_time
                    if dur >= 0.1: # Min 100ms
                        notes.append((start_time, dur, current_note))
                    current_note = midi
                    start_time = t
            else:
                if current_note is not None:
                    dur = t - start_time
                    if dur >= 0.1:
                        notes.append((start_time, dur, current_note))
                    current_note = None

        # Build ABC Score
        abc_lines = [
            f"X:1",
            f"T:{title}",
            f"M:4/4",
            f"L:1/8",
            f"Q:1/4={bpm}",
            f"K:{key}{'m' if mode == 'Minor' else ''}",
            "| "
        ]

        abc_pitch_map = {
            60: "C", 62: "D", 64: "E", 65: "F", 67: "G", 69: "A", 71: "B",
            72: "c", 74: "d", 76: "e", 77: "f", 79: "g", 81: "a", 83: "b"
        }

        note_str = ""
        bar_count = 0
        for _, dur, midi in notes[:40]: # First 40 notes for preview
            closest = min(abc_pitch_map.keys(), key=lambda k: abs(k - midi))
            p_sym = abc_pitch_map[closest]
            length_units = max(1, min(4, int(round(dur / 0.25))))
            len_suffix = str(length_units) if length_units > 1 else ""
            note_str += f"{p_sym}{len_suffix} "
            bar_count += length_units
            if bar_count >= 8:
                note_str += "| "
                bar_count = 0

        if not note_str.strip():
            note_str = "C2 D2 E2 G2 | A4 G4 |"

        abc_lines.append(note_str.strip())
        return "\n".join(abc_lines)

    @classmethod
    def analyze_audio_file(cls, filepath: str) -> Dict[str, Any]:
        """
        Full analysis pipeline for uploaded reference audio.
        """
        y, sr = cls.load_audio_mono(filepath)
        duration = float(len(y) / sr)
        key, mode, confidence = cls.estimate_key(y, sr)
        tempo, _ = librosa.beat.beat_track(y=y, sr=sr)
        bpm = int(round(float(np.atleast_1d(tempo)[0]))) if tempo is not None else 120
        abc = cls.transcribe_to_abc(y, sr, title=Path(filepath).stem)

        f0, _ = cls.track_pitch_f0(y, sr)
        # Downsample F0 for fast frontend visualization
        step = max(1, len(f0) // 200)
        f0_preview = [float(v) for v in f0[::step]]

        return {
            "duration_seconds": duration,
            "estimated_key": key,
            "estimated_mode": mode,
            "confidence": round(confidence, 3),
            "estimated_bpm": bpm,
            "abc_score": abc,
            "pitch_contour": f0_preview
        }
