"""Compare key and BPM analysis of Harmonic DJ, rekordbox and Beatport file names (T4).

Inputs:
  - a rekordbox collection XML **export** (File > Export Collection in xml format);
  - Harmonic DJ's library DB (`~/Library/APU Harmonic DJ/harmonic-dj.sqlite`);
  - the folder to compare (tracks are matched by absolute path, NFC-normalized).

Read-only: the HDJ DB is copied to a temporary file and opened with `?immutable=1`.

Key relations:
  same        root and major / minor equal
  relative    same Camelot number, other major / minor (e.g. Am vs C)
  same-scale  HDJ's mode has the same parent scale (HDJ keycode number = other's Camelot)
  parallel    same root, other major / minor (e.g. C vs Cm)
  adjacent    Camelot neighbour (+/-1), same letter
  other       anything else
HDJ modes map to major (ionian, lydian, mixolydian) or minor (aeolian, dorian, phrygian).
Beatport key / BPM come from file names like `…_<BPM>_<Key>_<Major|Minor>_<nn>.aiff`.
"""

import argparse
import re
import shutil
import sqlite3
import tempfile
import unicodedata
import urllib.parse
import xml.etree.ElementTree as ET
from collections import Counter, defaultdict
from pathlib import Path

PC = {
    "C": 0, "B#": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "Fb": 4, "F": 5,
    "E#": 5, "F#": 6, "Gb": 6, "G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10,
    "B": 11, "Cb": 11,
}
NAMES = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]
MINOR_MODES = {"aeolian", "dorian", "phrygian"}
RELATIONS = ["same", "relative", "same-scale", "parallel", "adjacent", "other"]


def nfc(path):
    """Return the path in Unicode NFC form."""
    return unicodedata.normalize("NFC", path)


def camelot(pc, minor):
    """Camelot number (1-12) of a major or minor key."""
    major_pc = (pc + 3) % 12 if minor else pc
    return (major_pc * 7 % 12 + 7) % 12 + 1


def parse_key(text):
    """Parse 'Cm', 'F#', or Camelot '5A' into (pitch class, minor); None if unknown."""
    text = (text or "").strip()
    match = re.fullmatch(r"(\d{1,2})([AB])", text)
    if match:
        number, minor = int(match[1]), match[2] == "A"
        major_pc = next(pc for pc in range(12) if camelot(pc, False) == number)
        return ((major_pc - 3) % 12 if minor else major_pc, minor)
    match = re.fullmatch(r"([A-G](?:#|b)?)(m|min|maj)?", text)
    return (PC[match[1]], match[2] in ("m", "min")) if match else None


def show(key):
    """Format (pc, minor) as e.g. 'Cm (5A)'."""
    if key is None:
        return "-"
    pc, minor = key
    return f"{NAMES[pc]}{'m' if minor else ''} ({camelot(pc, minor)}{'A' if minor else 'B'})"


def relation(a, b, a_parent=None):
    """Classify how key a relates to key b (see module docstring)."""
    if a is None or b is None:
        return None
    if a == b:
        return "same"
    if camelot(*a) == camelot(*b):
        return "relative"
    if a_parent is not None and a_parent == camelot(*b):
        return "same-scale"
    if a[0] == b[0]:
        return "parallel"
    if a[1] == b[1] and (camelot(*a) - camelot(*b)) % 12 in (1, 11):
        return "adjacent"
    return "other"


def bpm_relation(a, b):
    """Classify two BPM values as same (+/-0.5), half/double or other."""
    if not a or not b:
        return None
    if abs(a - b) <= 0.5:
        return "same"
    if abs(2 * a - b) <= 1 or abs(a - 2 * b) <= 1:
        return "half/double"
    return "other"


def beatport(path):
    """Key and BPM from a Beatport file name; (None, None) if absent."""
    match = re.search(r"_(\d+)_([A-G](?:b|#)?)_(Major|Minor)_\d+\.\w+$", path)
    if not match:
        return None, None
    return (PC[match[2]], match[3] == "Minor"), int(match[1])


def load_rekordbox(xml_path, folder):
    """Map NFC path -> (key, BPM) for rekordbox tracks inside folder."""
    tracks = {}
    for track in ET.parse(xml_path).getroot().iter("TRACK"):
        location = track.get("Location")
        if not location:
            continue
        path = nfc(urllib.parse.unquote(location.replace("file://localhost", "")))
        if path.startswith(folder + "/"):
            tracks[path] = (parse_key(track.get("Tonality")), float(track.get("AverageBpm") or 0))
    return tracks


