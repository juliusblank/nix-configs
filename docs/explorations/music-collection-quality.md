# Music collection quality

| | |
|---|---|
| **Slug** | `music-collection-quality` |
| **Status** | active |
| **Started / last update** | 2026-11-08 / 2026-11-08 |
| **Budget** | a few evenings (start with 4, then end-of-budget review); €0 — a paid tool only after a decision |
| **Roadmap** | #38 |

## Brief

- **Purpose** — the music is spread over several places, with copies, missing files and
  no consistent folder structure. Set prep (and the Harmonic DJ base lists,
  [`dj-prep-workflow`](dj-prep-workflow.md)) depends on a clean collection, and the
  backup should cover the collection, not copies of it.
- **Goal** — one collection: every rekordbox track points to exactly one existing file
  in one consistent folder structure; no duplicates; every Beatport purchase maps to its
  file, with a rekordbox playlist per purchase date.
- **Non-goals / scope** — all music sources are in scope: serenity `~/Music`, external
  drives (3 TB drive, USB drives, the old music drive) and Dropbox (`Musik`,
  `rekordbox`). Not in scope: key / BPM analysis and Harmonic DJ's analysis scope
  (`dj-prep-workflow`), re-buying tracks, a new tagging scheme.
- **Context** — scan of serenity, 2026-11-07 (sizes on disk):
  - `~/Music` ≈ 500 GB: `purchased` 220 GB (2665 aiff, plus 11 download zips, 16 GB),
    `rekordbox_backup` 200 GB, `Recordings` 55 GB, `Fineschliff` 18 GB (rekordbox
    `Contents/<Artist>` layout), `tmp` 9 GB (Beatport zips 2023), friends' music
    21 GB, `rekordbox` 6 GB (`Recording`, `Sampler`), `2025` 5 GB.
  - `rekordbox_backup/rekordbox_bak`: files named `<hex>_<Artist> - <Title>`; 2473 of
    its aiff files match a `purchased` file by size, and 17 of 20 sampled matches are
    byte-identical (sha256) → mostly a copy.
  - `Music/2025`: all 79 aiff match `purchased` by size, 16 of 20 sampled identical.
  - `Fineschliff`: only 2 size matches with `purchased` → separate tracks.
  - `Downloads`: 9 GB of `beatport_tracks_YYYY-MM*.zip`.
  - Dropbox (inventory 2026-11-07, storage-migration repo): `Musik` 106 GB, `rekordbox`
    9.5 GB — not scanned in detail (music excluded from that inventory).
  - Purchase dates are partly in the folder names already
    (`purchased/Main/20160919`, `purchased/Beatport/2026/20260507`).
- **Constraints / risk tolerance** —
  - Scripts only read, and only a **copy** of `master.db`. Changes in rekordbox only
    through rekordbox itself (Missing File Manager, relocate, Duplicated File Manager,
    playlist import).
  - No file moves before the backup `baseline` snapshot of the `dj` group exists
    (*SPEC → Backup*; `just backup dj`, then `just backup-baseline dj`).
  - Cloud Library Sync is **off** (2026-11-08).
  - Nothing is deleted directly: storage-migration's rules apply (`to_delete.csv`,
    append-only ledger, source removed only after a verified copy).
- **Prior knowledge / research** —
  - [`docs/harmonic-dj.md`](../harmonic-dj.md): 126 of 6217 audio files have `#` in the
    path, and rekordbox's M3U import drops them (known issue); newer Beatport file names
    carry the key; tracks are keyed by absolute path in rekordbox and Harmonic DJ.
  - *SPEC → Harmonic DJ → Decision gate*: 2614 audio files in `rekordbox_backup`
    must never be analyzed; folder counts from 2026-10-18.
  - storage-migration repo (`~/github/juliusblank/storage-migration`): URIs, inventory
    format and scanner (`scanner/scan.py`, sha256), ledger; it keeps the music for a
    separate pass — this exploration is that pass.
- **References** — see *Scrutiny*.

## Scrutiny and verdict

