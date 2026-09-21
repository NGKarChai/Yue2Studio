import re
from typing import Optional, Dict, Any, List

SEMITONE_SCALE = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

class SymbolicPlanner:
    @staticmethod
    def transpose_abc(abc_text: str, semitones: int) -> str:
        """
        Transposes an ABC notation string by semitones (+-12).
        Transposes key K:, chords "... ", and melody notes.
        """
        if semitones == 0:
            return abc_text

        def shift_pitch(name: str) -> str:
            upper = name.upper()
            if upper in SEMITONE_SCALE:
                idx = SEMITONE_SCALE.index(upper)
                new_idx = (idx + semitones) % 12
                return SEMITONE_SCALE[new_idx]
            return name

        result_lines = []
        for line in abc_text.splitlines():
            if line.startswith("K:"):
                # Key transposition
                match = re.match(r"K:\s*([A-G][b#]?)(.*)", line)
                if match:
                    root = match.group(1)
                    suffix = match.group(2)
                    new_root = shift_pitch(root)
                    result_lines.append(f"K:{new_root}{suffix}")
                else:
                    result_lines.append(line)
            else:
                # Transpose chords e.g. "C", "Am", "G7"
                def chord_repl(match):
                    full_chord = match.group(1)
                    inner = full_chord.strip('"')
                    root_match = re.match(r"([A-G][b#]?)(.*)", inner)
                    if root_match:
                        r = root_match.group(1)
                        s = root_match.group(2)
                        new_r = shift_pitch(r)
                        return f'"{new_r}{s}"'
                    return full_chord

                transposed_line = re.sub(r'("[A-G][b#]?[^"]*")', chord_repl, line)
                result_lines.append(transposed_line)

        return "\n".join(result_lines)

    @staticmethod
    def modulate_mode(abc_text: str, target_mode: str = "minor") -> str:
        """
        Modulates mode between Major and Minor.
        Major -> Minor: changes K: from Major to minor, changes major triads to minor.
        """
        result_lines = []
        for line in abc_text.splitlines():
            if line.startswith("K:"):
                match = re.match(r"K:\s*([A-G][b#]?)(.*)", line)
                if match:
                    root = match.group(1)
                    if target_mode.lower() == "minor":
                        result_lines.append(f"K:{root}m")
                    else:
                        result_lines.append(f"K:{root}")
                else:
                    result_lines.append(line)
            else:
                # Replace Major chords with Minor chords if target is minor
                if target_mode.lower() == "minor":
                    def chord_mod(m):
                        c = m.group(1).strip('"')
                        if len(c) == 1 or (len(c) == 2 and c[1] in ("#", "b")):
                            return f'"{c}m"'
                        return m.group(1)
                    result_lines.append(re.sub(r'("[A-G][b#]?")', chord_mod, line))
                else:
                    result_lines.append(line)

        return "\n".join(result_lines)

    @staticmethod
    def realign_lyrics(abc_text: str, new_lyrics: str) -> str:
        """
        Strips previous lyrics (w: lines) and syllabically aligns new lyrics.
        """
        words = new_lyrics.split()
        clean_lines = [l for l in abc_text.splitlines() if not l.startswith("w:") and not l.startswith("W:")]

        # Insert w: under music lines
        result_lines = []
        word_idx = 0
        for line in clean_lines:
            result_lines.append(line)
            if not line.startswith("%") and not (len(line) >= 2 and line[1] == ":") and line.strip():
                # Music line, attach a slice of words
                if word_idx < len(words):
                    take = min(8, len(words) - word_idx)
                    chunk = " ".join(words[word_idx:word_idx + take])
                    result_lines.append(f"w: {chunk}")
                    word_idx += take

        return "\n".join(result_lines)

    @staticmethod
    def build_symbolic_cot_prompt(genre_tags: str, lyrics: str, cot_mode: str = "full", custom_abc: Optional[str] = None) -> str:
        """
        Formats Chain-of-Thought (CoT) prompt for YuE2 symbolic guidance.
        """
        if cot_mode == "off":
            return ""

        if custom_abc and custom_abc.strip():
            score_body = custom_abc.strip()
        else:
            # Generate default melodic sketch
            score_body = (
                "X:1\n"
                f"T:Plan for {genre_tags[:30]}\n"
                "M:4/4\n"
                "L:1/8\n"
                "Q:1/4=120\n"
                "K:C\n"
                '| "C" C2 E2 G2 c2 | "Am" A2 c2 e2 a2 | "F" F2 A2 c2 f2 | "G" G2 B2 d2 g2 |\n'
            )

        if cot_mode == "melody":
            # Strip chord symbols for cover / melody guidance
            score_body = re.sub(r'"[^"]+"', '', score_body)

        return f"[start_of_score]\n{score_body}\n[end_of_score]\n"
