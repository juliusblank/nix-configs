# Music collection quality

| | |
|---|---|
| **Slug** | `music-collection-quality` |
| **Status** | active |
| **Started / last update** | 2026-11-08 / 2026-11-17 |
| **Budget** | a few evenings (start with 4, then end-of-budget review); €0 — a paid tool only after a decision |
| **Roadmap** | #38 |
| **Task state** | storage-migration `docs/progress.md` (the only task list: tasks 9a, 10a, 15); this file holds goal and decisions |

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
  (`dj-prep-workflow`), re-buying tracks, a new tagging scheme, consolidating the
  playlist tree (similar lists, naming, folders: [`rekordbox-tagging`](rekordbox-tagging.md);
  this pass only builds the date playlists and keeps existing lists intact).
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
| Read a copy of `master.db` (`pyrekordbox`): tracks, paths, missing files, folders, path-duplicates | 3 | 3 | 3 | 3 | 3 | 3 | replaced — rekordbox XML export (File → Export Collection) holds all of it and needs no decryption |
| Inventory every source with the storage-migration scanner (sha256) → duplicate sets across sources | 3 | 3 | 2 | 3 | 3 | 3 | done (I1) |
| Purchase dates from folder names and `beatport_tracks_YYYY-MM` zips → playlists per date | 3 | 3 | 3 | 3 | 3 | 3 | done (I1) — dates from the Beatport library export instead |
| rekordbox built-ins: Missing File Manager, Duplicated File Manager (on a test track first) | 2 | 2 | 3 | 2 | 3 | 3 | Missing File Manager + Auto Relocate used (I1); Duplicated File Manager not needed |
| Beatport library page: own purchase list (manual copy / export of `beatport.com/library`), match by file name, tags, Beatport ID | 2 | 3 | 2 | 3 | 3 | 2 | done (I1) |
| Audio fingerprint (chromaprint `fpcalc`) for the same track in different files / formats | 2 | 2 | 1 | 3 | 3 | 2 | replaced — hash of the decoded audio (`audio_hash`, `pcm_hash` across WAV / AIFF) |
| Lexicon trial (duplicates, lost / broken tracks) | 2 | 2 | 2 | 2 | 1 | 2 | dropped — not needed |
| Open-source fixers (rekordbox-library-fixer, rekordbox-repair) | 1 | 2 | 2 | 1 | 3 | 1 | dropped — not needed |
| Rest of the Data drive (unused iTunes ~120 GB, friends, recordings), then clear it | 2 | 3 | 2 | 3 | 3 | 3 | open (storage-migration step 9) |
| Dropbox `Musik` / `rekordbox` (106 + 9.5 GB) against the collection | 2 | 2 | 2 | 3 | 3 | 3 | open |
| Narrow the `dj` backup group to `Library`, `Recordings`, `Productions` (*SPEC → Backup tailoring*) | 1 | 3 | 3 | 3 | 3 | 3 | open — possible now |

## Iterations

### I1 — Clean up serenity `~/Music` and the rekordbox collection (2026-11-09 → 17)

Run in the storage-migration repo (state and history: `docs/progress.md`; structure:
`docs/structure.md`; every action in `ledger/ledger.csv`). Not run with the iteration
format (one question, budget); recorded here after the fact.

- **Results** —
  - Inventory of serenity and the Data drive (sha256); rekordbox read only from its XML
    export, changed only by rekordbox itself (XML playlist import, Auto Relocate, Missing
    File Manager).
  - Missing files 164 → 1 (the unwanted `Hochzeitsplaylist`); 606 drive ↔ serenity
    double entries merged; 841 tag-only duplicates (same audio) merged; no entry points to
    the Data drive any more.
  - New structure `~/Music/Library/Purchased/<Source>/<YYYY>/<YYYYMMDD>`,
    `Library/Friends/<Name>/<YYYYMMDD>`, `Library/Collection`, `~/Music/Recordings`,
    `~/Music/Productions`; file names
    `<Artists> - <Title> (<Mix>) [<shop id>]` (`#` → `No.`).
  - Purchases: 2,512 Beatport files by purchase date (Beatport library export; the
    Beatport Pro 2015 export for old ones), Bandcamp / Various / Juno / iTunes; rekordbox
    playlists `<shop>/<YYYY>/<YYYYMMDD>`.
  - Friends' music flat per delivery date; temp copies, `rekordbox_backup` (200 GB),
    duplicates and zips in the Trash (kept in the `dj` backup).
  - Own mixes (16) moved out of the library into `Recordings/DJ-Sets/`; old set-list
    exports (June 2023) rebuilt as rekordbox playlists `Setlists 2023 (restored)`.
  - Collection 2026-11-17: 5,627 entries.