def load_hdj(db_path):
    """Return (bpm by path, {profile: {path: (key, parent camelot, key text)}}) from a DB copy."""
    with tempfile.TemporaryDirectory() as tmp:
        copy = Path(tmp) / "hdj.sqlite"
        shutil.copyfile(db_path, copy)
        con = sqlite3.connect(f"file:{copy}?immutable=1", uri=True)
        bpm = {nfc(p): b for p, b in con.execute("select path, bpm from tracks")}
        keys = defaultdict(dict)
        rows = con.execute(
            "select path, profile_id, key_root, key_mode, keycode, key from track_key_profiles"
        )
        for path, profile, root, mode, keycode, text in rows:
            if root is None:
                continue
            parent = int(re.match(r"\d+", keycode)[0]) if keycode else None
            keys[profile][nfc(path)] = ((PC[root], mode in MINOR_MODES), parent, text)
        con.close()
    return bpm, keys


def tally(pairs):
    """Format relation counts and agreement rates for (a, b, a_parent) triples."""
    counts = Counter(relation(*pair) for pair in pairs)
    counts.pop(None, None)
    n = sum(counts.values())
    if not n:
        return "n=0"
    rates = f"same {counts['same'] / n:.0%}, same+relative+same-scale " + \
        f"{(counts['same'] + counts['relative'] + counts['same-scale']) / n:.0%}"
    return " ".join(f"{r} {counts[r]:2}" for r in RELATIONS) + f" | {rates} (n={n})"


def main():
    """Print the comparison report."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("rekordbox_xml", help="rekordbox collection XML export")
    parser.add_argument("hdj_db", help="Harmonic DJ harmonic-dj.sqlite")
    parser.add_argument("folder", help="absolute folder path to compare")
    parser.add_argument("--profile", default="ecma418", help="HDJ profile for the track table")
    args = parser.parse_args()

    folder = nfc(args.folder.rstrip("/"))
    rb = load_rekordbox(args.rekordbox_xml, folder)
    hdj_bpm, hdj = load_hdj(args.hdj_db)
    paths = sorted(set(rb) & set(hdj_bpm) & set(hdj.get(args.profile, {})))
    with_bp = sum(beatport(p)[0] is not None for p in paths)
    print(f"tracks: rekordbox {len(rb)}, HDJ {len(hdj_bpm)}, both {len(paths)}, "
          f"Beatport key in name {with_bp}\n")

    print("KEY")
    print(f"  {'rekordbox vs Beatport':34} " + tally((rb[p][0], beatport(p)[0]) for p in paths))
    for profile in sorted(hdj, key=lambda x: (x != args.profile, x)):
        h = hdj[profile]
        print(f"  {'HDJ ' + profile + ' vs rekordbox':34} "
              + tally((h[p][0], rb[p][0], h[p][1]) for p in paths))
        print(f"  {'HDJ ' + profile + ' vs Beatport':34} "
              + tally((h[p][0], beatport(p)[0], h[p][1]) for p in paths))
    quality = Counter((rb[p][0][1], beatport(p)[0][1]) for p in paths
                      if rb[p][0] and beatport(p)[0])
    print("  rekordbox / Beatport major-minor: " + ", ".join(
        f"{'m' if a else 'M'}/{'m' if b else 'M'} {v}" for (a, b), v in sorted(quality.items())))

    print("\nBPM")
    for label, pairs in (
        ("HDJ vs rekordbox", [(hdj_bpm[p], rb[p][1]) for p in paths]),
        ("rekordbox vs Beatport", [(rb[p][1], beatport(p)[1]) for p in paths]),
    ):
        counts = Counter(bpm_relation(a, b) for a, b in pairs)
        counts.pop(None, None)
        print(f"  {label:34} " + ", ".join(f"{k} {counts[k]}"
                                           for k in ("same", "half/double", "other")))

    print(f"\nPER TRACK (HDJ profile {args.profile})")
    print(f"  {'track':44} {'rekordbox':10} {'HDJ':28} {'Beatport':10} {'HDJ~rb':10} BPM rb/HDJ/bp")
    for path in paths:
        key, parent, text = hdj[args.profile][path]
        bp_key, bp_bpm = beatport(path)
        name = Path(path).name[:44]
        print(f"  {name:44} {show(rb[path][0]):10} {text[:28]:28} {show(bp_key):10} "
              f"{relation(key, rb[path][0], parent) or '-':10} "
              f"{rb[path][1]:.1f}/{hdj_bpm[path]:.1f}/{bp_bpm or '-'}")


if __name__ == "__main__":
    main()