- **Exists already?** Partly, as tools:
  - rekordbox 7: Missing File Manager (*File → Display All Missing Files*, relocate /
    auto relocate) and Duplicated File Manager (merges tracks with the same title and
    artist into one representative file) —
    [rekordbox FAQ v7](https://rekordbox.com/en/support/faq/v7/),
    [troubleshooting](https://rekordbox.com/en/support/faq/trouble-shooting-7/).
    Not verified here: what a merge does with cues, playlists and play counts.
  - Lexicon (paid): Find Duplicates / Unused Files / Broken Tracks / Lost Tracks, syncs
    with rekordbox — [walkthrough](https://wearecrossfader.co.uk/blog/lexicon-music-management-for-djs/).
  - Open source: [rekordbox-library-fixer](https://github.com/koraysels/rekordbox-library-fixer),
    [rekordbox-repair](https://github.com/edkennard/rekordbox-repair); paid
    [RCT](https://www.digitaldjtips.com/rct-rekordbox-music-tool/).
  - Beatport: purchases at `beatport.com/library` (re-download per track) —
    [support](https://support.beatport.com/hc/en-us/articles/46607140394004). No documented
    export of the purchase history found.
  - Nothing covers the mapping across all sources (drives, Dropbox) and the
    purchase-date playlists.
- **Makes sense?** Yes — the collection feeds set prep and the backup; the cleanup is the
  only way to shrink the `dj` backup group to the real collection.
- **Knowledge level** — medium (rekordbox DB and M3U behaviour known from
  `dj-prep-workflow`; other sources and the Beatport history unknown).
- **Greenfield or researched before?** Partly researched (see *Prior knowledge*).
- **Verdict** — **pursue**.

## Goal and definition of done

- **Goal** — see *Brief*.
- **Non-goals** — see *Brief*.
- **Done when** (about 95 % is enough; the rest is listed, not fixed):
  - every music source is inventoried (sha256), and each file is either part of the
    collection, a recorded duplicate, or a recorded decision (keep / archive / delete);
  - ≥ 95 % of the rekordbox tracks point to an existing file;
  - ≥ 95 % of the collection files sit in the agreed folder structure, without
    duplicate files;
  - ≥ 95 % of the Beatport purchases map to a file, and rekordbox has a playlist per
    purchase date for them;
  - the `dj` backup group is narrowed to the collection (*SPEC → Backup tailoring*).

## Approach backlog

Scores 1–3: L = learning per effort, V = value toward the goal, T = time to first signal,
R = risk / reversibility (3 = safe), C = cost (3 = cheap), F = fit.

| Approach | L | V | T | R | C | F | Status |
|---|---|---|---|---|---|---|---|
| Read a copy of `master.db` (`pyrekordbox`): tracks, paths, missing files, folders, path-duplicates | 3 | 3 | 3 | 3 | 3 | 3 | open |
| Inventory every source with the storage-migration scanner (sha256) → duplicate sets across sources | 3 | 3 | 2 | 3 | 3 | 3 | open |
| Purchase dates from folder names and `beatport_tracks_YYYY-MM` zips → playlists per date | 3 | 3 | 3 | 3 | 3 | 3 | open |
| rekordbox built-ins: Missing File Manager, Duplicated File Manager (on a test track first) | 2 | 2 | 3 | 2 | 3 | 3 | open |
| Beatport library page: own purchase list (manual copy / export of `beatport.com/library`), match by file name, tags, Beatport ID | 2 | 3 | 2 | 3 | 3 | 2 | open |
| Audio fingerprint (chromaprint `fpcalc`) for the same track in different files / formats | 2 | 2 | 1 | 3 | 3 | 2 | open |
| Lexicon trial (duplicates, lost / broken tracks) | 2 | 2 | 2 | 2 | 1 | 2 | open |
| Open-source fixers (rekordbox-library-fixer, rekordbox-repair) | 1 | 2 | 2 | 1 | 3 | 1 | open |

## Iterations

None yet. Proposed I1: *What is in the rekordbox collection, and where do its files
live?* (track count, missing files, duplicates, folder distribution) — `master.db` copy
plus the serenity inventory.

## Decisions

- 2026-11-08 — scope: all music sources (serenity, external drives, Dropbox) — one pass
  instead of several; this is storage-migration's "music pass".
- 2026-11-08 — "done" at about 95 % per criterion — the long tail is listed, not fixed.
- 2026-11-08 — Beatport purchases become rekordbox playlists per purchase date.
- 2026-11-08 — before the cleanup, all of `~/Music` is backed up and pinned as
  `baseline` (*SPEC → Backup*), so nothing the cleanup moves can be lost.

## Open questions

- [ ] Where does the collection live afterwards — local on serenity (+ S3 backup), or
      also Dropbox (storage-migration's `40_Musik-DJ/Library`)? Which folder structure?
- [ ] What counts as a duplicate: identical bytes, the same track in another format
      (mp3 / aiff), another version (edit / remix)?
- [ ] Does `rekordbox_backup` hold tracks that exist nowhere else (≈ 150 files —
      63 aiff, 48 wav, 26 mp3, … — without a size match in `purchased`)?
- [ ] Can the Beatport purchase history be exported, and does it carry the purchase
      date per track?
- [ ] Playlist import path: M3U drops `#` paths — rename those files first (TODO in
      `docs/harmonic-dj.md`), or another route?
- [ ] What does rekordbox's Duplicated File Manager keep (cues, playlists, play count)?
- [ ] Which external drives exist, and what do they hold (`ext3tb`, `usb01`,
      `musicdrive` in storage-migration's `locations.yaml`)?

## Summary (when closed)

Outcome · decisions · learnings · artifacts · follow-ups.
