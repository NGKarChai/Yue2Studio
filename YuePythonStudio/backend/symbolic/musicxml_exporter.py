import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Dict, Any
from .abc_parser import ABCParser

class MusicXMLExporter:
    @staticmethod
    def export(abc_text: str, output_path: Path) -> Path:
        parsed = ABCParser.parse(abc_text)
        title = parsed["headers"].get("title", "YuE Music Composition")
        tempo = parsed["headers"].get("tempo", "120")

        root = ET.Element("score-partwise", version="4.0")

        # Work / Title
        work = ET.SubElement(root, "work")
        ET.SubElement(work, "work-title").text = title

        # Part List
        part_list = ET.SubElement(root, "part-list")
        score_part = ET.SubElement(part_list, "score-part", id="P1")
        ET.SubElement(score_part, "part-name").text = "Vocal Lead"

        # Part P1
        part = ET.SubElement(root, "part", id="P1")

        for i, measure_data in enumerate(parsed["measures"]):
            measure = ET.SubElement(part, "measure", number=str(i + 1))

            # Attributes in Measure 1
            if i == 0:
                attributes = ET.SubElement(measure, "attributes")
                divisions = ET.SubElement(attributes, "divisions")
                divisions.text = "2" # 1/8 note = 1 division, quarter = 2

                key = ET.SubElement(attributes, "key")
                ET.SubElement(key, "fifths").text = "0"
                ET.SubElement(key, "mode").text = "major"

                time = ET.SubElement(attributes, "time")
                ET.SubElement(time, "beats").text = "4"
                ET.SubElement(time, "beat-type").text = "4"

                clef = ET.SubElement(attributes, "clef")
                ET.SubElement(clef, "sign").text = "G"
                ET.SubElement(clef, "line").text = "2"

                # Direction / Tempo
                direction = ET.SubElement(measure, "direction", placement="above")
                direction_type = ET.SubElement(direction, "direction-type")
                metronome = ET.SubElement(direction_type, "metronome")
                ET.SubElement(metronome, "beat-unit").text = "quarter"
                ET.SubElement(metronome, "per-minute").text = str(tempo)

            # Harmony / Chord
            chord_name = measure_data.get("chord", "")
            if chord_name:
                harmony = ET.SubElement(measure, "harmony")
                root_tag = ET.SubElement(harmony, "root")
                ET.SubElement(root_tag, "root-step").text = chord_name[0].upper()
                kind = ET.SubElement(harmony, "kind")
                kind.text = "minor" if "m" in chord_name else "major"

            # Notes
            notes = measure_data.get("notes", [])
            for note_data in notes:
                symbol = note_data["symbol"]
                clean = symbol.lstrip("=^_")
                step_char = clean[0].upper()
                octave_num = 5 if clean[0].islower() else 4

                dur_val = 1
                for c in symbol:
                    if c.isdigit():
                        dur_val = int(c)
                        break

                note_el = ET.SubElement(measure, "note")
                pitch_el = ET.SubElement(note_el, "pitch")
                ET.SubElement(pitch_el, "step").text = step_char
                ET.SubElement(pitch_el, "octave").text = str(octave_num)
                ET.SubElement(note_el, "duration").text = str(dur_val)
                ET.SubElement(note_el, "type").text = "quarter" if dur_val >= 2 else "eighth"

        output_path = Path(output_path)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        tree = ET.ElementTree(root)
        ET.indent(tree, space="  ", level=0)
        tree.write(str(output_path), encoding="utf-8", xml_declaration=True)
        return output_path
