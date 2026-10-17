# scripts/dj — conventions (Python)

Small helper scripts for the DJ toolchain (roadmap #15, #32). See `docs/harmonic-dj.md`.

- **Python 3, standard library only.** No packages, no virtualenv. Run with
  `nix shell nixpkgs#python3 -c python3 scripts/dj/<script>.py …` (python3 is not on
  the macOS hosts' PATH).
- **Read-only on app data.** Never write to Harmonic DJ's or rekordbox's files. Read
  SQLite from a temporary copy, opened with `?immutable=1`. rekordbox's `master.db` is
  encrypted and is not read at all; use rekordbox's XML **export** instead.
- **Doc comments:** a module docstring that says what the script does, its inputs, and
  that it is read-only; a one-line docstring on non-trivial functions.
- **Style:** PEP 8, 4-space indentation, 100-character lines, `argparse` for arguments.
- **No personal data in the repo:** paths and folders are arguments, not constants.
