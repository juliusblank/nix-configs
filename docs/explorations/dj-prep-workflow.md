# DJ preparation workflow

| | |
|---|---|
| **Slug** | `dj-prep-workflow` |
| **Status** | active |
| **Started / last update** | 2026-10-17 / 2026-11-07 |
| **Budget** | not set for I1–I3 (they predate the process); set one per iteration from I4 on. Money: Harmonic DJ Pro ($40 one-time) only at the decision gate |
| **Roadmap** | #32 (Harmonic DJ evaluation); related #10 (backup), #15 (DJ toolchain), #16 (MCP) |

Detailed evidence: [`docs/harmonic-dj.md`](../harmonic-dj.md) (vendor research, install,
storage, test logs T1–T4, known issue). Spec: `docs/SPEC.md` → *DJ Toolchain → Harmonic
DJ* (workflow, tests T1–T6, decision gate incl. analysis scope). Scripts: `scripts/dj/`.

## Brief

- **Purpose** — spend less time compiling set playlists and listening through them to
  hear whether the tracks fit together.
- **Goal** — for a set I have pre-selected, get a good running order (key, BPM, energy)
  with little effort, and have it in rekordbox ready to play.
- **Non-goals / scope** — replacing rekordbox as the library or the key / BPM analyzer;
  writing into rekordbox's database or importing rekordbox XML; writing tags.
- **Context** — dig on Spotify → buy on Beatport → library folder per purchase date →
  rekordbox 7.2.14 (analysis, cue points; key display: Alphanumeric) → sets ordered by
  hand with Camelot.
- **Constraints / risk tolerance** — no writes into rekordbox's data (playlist import
  via M3U only); local over cloud; one-time payment over subscriptions; work on copies
  when touching audio files; Harmonic DJ data only read via copies.
- **Prior knowledge / research** — `docs/harmonic-dj.md`.
- **References** — Harmonic DJ <https://apu.software/hdj/>; rekordbox 7.2.16 manual
  (pp. 40, 255); tool sources under I3.

## Scrutiny and verdict

- **Exists already?** Yes, a whole category of set planners (Harmonic DJ, DJ.Studio,
  SetFlow, Mixgraph, Djoid, MixReady) and online playlist analyzers (TuneBad, Song
  Finder, Brizm, Sort by Tune, Skiley) — see I3. Harmonic DJ is the only one found with
  modes and separate in / out keys.
- **Makes sense?** Yes — the round trip with rekordbox works (T1, T2); the open question
  is the value of the tool's order (T5).
