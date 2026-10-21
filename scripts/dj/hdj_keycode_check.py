"""Check the Harmonic DJ key-code rule on every key in the library DB.

Rule: the number of a keycode (e.g. `10P`) is the Camelot number of the mode's parent
major scale; the letter is the mode (B ionian, D dorian, P phrygian, L lydian,
M mixolydian, A aeolian). In / out keys (`a->b`) are checked separately.

Read-only: the DB is copied to a temporary file and opened with `?immutable=1`.
"""

import argparse
import shutil
import sqlite3
import tempfile
from collections import defaultdict
from pathlib import Path

PC = {"C": 0, "Db": 1, "C#": 1, "D": 2, "Eb": 3, "D#": 3, "E": 4, "F": 5, "Gb": 6, "F#": 6,
      "G": 7, "Ab": 8, "G#": 8, "A": 9, "Bb": 10, "A#": 10, "B": 11}
OFFSET = {"ionian": 0, "dorian": 2, "phrygian": 4, "lydian": 5, "mixolydian": 7, "aeolian": 9}


def camelot_major(pc):
    """Camelot number of the major key with pitch class pc."""
    return (pc * 7 % 12 + 7) % 12 + 1


def main():
    """Print rule matches, mismatches and the letter used per mode."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("hdj_db", help="Harmonic DJ harmonic-dj.sqlite")
    args = parser.parse_args()

    with tempfile.TemporaryDirectory() as tmp:
        copy = Path(tmp) / "hdj.sqlite"
        shutil.copyfile(args.hdj_db, copy)
        con = sqlite3.connect(f"file:{copy}?immutable=1", uri=True)
        rows = con.execute("select key, keycode from track_key_profiles where key is not null")
        ok, bad, letters = 0, 0, defaultdict(set)
        for key, code in rows:
            for part, part_code in zip(key.split("->"), code.split("->")):
                root, mode = part.split()
                expected = camelot_major((PC[root.rstrip("m")] - OFFSET[mode]) % 12)
                letters[mode].add(part_code[-1])
                if int(part_code[:-1]) == expected:
                    ok += 1
                else:
                    bad += 1
                    print(f"MISMATCH {part} {part_code} (expected {expected})")
        con.close()
    print(f"{ok} ok, {bad} mismatches; letters: "
          + ", ".join(f"{m} {''.join(sorted(v))}" for m, v in sorted(letters.items())))


if __name__ == "__main__":
    main()
