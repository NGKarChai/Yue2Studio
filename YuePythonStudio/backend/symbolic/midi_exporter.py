import mido
from pathlib import Path
from typing import Dict, Any, List
from .abc_parser import ABCParser

# Pitch name to base MIDI note
NOTE_PITCH_MAP = {
    "C": 60, "C#": 61, "DB": 61, "D": 62, "D#": 63, "EB": 63, "E": 64,
    "F": 65, "F#": 66, "GB": 66, "G": 67, "G#": 68, "AB": 68, "A": 69,
    "A#": 70, "BB": 70, "B": 71
}

# Chord triad intervals
CHORD_INTERVALS = {
    "": [0, 4, 7],         # Major
    "M": [0, 4, 7],        # Major
    "MIN": [0, 3, 7],      # Minor
    "7": [0, 4, 7, 10],    # Dominant 7th
    "MAJ7": [0, 4, 7, 11], # Major 7th
    "M7": [0, 3, 7, 10],   # Minor 7th
    "DIM": [0, 3, 6],      # Diminished
}

class MIDIExporter:
    @staticmethod
    def export(abc_text: str, output_path: Path) -> Path:
        parsed = ABCParser.parse(abc_text)
        bpm = int(parsed["headers"].get("tempo", 120))
        tempo = mido.bpm2tempo(bpm)

        mid = mido.MidiFile(type=1, ticks_per_beat=480)

        # Track 0: Conductor (Tempo & Meta)
        conductor_track = mido.MidiTrack()
        mid.tracks.append(conductor_track)
        conductor_track.append(mido.MetaMessage('track_name', name='Conductor', time=0))
        conductor_track.append(mido.MetaMessage('set_tempo', tempo=tempo, time=0))
        conductor_track.append(mido.MetaMessage('time_signature', numerator=4, denominator=4, time=0))
        conductor_track.append(mido.MetaMessage('end_of_track', time=0))

        # Track 1: Melody Lead
        melody_track = mido.MidiTrack()
        mid.tracks.append(melody_track)
        melody_track.append(mido.MetaMessage('track_name', name='Vocal Melody', time=0))
        melody_track.append(mido.Message('program_change', program=0, channel=0, time=0)) # Acoustic Grand

        # Track 2: Chord Accompaniment
        chord_track = mido.MidiTrack()
        mid.tracks.append(chord_track)
        chord_track.append(mido.MetaMessage('track_name', name='Chords', time=0))
        chord_track.append(mido.Message('program_change', program=4, channel=1, time=0)) # Electric Piano 1

        ticks_per_eighth = 240
        measure_ticks = 480 * 4

        for measure in parsed["measures"]:
            chord_name = measure.get("chord", "")
            notes = measure.get("notes", [])

            # Emit chord on chord_track (plays at start of measure)
            if chord_name:
                root_char = chord_name[0].upper()
                accidental = ""
                suffix = ""
                if len(chord_name) > 1 and chord_name[1] in ("#", "b"):
                    accidental = chord_name[1].upper()
                    suffix = chord_name[2:].upper()
                else:
                    suffix = chord_name[1:].upper()

                root_key = (root_char + accidental).upper()
                base_midi = NOTE_PITCH_MAP.get(root_key, 60) - 12 # Octave lower for chords
                intervals = CHORD_INTERVALS.get(suffix, [0, 4, 7])
                chord_pitches = [base_midi + iv for iv in intervals]

                # Note on for chord notes
                for i, p in enumerate(chord_pitches):
                    chord_track.append(mido.Message('note_on', note=p, velocity=75, channel=1, time=0))
                # Hold chord for measure
                chord_track.append(mido.Message('note_off', note=chord_pitches[0], velocity=64, channel=1, time=measure_ticks))
                for p in chord_pitches[1:]:
                    chord_track.append(mido.Message('note_off', note=p, velocity=64, channel=1, time=0))
            else:
                # Rest on chord track
                pass

            # Emit melody notes on melody_track
            for note in notes:
                symbol = note["symbol"]
                clean_sym = symbol.lstrip("=^_")
                pitch_char = clean_sym[0].upper()
                octave_shift = 12 if clean_sym[0].islower() else 0
                acc_shift = 1 if "^" in symbol else (-1 if "_" in symbol else 0)

                midi_pitch = NOTE_PITCH_MAP.get(pitch_char, 60) + octave_shift + acc_shift

                # Duration calculation
                dur_factor = 1
                for ch in symbol:
                    if ch.isdigit():
                        dur_factor = int(ch)
                        break
                note_duration = ticks_per_eighth * dur_factor

                melody_track.append(mido.Message('note_on', note=midi_pitch, velocity=96, channel=0, time=0))
                melody_track.append(mido.Message('note_off', note=midi_pitch, velocity=64, channel=0, time=note_duration))

        melody_track.append(mido.MetaMessage('end_of_track', time=0))
        chord_track.append(mido.MetaMessage('end_of_track', time=0))

        output_path = Path(output_path)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        mid.save(str(output_path))
        return output_path
