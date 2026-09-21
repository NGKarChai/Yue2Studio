import re
import os
import gc
import torch
import numpy as np
from pathlib import Path
from typing import Optional, List, Tuple, Callable, Dict, Any
from einops import rearrange
from transformers import AutoModelForCausalLM, LogitsProcessor, LogitsProcessorList

from .codec_manipulator import CodecManipulator
from .mmtokenizer import _MMSentencePieceTokenizer

class BlockTokenRangeProcessor(LogitsProcessor):
    def __init__(self, start_id: int, end_id: int):
        self.blocked_token_ids = list(range(start_id, end_id))

    def __call__(self, input_ids: torch.Tensor, scores: torch.Tensor) -> torch.Tensor:
        scores[:, self.blocked_token_ids] = -float("inf")
        return scores

class Stage1Generator:
    def __init__(self, models_dir: Path, device: torch.device):
        self.models_dir = Path(models_dir)
        self.device = device
        self.model: Optional[AutoModelForCausalLM] = None
        self.current_model_path: Optional[str] = None
        self.codectool = CodecManipulator("xcodec", 0, 1)

    @staticmethod
    def detect_language(text: str) -> str:
        """Detects whether text contains CJK Chinese characters or Latin English."""
        cjk_count = len(re.findall(r'[\u4e00-\u9fff]', text))
        return "zh" if cjk_count > 4 else "en"

    @staticmethod
    def split_lyrics(lyrics: str) -> List[str]:
        # Match section tags like [verse 1], [pre-chorus], [chorus], [outro]
        pattern = r"\[([\w\s\-]+)\](.*?)(?=\[|\Z)"
        segments = re.findall(pattern, lyrics, re.DOTALL)
        if not segments:
            # If no tags, check for multi-stanza lyrics separated by blank lines
            paras = [p.strip() for p in lyrics.strip().split('\n\n') if p.strip()]
            if len(paras) > 1:
                labels = ["verse 1", "chorus", "verse 2", "bridge", "outro"]
                result = []
                for idx, p in enumerate(paras):
                    label = labels[idx] if idx < len(labels) else f"section {idx+1}"
                    result.append(f"[{label}]\n{p}\n\n")
                return result
            # Single block fallback
            return [f"[verse]\n{lyrics.strip()}\n\n"]
        return [f"[{seg[0].strip()}]\n{seg[1].strip()}\n\n" for seg in segments]

    def select_model_dir(self, lyric_language: str) -> Path:
        if lyric_language == "zh":
            zh_dir = self.models_dir / "stage1-zh"
            if zh_dir.exists():
                return zh_dir
            parent_zh = self.models_dir.parent / "Models" / "stage1-zh"
            if parent_zh.exists():
                return parent_zh

        en_dir = self.models_dir / "stage1"
        if en_dir.exists():
            return en_dir
        parent_en = self.models_dir.parent / "Models" / "stage1"
        if parent_en.exists():
            return parent_en

        raise FileNotFoundError(f"Stage 1 model directory not found in {self.models_dir}")

    def load_model(self, lyric_language: str = "en"):
        target_dir = self.select_model_dir(lyric_language)
        path_str = str(target_dir)

        if self.model is not None and self.current_model_path == path_str:
            return

        self.unload_model()

        self.model = AutoModelForCausalLM.from_pretrained(
            path_str,
            torch_dtype=torch.bfloat16 if self.device.type != "cpu" else torch.float32,
            attn_implementation="sdpa"
        )
        self.model.to(self.device)
        self.model.eval()
        self.current_model_path = path_str

    def unload_model(self):
        if self.model is not None:
            del self.model
            self.model = None
            self.current_model_path = None
            gc.collect()
            if self.device.type == "mps":
                torch.mps.empty_cache()
            elif self.device.type == "cuda":
                torch.cuda.empty_cache()

    def generate_coarse_tokens(
        self,
        genre_tags: str,
        lyrics: str,
        tokenizer: _MMSentencePieceTokenizer,
        max_new_tokens: int = 1200,
        temperature: float = 0.9,
        top_p: float = 0.95,
        cfg_scale: float = 1.5,
        repetition_penalty: float = 1.1,
        cot_prompt: str = "",
        audio_prompt_tokens: Optional[np.ndarray] = None,
        progress_callback: Optional[Callable[[float, str], None]] = None
    ) -> Tuple[np.ndarray, np.ndarray]:
        """
        Generates interleaved dual-track coarse audio tokens (Codebook 0).
        Returns: (vocals_cb0, inst_cb0) as 1D numpy arrays.
        """
        lang = self.detect_language(lyrics)
        self.load_model(lang)
        assert self.model is not None

        structured_segments = self.split_lyrics(lyrics)
        full_lyrics = "".join(structured_segments)

        # Canonical YuE prompt template
        prompt_texts = [f"Generate music from the given lyrics segment by segment.\n[Genre] {genre_tags}\n{full_lyrics}"]
        prompt_texts += structured_segments

        raw_output: Optional[torch.Tensor] = None
        block_list = LogitsProcessorList([
            BlockTokenRangeProcessor(0, 32002),
            BlockTokenRangeProcessor(32016, 32017)
        ])

        start_of_segment = tokenizer.tokenize('[start_of_segment]')
        end_of_segment = tokenizer.tokenize('[end_of_segment]')

        total_segments = len(prompt_texts) - 1
        # Distribute target tokens proportionally across lyric segments (100 tokens = 1 second)
        seg_target = max(300, max_new_tokens // max(1, total_segments))
        seg_max_tokens = min(3500, int(seg_target * 1.15))
        # Enforce minimum tokens per segment so the model does NOT stop after 1-2 seconds
        seg_min_tokens = max(150, int(seg_target * 0.70))

        for i, segment_text in enumerate(prompt_texts):
            if i == 0:
                continue

            section_text = segment_text.replace('[start_of_segment]', '').replace('[end_of_segment]', '')
            guidance_scale = cfg_scale if i <= 1 else max(1.1, cfg_scale * 0.8)

            if i == 1:
                head_id = tokenizer.tokenize(prompt_texts[0])
                if cot_prompt:
                    head_id = head_id + tokenizer.tokenize(f"\n{cot_prompt}")
                prompt_ids = head_id + start_of_segment + tokenizer.tokenize(section_text) + [tokenizer.soa] + self.codectool.sep_ids
                if audio_prompt_tokens is not None and len(audio_prompt_tokens) > 0:
                    prompt_ids = prompt_ids + list(audio_prompt_tokens)
                prompt_tensor = torch.as_tensor(prompt_ids, dtype=torch.long, device=self.device).unsqueeze(0)
                input_ids = prompt_tensor
            else:
                prompt_ids = end_of_segment + start_of_segment + tokenizer.tokenize(section_text) + [tokenizer.soa] + self.codectool.sep_ids
                seg_input = torch.as_tensor(prompt_ids, dtype=torch.long, device=self.device).unsqueeze(0)
                input_ids = torch.cat([raw_output, seg_input], dim=1)

            # Context window boundary check (16,384 tokens maximum position embeddings)
            max_context = 16384 - seg_max_tokens - 1
            if input_ids.shape[-1] > max_context:
                input_ids = input_ids[:, -max_context:]

            if progress_callback:
                frac = (i - 1) / max(1, total_segments)
                progress_callback(frac, f"Generating Segment {i}/{total_segments} (~{seg_target//100}s, CFG={guidance_scale:.1f})...")

            with torch.no_grad():
                output_seq = self.model.generate(
                    input_ids=input_ids,
                    max_new_tokens=seg_max_tokens,
                    min_new_tokens=seg_min_tokens,
                    do_sample=True,
                    top_p=top_p,
                    temperature=temperature,
                    repetition_penalty=repetition_penalty,
                    eos_token_id=tokenizer.eoa,
                    pad_token_id=tokenizer.eoa,
                    logits_processor=block_list,
                    guidance_scale=guidance_scale
                )

                if output_seq[0][-1].item() != tokenizer.eoa:
                    tensor_eoa = torch.as_tensor([[tokenizer.eoa]], device=self.device)
                    output_seq = torch.cat((output_seq, tensor_eoa), dim=1)

            if i > 1:
                raw_output = torch.cat([raw_output, seg_input, output_seq[:, input_ids.shape[-1]:]], dim=1)
            else:
                raw_output = output_seq

        if progress_callback:
            progress_callback(1.0, "Stage 1 Complete. Extracting dual-track tokens...")

        # Parse SOA and EOA tokens
        ids = raw_output[0].cpu().numpy()
        soa_idx = np.where(ids == tokenizer.soa)[0].tolist()
        eoa_idx = np.where(ids == tokenizer.eoa)[0].tolist()

        if len(soa_idx) == 0 or len(eoa_idx) == 0:
            raise ValueError("No audio segments were generated by the model.")

        vocals_list = []
        inst_list = []

        for k in range(min(len(soa_idx), len(eoa_idx))):
            codec_ids = ids[soa_idx[k] + 1 : eoa_idx[k]]
            if len(codec_ids) == 0:
                continue
            if codec_ids[0] == 32016: # <xcodec>
                codec_ids = codec_ids[1:]

            # Make length even for 2-track interleaving (vocal, inst)
            codec_ids = codec_ids[: 2 * (codec_ids.shape[0] // 2)]
            if len(codec_ids) < 2:
                continue

            v_track = self.codectool.ids2npy(rearrange(codec_ids, "(n b) -> b n", b=2)[0])
            i_track = self.codectool.ids2npy(rearrange(codec_ids, "(n b) -> b n", b=2)[1])

            vocals_list.append(v_track)
            inst_list.append(i_track)

        if not vocals_list or not inst_list:
            raise ValueError("Failed to extract valid dual-track tokens from generated output.")

        vocals = np.concatenate(vocals_list, axis=1)
        inst = np.concatenate(inst_list, axis=1)

        return vocals, inst
