#!/usr/bin/env python3
"""
Automated Test Suite for YuePythonStudio
"""
import sys
import os
import re
import unittest
import numpy as np
from pathlib import Path

# Add YuePythonStudio to sys.path
BASE_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(BASE_DIR))

from backend import BUILD_NUMBER, __version__
from backend.config import StudioConfig
from backend.database.db import DatabaseManager
from backend.database.repository import SettingsRepository, PresetsRepository, HistoryRepository
from backend.symbolic.abc_parser import ABCParser
from backend.symbolic.planner import SymbolicPlanner
from backend.symbolic.midi_exporter import MIDIExporter
from backend.symbolic.musicxml_exporter import MusicXMLExporter
from backend.audio.processor import AudioProcessor
from backend.audio.reference_analyzer import AudioReferenceAnalyzer
from backend.pipeline.mmtokenizer import _MMSentencePieceTokenizer
from backend.pipeline.stage3_vocoder import Stage3Vocoder

class TestYuePythonStudio(unittest.TestCase):
    def test_01_build_number(self):
        self.assertEqual(BUILD_NUMBER, "2026092101")
        print(f"✓ Test 1 Passed: Build number is {BUILD_NUMBER}")

    def test_02_database_connection(self):
        db = DatabaseManager()
        presets_repo = PresetsRepository(db)
        settings_repo = SettingsRepository(db)
        history_repo = HistoryRepository(db)

        genres = presets_repo.get_genres()
        self.assertGreaterEqual(len(genres), 1)

        lyrics = presets_repo.get_lyrics()
        self.assertGreaterEqual(len(lyrics), 1)

        settings = settings_repo.get_all()
        self.assertIn("default_temperature", settings)

        records = history_repo.list_all()
        self.assertIsInstance(records, list)
        print(f"✓ Test 2 Passed: SQLite Database queried {len(genres)} genres, {len(lyrics)} lyrics presets, {len(records)} history records")

    def test_03_tokenizer(self):
        models_dir = Path(__file__).resolve().parent.parent / "Models"
        tok_path = models_dir / "stage1" / "tokenizer.model"
        self.assertTrue(tok_path.exists())

        tokenizer = _MMSentencePieceTokenizer(str(tok_path))
        self.assertEqual(tokenizer.soa, 32001)
        self.assertEqual(tokenizer.eoa, 32002)

        tokens = tokenizer.tokenize("Test melody prompt")
        self.assertIsInstance(tokens, list)
        self.assertGreater(len(tokens), 0)
        print(f"✓ Test 3 Passed: SentencePiece mmtokenizer loaded (vocab: {tokenizer.vocab_size})")

    def test_04_symbolic_and_exporters(self):
        abc = (
            "X:1\n"
            "T:Test Song\n"
            "M:4/4\n"
            "L:1/8\n"
            "Q:1/4=120\n"
            "K:C\n"
            '| "C" C2 E2 G2 c2 | "Am" A2 c2 e2 a2 |\n'
        )
        parsed = ABCParser.parse(abc)
        self.assertEqual(parsed["headers"]["title"], "Test Song")
        self.assertEqual(len(parsed["measures"]), 2)

        # Transpose
        transposed = SymbolicPlanner.transpose_abc(abc, 2) # C -> D
        self.assertIn("K:D", transposed)

        # Export MIDI
        midi_out = Path("/tmp/test_export.mid")
        MIDIExporter.export(abc, midi_out)
        self.assertTrue(midi_out.exists())
        self.assertGreater(midi_out.stat().st_size, 100)

        # Export MusicXML
        xml_out = Path("/tmp/test_export.musicxml")
        MusicXMLExporter.export(abc, xml_out)
        self.assertTrue(xml_out.exists())
        self.assertGreater(xml_out.stat().st_size, 100)
        print("✓ Test 4 Passed: Symbolic parsing, transposition (+2st), MIDI and MusicXML export verified")

    def test_05_audio_processor(self):
        sr = 16000
        dur = 1.0 # 1 sec
        t = np.linspace(0, dur, int(sr * dur), endpoint=False)
        vocal = np.sin(2 * np.pi * 440 * t).astype(np.float32)
        inst = np.sin(2 * np.pi * 220 * t).astype(np.float32)

        stereo = AudioProcessor.adjust_stereo_width(vocal, inst, stereo_width=0.6)
        self.assertEqual(stereo.shape[0], 2)
        self.assertEqual(stereo.shape[1], len(vocal))

        mastered = AudioProcessor.apply_mastering_limiter(stereo, target_peak_dbfs=-2.0)
        peak_linear = np.max(np.abs(mastered))
        target_linear = 10.0 ** (-2.0 / 20.0)
        self.assertLessEqual(peak_linear, target_linear + 1e-4)

        wav_path = Path("/tmp/test_audio.wav")
        AudioProcessor.export_wav(mastered, wav_path, sample_rate=sr)
        self.assertTrue(wav_path.exists())
        print("✓ Test 5 Passed: Audio stereo spatial widener, soft-knee limiter (-2dBFS peak), and WAV export verified")

    def test_06_frontend_prefix_rule(self):
        index_html = (BASE_DIR / "frontend" / "index.html").read_text()
        # Find all id="..."
        ids = re.findall(r'id=["\']([^"\']+)["\']', index_html)
        self.assertGreater(len(ids), 10)
        for el_id in ids:
            self.assertTrue(el_id.startswith("yue_"), f"Element ID '{el_id}' violates Rule 9 (must start with 'yue_')")
        print(f"✓ Test 6 Passed: All {len(ids)} HTML DOM element IDs strictly adhere to the 'yue_' prefix (Rule 9)")

if __name__ == "__main__":
    unittest.main()
