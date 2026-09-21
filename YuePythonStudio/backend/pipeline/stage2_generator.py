import os
import copy
import torch
import numpy as np
from pathlib import Path
from typing import Optional, List, Callable
from collections import Counter
from transformers import AutoModelForCausalLM, LogitsProcessor, LogitsProcessorList

from .codec_manipulator import CodecManipulator
from .mmtokenizer import _MMSentencePieceTokenizer

class BlockTokenRangeProcessor(LogitsProcessor):
    def __init__(self, start_id: int, end_id: int):
        self.blocked_token_ids = list(range(start_id, end_id))

    def __call__(self, input_ids: torch.Tensor, scores: torch.Tensor) -> torch.Tensor:
        scores[:, self.blocked_token_ids] = -float("inf")
        return scores

class Stage2Generator:
    def __init__(self, models_dir: Path, device: torch.device):
        self.models_dir = Path(models_dir)
        self.device = device
        self.model: Optional[AutoModelForCausalLM] = None
        self.codectool = CodecManipulator("xcodec", 0, 1)
        self.codectool_stage2 = CodecManipulator("xcodec", 0, 8)

    def load_model(self):
        if self.model is not None:
            return

        stage2_dir = self.models_dir / "stage2"
        if not stage2_dir.exists():
            stage2_dir = self.models_dir.parent / "Models" / "stage2"

        if not stage2_dir.exists():
            raise FileNotFoundError(f"Stage 2 model directory not found: {stage2_dir}")

        self.model = AutoModelForCausalLM.from_pretrained(
            str(stage2_dir),
            torch_dtype=torch.bfloat16 if self.device.type != "cpu" else torch.float32,
            attn_implementation="sdpa"
        )
        self.model.to(self.device)
        self.model.eval()

    def unload_model(self):
        if self.model is not None:
            del self.model
            self.model = None
            if self.device.type == "mps":
                torch.mps.empty_cache()
            elif self.device.type == "cuda":
                torch.cuda.empty_cache()

    def generate_stage2_track(
        self,
        cb0_track: np.ndarray,
        tokenizer: _MMSentencePieceTokenizer,
        quality: str = "full",
        progress_callback: Optional[Callable[[float, str], None]] = None
    ) -> np.ndarray:
        """
        cb0_track: 1D or 2D array of coarse codebook 0 tokens (shape: (1, T) or (T,))
        quality: 'draft', 'balanced', 'full'
        Returns: 2D numpy array of shape (8, T) containing all 8 codebooks
        """
        if cb0_track.ndim == 1:
            cb0_track = cb0_track[np.newaxis, :]

        total_frames = cb0_track.shape[1]

        # Fast Draft mode: Bypasses Stage 2 inference
        if quality.lower() == "draft":
            if progress_callback:
                progress_callback(1.0, "Draft mode: Codebook 0 direct audio synthesis")
            # Create 8-codebook matrix where codebook 0 is the coarse tokens and 1..7 are zeros or replicated
            full_codes = np.zeros((8, total_frames), dtype=np.int16)
            full_codes[0] = cb0_track[0]
            for c in range(1, 8):
                full_codes[c] = (cb0_track[0] // (c + 1)) % 1024
            return full_codes

        self.load_model()
        assert self.model is not None

        # Prepare tokens
        codec_ids = self.codectool.offset_tok_ids(
            cb0_track.copy(),
            global_offset=self.codectool.global_offset,
            codebook_size=self.codectool.codebook_size,
            num_codebooks=self.codectool.num_codebooks
        ).astype(np.int32)

        # 6-second (300-frame) chunking
        batch_size = 4
        output_duration = total_frames // 50 // 6 * 6
        num_batches = output_duration // 6

        output_tokens: List[np.ndarray] = []
        block_list = LogitsProcessorList([
            BlockTokenRangeProcessor(0, 46358),
            BlockTokenRangeProcessor(53526, tokenizer.vocab_size)
        ])

        target_residuals = 3 if quality.lower() == "balanced" else 7

        def run_chunk(prompt_chunk: np.ndarray) -> np.ndarray:
            chunk_len = prompt_chunk.shape[1]
            prompt_ids = np.concatenate([
                np.array([tokenizer.soa, tokenizer.stage_1]),
                prompt_chunk.flatten(),
                np.array([tokenizer.stage_2])
            ]).astype(np.int32)[np.newaxis, ...]

            prompt_tensor = torch.as_tensor(prompt_ids).to(self.device)
            chunk_tensor = torch.as_tensor(prompt_chunk).to(self.device)
            base_len = prompt_tensor.shape[-1]

            for frame_idx in range(chunk_len):
                cb_curr = chunk_tensor[:, frame_idx:frame_idx+1]
                prompt_tensor = torch.cat([prompt_tensor, cb_curr], dim=1)

                with torch.no_grad():
                    stage2_out = self.model.generate(
                        input_ids=prompt_tensor,
                        min_new_tokens=target_residuals,
                        max_new_tokens=target_residuals,
                        eos_token_id=tokenizer.eoa,
                        pad_token_id=tokenizer.eoa,
                        logits_processor=block_list
                    )
                prompt_tensor = stage2_out

            return prompt_tensor[0].cpu().numpy()[base_len:]

        # Process main chunks
        processed_frames = 0
        while processed_frames < total_frames:
            end_frame = min(processed_frames + 300, total_frames)
            chunk = codec_ids[:, processed_frames:end_frame]
            out_chunk = run_chunk(chunk)
            output_tokens.append(out_chunk)
            processed_frames = end_frame

            if progress_callback:
                frac = min(1.0, processed_frames / total_frames)
                progress_callback(frac, f"Stage 2 refinement: {processed_frames}/{total_frames} frames")

        combined = np.concatenate(output_tokens, axis=0)

        # Decode stage2 token ids back to RVQ 8 codebooks
        unoffset_codes = self.codectool_stage2.ids2npy(combined)

        # Sanitize codes
        fixed = copy.deepcopy(unoffset_codes)
        for i in range(fixed.shape[0]):
            for j in range(fixed.shape[1]):
                if fixed[i, j] < 0 or fixed[i, j] > 1023:
                    fixed[i, j] = 0

        # If balanced mode, pad remaining codebooks 4..7 with zeros
        if fixed.shape[0] < 8:
            padded = np.zeros((8, fixed.shape[1]), dtype=np.int16)
            padded[:fixed.shape[0]] = fixed
            return padded

        return fixed[:8]
