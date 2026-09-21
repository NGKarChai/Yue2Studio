import re
from typing import List, Dict, Any, Optional

class ABCParser:
    @staticmethod
    def parse(abc_text: str) -> Dict[str, Any]:
        """
        Parses ABC text into a structured score object.
        """
        headers: Dict[str, str] = {
            "title": "Untitled Composition",
            "meter": "4/4",
            "unit_length": "1/8",
            "tempo": "120",
            "key": "C"
        }

        body_lines: List[str] = []
        lyric_lines: List[str] = []

        for line in abc_text.splitlines():
            line = line.strip()
            if not line or line.startswith("%"):
                continue
            if len(line) >= 2 and line[1] == ":":
                prefix = line[0].upper()
                content = line[2:].strip()
                if prefix == "T":
                    headers["title"] = content
                elif prefix == "M":
                    headers["meter"] = content
                elif prefix == "L":
                    headers["unit_length"] = content
                elif prefix == "Q":
                    # e.g. 1/4=120 or 120
                    numbers = re.findall(r"\d+", content)
                    if numbers:
                        headers["tempo"] = numbers[-1]
                elif prefix == "K":
                    headers["key"] = content
                elif prefix == "W":
                    lyric_lines.append(content)
            else:
                body_lines.append(line)

        # Parse measures and notes from body_lines
        measures: List[Dict[str, Any]] = []
        current_measure: Dict[str, Any] = {"chord": "", "notes": []}

        # Tokenize notes, chords, and bar lines
        # Pattern matches:
        # 1. Chords: "[A-G][b#]?[m|maj|7|min|dim]?" inside quotes like "C", "Am"
        # 2. Bar lines: |
        # 3. Notes: [=^_]?[a-gA-G][,']?[0-9]*
        token_pattern = r'("[^"]+")|(\|)|([=^_]?[a-gA-G][,\']?[0-9]*)'

        measure_index = 1
        for line in body_lines:
            tokens = re.finditer(token_pattern, line)
            for m in tokens:
                chord_token = m.group(1)
                bar_token = m.group(2)
                note_token = m.group(3)

                if chord_token:
                    current_measure["chord"] = chord_token.strip('"')
                elif bar_token:
                    if current_measure["notes"] or current_measure.get("chord"):
                        current_measure["measure_number"] = measure_index
                        measures.append(current_measure)
                        measure_index += 1
                        current_measure = {"chord": "", "notes": []}
                elif note_token:
                    current_measure["notes"].append({
                        "symbol": note_token,
                        "pitch": note_token[0].upper(),
                        "octave": 5 if note_token[0].islower() else 4
                    })

        if current_measure["notes"]:
            current_measure["measure_number"] = measure_index
            measures.append(current_measure)

        return {
            "headers": headers,
            "measures": measures,
            "lyrics": lyric_lines,
            "raw_abc": abc_text
        }