- **Knowledge level** — high on the workflow and rekordbox; medium on the tools.
- **Greenfield or researched before?** Researched: started as the Harmonic DJ
  evaluation (roadmap #32) on 2026-10-17.
- **Verdict** — **pursue**, Harmonic DJ as the main candidate (local, one-time $40,
  own modal analysis, tested round trip); DJ.Studio as the comparison candidate.

## Goal and definition of done

- **Goal** — plan real sets from a pre-selected rekordbox base list with a tool
  (Harmonic DJ first), bring the order back into rekordbox, and save time.
- **Non-goals** — see Brief.
- **Done when** —
  - T5 passes for at least one real set: the tool's order saves time against compiling
    and listening by hand, and its transitions are at least as good as my own order;
  - the tool decision is made (Harmonic DJ Community / Pro, or an alternative);
  - the analysis scope is decided (which parts of the collection the tool analyzes);
  - the workflow is written down so it is repeatable (spec → *Workflow and data flow*).

## Approach backlog

Scores 1–3: L = learning per effort, V = value toward the goal, T = time to first signal,
R = risk / reversibility (3 = safe), C = cost (3 = cheap), F = fit.

| Approach | L | V | T | R | C | F | Status |
|---|---|---|---|---|---|---|---|
| T5a — real set in Harmonic DJ, base list only (Pro trial for > 5 tracks) | 3 | 3 | 2 | 3 | 2 | 3 | open (next) |
| T6 — base list with a track HDJ has not analyzed | 3 | 2 | 3 | 3 | 3 | 3 | open (next) |
| T5b — HDJ adds tracks from a larger analyzed pool | 2 | 3 | 1 | 3 | 2 | 2 | open (needs scope + cleanup) |
| DJ.Studio 7-day trial, same set, without its rekordbox connection | 2 | 2 | 2 | 2 | 2 | 2 | open |
| Own ordering script on HDJ's DB data (→ MCP #16 later) | 2 | 2 | 2 | 3 | 3 | 3 | open |
| Online analyzer check (TuneBad / Song Finder) against the T4 references | 2 | 1 | 3 | 2 | 3 | 2 | open (pre-buy check) |
| rekordbox Spotify integration: does it show keys for Spotify tracks? | 2 | 1 | 3 | 3 | 3 | 2 | open (1-minute check) |
| Beatport previews analyzed in HDJ before buying | 1 | 2 | 1 | 3 | 3 | 2 | open (larger topic, #15) |
| Re-test the `#` import after the next rekordbox update (`t1c-1-plain.m3u`) | 2 | 1 | 3 | 3 | 3 | 3 | open (on update) |
| T4 listening on 4–5 major / minor cases | 1 | 1 | 2 | 3 | 3 | 3 | optional |
| Generator tuning (BPM range, key strictness) | 2 | 2 | 3 | 3 | 3 | 3 | open (part of T5) |
| Rename the 126 paths with `#` + relocate in rekordbox and HDJ | 1 | 2 | 1 | 1 | 3 | 2 | later (own step) |
| SetFlow / Mixgraph | 1 | 1 | 3 | 1 | 2 | 1 | dropped for now (cloud, subscription, rekordbox keys) |
| T3 — write HDJ data into tags | — | — | — | — | — | — | deferred (not needed for planning) |
| rekordbox XML import / direct `master.db` writes (Mixo-style) | — | — | — | — | — | — | dropped (risk to existing track data) |

## Iterations

### I1 — Does Harmonic DJ run cleanly and safely next to rekordbox? (2026-10-17)

- **Selected approaches:** nix derivation (app only) and first run on serenity; storage
  check against a pre-launch marker; restore test.
- **Results** —
  - **Install:** module `custom.harmonicDj` (1.2.9) unpacks only the Standalone app from
    the notarized dmg; signature intact (`codesign --verify --deep --strict`, `spctl`:
    Notarized Developer ID). The embedded AUv3 is registered by macOS at first launch.
    First run: one click (appearance); a default empty Mix is created.
  - **Storage:** `~/Library/APU Harmonic DJ/` (`harmonic-dj.sqlite`, `mixes.json`,
    `mixes/`, `mix-history/`) and `~/Library/Application Support/APU Harmonic DJ/`
    (`.global.settings`, `.settings`). Newly seen on serenity: the non-global `.settings`
    (its `filterState` decodes to the plugin editor state only) and an AUv3
    `Application Scripts` folder (system-managed).
  - **Defaults:** key profile `ECMA-418 (Precise)`, level reference `K-System (83 dB
    SPL)`, Mix target −14.0 LUFS. The **key profile is a per-Mix setting**
    (`settings.keyProfile` in the `.hdjmix`); a new Mix starts with `ecma418`.
  - **Restore test passed:** both folders copied apart, originals moved away, copies
    restored; after an app run the DB is byte-identical — no rescan.
  - **Key codes decoded** (490 / 490 values): number = Camelot number of the mode's
    parent major scale, letter = mode (B ionian, D dorian, P phrygian, L lydian,
    M mixolydian, A aeolian). `B` / `A` codes equal Camelot.
  - **DB:** 27 tracks ≈ 655 KB (≈ 24 KB per track); all 14 key profiles stored per track.
- **Conclusions** — safe to evaluate; the backup is two folders, copied with the app
  closed; the DB is readable for scripts (read-only, via copies).
- **Consequences applied** — spec storage table and open questions; backup handoff for
  #10 / #126 (two folders, `inhibitApps` `"APU Harmonic DJ"`, restic keeps absolute
  paths); `scripts/dj/hdj_keycode_check.py`.
- **Goal check** — continue.

### I2 — Does the round trip with rekordbox work, and are the keys trustworthy? (2026-10-17 → 18)

- **Selected approaches:** T1 (HDJ Mix → M3U → rekordbox), T2 (rekordbox → M3U8 → HDJ →
  M3U → rekordbox), T4 (key / BPM comparison on the 27 evaluation tracks).
- **Results** —
  - **Paths:** tracks resolve to the **existing** rekordbox entries (play count kept,
    collection count unchanged at 7037). Both tools write **NFC** paths; files on disk
    are NFD; rekordbox matches both. **HDJ handles `#` paths** (imports and exports them).
  - **`#` in a path: rekordbox drops the track silently** on M3U import — no error, no
    log entry. No M3U spelling helps (plain, `file://` URL with `%23`, `%23`,
    `#EXTINF`, `.m3u8`); rekordbox's **own** `.m3u8` export re-imports with 26 of 27
    tracks. Its importer does not decode percent escapes. It is a rekordbox 7.2.14
    limitation; release notes up to 7.2.19 mention nothing; no public issue tracker.
    Affects 126 of 6217 audio files (107 names, mostly Beatport `F#`-style keys; 46
    folders).
  - **rekordbox import:** File → Import → Import Playlist only. The Playlist menu's
    Import / Export items act on iTunes, rekordbox xml or device playlists (greyed out
    for normal playlists; manual p. 255). Importing never replaces or merges: it creates
    `<name> (1)`. Duplicates and order are kept.
  - **HDJ side:** base list import via the Mix menu **… → Import Playlist** reuses
    existing entries (no re-analysis); the Mix stores `sourcePlaylistPaths`. HDJ keeps
    a manual order and marks rule breaks ("No compatible transition under current
    rules"); it allows the same track twice. "Generate Tracklist" filled only 3 of 5
    slots — likely the Mix defaults `maximumBpmDifference: 0`, `bpmStrategy:
    rounded-match`.
  - **T4 keys** (`scripts/dj/hdj_compare_keys.py`; rekordbox from its XML export —
    `Tonality` in Camelot because of the Alphanumeric display setting; "Display key
    information on the database" off, so these are rekordbox's own analysis): roots
    agree almost always; rekordbox says **minor for 25 of 26** tracks, Beatport says
    major for 18 of those, HDJ mostly a major mode (lydian / mixolydian) on the same
    root. HDJ `ecma418` vs rekordbox: 9 same, 3 same-scale, 13 parallel, 1 adjacent,
    1 other; HDJ vs Beatport: 19 same. The profile barely matters (73–77 % agreement
    with Beatport for all 14).
  - **T4 BPM:** HDJ = rekordbox on all 27 (±0.5); Beatport file names differ on 4, so
    they are no BPM reference. Beatport key / BPM in file names exist only for newer
    downloads.
  - **Key mapping (what-if):** using HDJ keys in rekordbox would change 18 of 27 keys
    by root (mostly minor → major on the same root) or 22 of 27 by parent scale (exact
    note sets, but names like "F" for a C-mixolydian track).
- **Conclusions** — the round trip works with two limitations (`#` paths, `(1)`
  playlists); rekordbox's major / minor labels are doubtful for modal tracks; HDJ's
  value is its extra data for ordering, not replacing rekordbox's keys.
- **Consequences applied** — known issue + interim rule (compare track counts after
  import) + rename TODO; T1 / T2 recorded as passed with limitations; XML import ruled
  out; Python helpers in `scripts/dj/` (with conventions).
- **Goal check** — continue; the question shifts to "what do I want the tool for?"

### I3 — What do I want the tool for, and what else exists? (2026-10-18)

- **Selected approaches:** define the intended use; research the tool landscape;
  check Spotify-side analysis options.
- **Results** —
  - **Intended use:** compile and order a pre-selected base list (only these tracks, or
    with suggestions from an analyzed pool) and import the result into rekordbox.
  - **Tools** (prices and details as published; comparison table from SetFlow's own
    blog, vendor-biased; not tested):

    | Tool | Ordering | Keys | Into rekordbox | Platform / price |
    |---|---|---|---|---|
    | Harmonic DJ | routes, weakest transition first | own, 6 modes, in / out | M3U (tested) | local; Pro $40 one-time |
    | DJ.Studio | "Harmonize", key / BPM slider, Camelot | own analysis per its site (SetFlow's table says imported) | playlist with hot cues — XML or DB write, not documented; M3U possible | macOS / Win; ~$99 one-time; 7-day trial; cask `djstudio` |
    | SetFlow | running order by key, tempo, energy curve | rekordbox's (from XML) | XML or M3U8 | browser; £4.99 / month |
    | Mixgraph | recommendations, library scoring | imported (Pro) | XML, M3U, CSV | web / mobile; $9.99 / month |
    | Djoid | library maps, energy chapters | imported | crates | desktop; €99 / year |
    | MixReady | builds a set, writes cue points | imported | writes into rekordbox | alpha |
    | Lexicon | no set planning (library sync) | — | sync | — |

  - **How others write into rekordbox:** Mixo uses XML or "Rekordbox Direct", which
    writes `master.db` (support asks for read **and write** access). DJ.Studio finds the
    library via the folder of `master.db`; whether it writes is not documented → if
    tested, without its rekordbox connection. Every M3U-based tool hits the `#`
    limitation.
  - **DJ.Studio install caveat:** serenity's Homebrew uses `cleanup = "uninstall"`, so a
    manual `brew install --cask djstudio` is removed by the next deploy → dmg to
    `/Applications`, or declare it if kept.
  - **Spotify:** the Spotify connector lists my playlists but not their tracks; Spotify
    removed audio features (key, tempo) for third-party apps in November 2024; HDJ only
    analyzes local files. Online analyzers with their own databases exist (TuneBad,
    Song Finder, Brizm; Sort by Tune and Skiley need a Spotify login and may reorder the
    playlist itself) — data quality unknown, major / minor only. rekordbox (Creative
    plan) may analyze Spotify tracks — unverified.
  - **Own ordering script / MCP:** feasible with existing pieces (M3U8 base list, HDJ DB
    with parent-scale key codes and out → in keys, M3U output). Community's 5-track
    limit applies to Mixes, not to analysis. Caveats: undocumented DB schema, no access
    to HDJ's transition model, partly replaces what Pro sells.
  - **Analysis scope facts:** `~/Music` ≈ 6200 audio files, 2614 of them in
    `rekordbox_backup/rekordbox_bak` (never analyze); `purchased/Beatport` 2481,
    `Fineschliff` 407, `purchased/Main` 138, `purchased/Bandcamp` 62.
- **Conclusions** — HDJ remains the best fit (local, one-time, modal data); DJ.Studio is
  the only serious comparison; Pro is likely needed for real set sizes.
- **Consequences applied** — spec: purpose = planning only, workflow step 6 rewritten,
  T3 deferred, T4 listening optional, T5 refined (a / b), T6 added, analysis-scope step
  in the decision gate, "HDJ as single analyzer" not planned; roadmap #32 updated;
  this exploration created (roadmap #34 process). **Not applied:** the
  `rekordbox_backup` exclusion for #126 was only raised with the user (open question).
- **Goal check** — goal confirmed; next: T6 and T5a with a real set.

## Decisions

- 2026-10-17 — Harmonic DJ as a nix derivation, app only, serenity only — reproducible,
  no plug-ins in `/Library`.
- 2026-10-17 — rekordbox XML import and direct DB writes ruled out — risk of
  overwriting existing track data.
- 2026-10-17 — `#` drop logged as a known issue; renaming the files is a later, separate
  step (dry-run list, rekordbox backup, rename + relocate, re-link in HDJ).
- 2026-10-18 — Intended use: set planning from a pre-selected base list; rekordbox
  stays the analyzer; HDJ as single analyzer not planned — matches the purpose, avoids
  tag writing.
- 2026-10-18 — Analysis scope is decided after T6; `rekordbox_backup/` is never
  analyzed.

## Open questions

- [ ] T5: does a tool-made order save time and sound at least as good as mine?
- [ ] T6: what does HDJ do with base-list tracks it has not analyzed?
- [ ] Pro needed? Community saves at most 5 tracks per Mix; real sets have ≈ 15–30.
- [ ] Where is the Pro license stored? (snapshot files before starting the trial)
- [ ] Which generator settings (BPM range, key strictness) give useful orders?
- [ ] Analysis scope: curated subset, grow on demand, or whole collection? Analysis
      time per track (measure on the first larger batch).
- [ ] Does #126 (backup) include the two HDJ folders, `inhibitApps "APU Harmonic DJ"`
      and an exclusion for `rekordbox_backup/`? — HDJ folders and inhibit: yes (`dj`
      backup group). `rekordbox_backup/` is backed up for now (all of `~/Music` until
      the cleanup, [`music-collection-quality`](music-collection-quality.md)) —
      it is a backup, not a collection folder, so HDJ must never analyze it.
- [ ] Is rekordbox's minor bias real? (optional T4 listening)
- [x] Key codes vs Camelot — answered (I1).
- [x] Where the key profile is stored — per Mix; a new Mix starts with `ecma418` (I1).
- [x] M3U path matching — works incl. NFC / NFD; `#` paths dropped by rekordbox (I2).
- [x] Can rekordbox import over an existing playlist? — no, it creates `<name> (1)` (I2).

## Housekeeping

- Restore-test backup: `~/hdj-restore-test-20261017/` — keep until #126 covers HDJ.
- Test files in `~/Documents/`: `hdj-t1c/`, `evaluation T1*.m3u`, `eval T2.m3u*`,
  `20260507.m3u8`, `rekordbox-collection.xml` (keep the XML for T4 reruns or re-export).
- Test playlists in rekordbox: `test`, `t1c-*`, `t1d-*`, re-imported `20260507`,
  `evaluation T1*`, `eval T2*`.

## Summary (when closed)

—