- **Conclusions** —
  - The XML playlist import is safe for playlists: it reuses existing entries and
    changes none of their attributes (checked after every import with
    `tools/rb_compare.py`), also for paths with `#` (36 such tracks went through).
    Moving an imported folder onto a same-named one asks to replace it.
  - Auto Relocate finds renamed files (cues, grid, attributes kept), except a file whose
    content changed since rekordbox last saw it (relocate by hand).
  - rekordbox writes into music files: "Add My Tag to the Comments" (Preferences →
    Advanced → Browse) rewrote 4,830 files on 2026-11-16 (restored byte-identical from
    restic `dj`, 1,386 files that still differed); Analyze Track / Reload Tag on new
    tracks wrote the key into 30 files. Mixed In Key writes too (`track-prep`, 2026-11-12).
  - The restic `dj` backup restored 1,386 files byte-identical into their current
    (moved) paths — a real restore test at file level.
  - Many gig playlists had lost tracks between 2023-06 and 2026-11 (before this cleanup;
    e.g. Rummelsbucht 27 → 15), found through the June 2023 set-list exports.
- **Consequences applied** — open questions answered (below); backlog statuses;
  `rekordbox-tagging` (file writes, set-list evidence, playlist consolidation),
  `track-prep` (file-write rule), `dj-prep-workflow` and *SPEC → Harmonic DJ* (XML
  playlist import, `#` paths, analysis scope figures), *SPEC → Backup* (paths).
- **Goal check** — rekordbox and Beatport criteria met; open: Data drive, Dropbox,
  backup narrowing. Continue.

## Decisions

- 2026-11-08 — scope: all music sources (serenity, external drives, Dropbox) — one pass
  instead of several; this is storage-migration's "music pass".
- 2026-11-08 — "done" at about 95 % per criterion — the long tail is listed, not fixed.
- 2026-11-08 — Beatport purchases become rekordbox playlists per purchase date.
- 2026-11-08 — before the cleanup, all of `~/Music` is backed up and pinned as
  `baseline` (*SPEC → Backup*), so nothing the cleanup moves can be lost.
- 2026-11-09 — the collection lives locally in `~/Music/Library` (rekordbox needs local
  files), backed up by restic `dj`; structure in storage-migration `docs/structure.md`.
- 2026-11-15 — file names `<Artists> - <Title> (<Mix>) [<shop id>].<ext>`, names from
  the shop's data; `#` → `No.`, no characters that break FAT32 / exFAT sticks.
- 2026-11-15 — playlist changes through rekordbox's XML import (playlists only, TRACK
  elements copied verbatim from a fresh export); never `master.db` writes.
- 2026-11-16 — two copies of a track bought twice stay; other versions (edit / remix)
  are different tracks.
- 2026-11-17 — own mixes and recordings are not part of the library (`~/Music/Recordings`);
  own productions in `~/Music/Productions` (workflows for both: later, storage-migration).
- 2026-11-17 — no file writes into the library while the migration runs (moves and
  duplicates are verified by sha256); afterwards tools may write into files deliberately
  (`track-prep`).

## Open questions

- [x] Where does the collection live afterwards? — local `~/Music/Library` (decision
      2026-11-09).
- [x] What counts as a duplicate? — identical bytes, or the same decoded audio with other
      tags or another lossless container (WAV / AIFF); other versions are other tracks.
- [x] Does `rekordbox_backup` hold tracks that exist nowhere else? — a few (sorted into
      `Library` in round 9); the rest was copies (trashed).
- [x] Can the Beatport purchase history be exported, with the date? — yes, the Beatport
      library export has the purchase date per track.
- [x] Playlist import path for `#` paths? — XML import (handles `#`); `#` is no longer
      written in new file names.
- [x] What does rekordbox's Duplicated File Manager keep? — not tested; merging via XML
      import was enough.
- [ ] Which external drives exist, and what do they hold? — the Data drive (data1tb)
      is the only one used so far; its rest is step 9.
- [ ] Dropbox `Musik`: what is there that the collection lacks?

## Summary (when closed)

Outcome · decisions · learnings · artifacts · follow-ups.
