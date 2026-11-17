# Track prep (beat grid and cue points)

| | |
|---|---|
| **Slug** | `track-prep` |
| **Status** | active |
| **Started / last update** | 2026-11-14 / 2026-11-17 |
| **Budget** | 3 evenings, then end-of-budget review; €0 (Mixed In Key 11 licence and rekordbox Creative exist) |
| **Roadmap** | — |

## State and next steps

_Last update 2026-11-17._

- **Done:** research on Mixed In Key, CueGen and Intelligent Cue Creation; comparison test
  A / B / C designed (below). Not run yet.
- **Next, in order:**
  1. Pick 10 hand-cued reference tracks (and, for C, ≥ 30 training tracks).
  2. Copy plan into `~/Music/_cue-test/{A-mik,B-cuegen,C-icc}/` and a cue comparison script in
     `scripts/dj`.
  3. Run A (Mixed In Key) and C (Intelligent Cue Creation) on the copies.
- **Blocked:** B (CueGen writes `master.db`) until the library cleanup is finished.

## Brief

- **Purpose** — every track I play needs a fine-tuned beat grid and my standard cue
  points, so tracks blend on aligned (usually 64-bar) loops. Doing this by hand is slow,
  and the backlog is large. A building block for set building, next to
  [`rekordbox-tagging`](rekordbox-tagging.md).
- **Goal** — my prep standard applied consistently and noticeably faster, ideally partly
  automated.
- **My standard** — cue names and positions:
  - intro: `start` (track start), `bass` or `kick` (during the intro);
  - main part: `main`, `breakdown`, `drop`;
  - end: `outro`, `fade out`.
  The cues mark 64-bar loop boundaries for aligned blends.
- **Non-goals / scope** — set building and tagging; anything that changes the music files
  in `~/Music/Library` during the storage migration.
- **Context** — rekordbox 7.2.x (Creative), Mixed In Key 11 (installed 2026-11-12 via
  nix-configs #188/#189, file-writing preferences off #190). Mixed In Key still writes its
  analysis (GEOB frames) into analysed files (verified 2026-11-12, track restored from
  restic), so it may only run on copies until the migration is done.
- **Constraints / risk tolerance** — rekordbox changed only through rekordbox (UI, XML
  import); music files in `~/Music/Library` must not change (sha256); tests on copies.
  Exception: CueGen may write `master.db` directly (test B and later use), but only once
  the library fixes and cleanup (storage-migration) are done; backup first. rekordbox's Preferences → Analysis → [Key Analysis] → "Write the value to
  the ID3 tag" writes into files: must stay off (manual p. 237).
- **Prior knowledge / research**
  - **Mixed In Key → rekordbox** (vendor docs, not verified): XML round trip — export the
    rekordbox collection as XML, connect it in Mixed In Key, analyse, then in rekordbox
    reload the XML and import the playlist "MIK Cue Points"; existing memory cues need the
    overwrite option ([workflow](https://mixedinkey.com/workflows/export-cue-points-to-rekordbox/),
    [rekordbox guide](https://mixedinkey.com/workflows/use-mixed-in-key-with-rekordbox/)).
    Up to 8 automatic cues per track, named by energy level ("Energy 5"). A CueGen user
    reports MIK 11's own export arrives with all cues green
    ([CueGen #25](https://github.com/mganss/CueGen/issues/25), 2025-07, unverified).
  - **CueGen** ([mganss/CueGen](https://github.com/mganss/CueGen), MIT, console app,
    last release v1.0.37 2023-09, `osx-x64` build → runs under Rosetta, which is installed):
    - writes cues **directly into `master.db`**; rekordbox must be closed; makes a
      `master.backup.<datetime>.db` before each run; `--dryrun`; `--remove` deletes all
      cues it created; `--glob` limits the tracks (reported unreliable for single files,
      #25), `--mindate` by import date;
    - two sources: **Mixed In Key cues** read from the Serato ID3 tags MIK writes into the
      file (→ copies only here), or **rekordbox phrases** read from rekordbox's own
      analysis files (`ANLZ*.DAT`; no MIK, no file writes);
    - phrase mode: a cue at the start of each phrase group (Intro, Verse, Bridge, Chorus,
      Up, Down, Outro; groups combinable via `--order`), snapped to the bar, `--offset` in
      beats, `--max` cues, memory or hot cues (`--hc`), colours per phrase, merge with
      existing cues keeping `--distance` bars apart; optional active loops on intro / outro;
    - extras: an "Energy" My Tag and track colour from MIK's energy (README: the extra My
      Tag category can't be used as a filter) — not wanted (colour = prep status).
    - README says rekordbox 6; on rekordbox 7 one user reports it runs (issue #25), none
      verified on 7.2.
  - **rekordbox INTELLIGENT CUE CREATION** (manual 7.2.18 pp. 41–45, 237–238): "CUE
    Analysis" sets hot cues (up to 16) and / or memory cues (up to 10) **during track
    analysis**; needs phrase analysis on; available on the Creative plan (checked
    2026-11-15). Two modes:
    - **Auto**: general learning data plus **personal CUE trend** learned from tracks in
      the [CUE Analysis playlist] ([Start] button; "register 30 tracks or more", several
      genres; the more consistent my cues, the closer the result). Tried before with a
      trained personal trend, results were off; newer versions may do better.
    - **Manual**: a cue at 1.1 Bars and optionally repeated every N bars from there.
    - Settings in Preferences → Analysis → [CUE Analysis]: [Set CUE during analysis]
      (Auto / Manual), [CUE Type] (hot / memory, how many), [Set to 1.1 Bars], repeat every
      N bars, [Prohibit overwriting CUEs], [Add a comment to CUE].
    - Re-analysing a track runs it again (manual p. 41: analyse already analysed tracks).
  - rekordbox XML import reuses existing entries for playlists (proven 2026-11-14,
    storage-migration); whether it updates cues of existing entries is unknown.
- **References** — rekordbox 7.2.18 manual: beat grid editing, phrase edit, INTELLIGENT
  CUE CREATION (pp. 41–45), Preferences → Analysis (pp. 237–238), XML import; CueGen README
  and issues #14, #19, #25.

## Scrutiny and verdict

- **Exists already?** — `dj-prep-workflow` covers set planning, not track prep.
- **Makes sense?** — yes; cue placement is repetitive and partly automatable.
- **Knowledge level** — medium.
- **Greenfield or researched before?** — rekordbox's Intelligent Cue Creation tried
  before, with personal trend training (results off; retest on 7.2).
- **Verdict** — **pursue**.

## Goal and definition of done

- **Goal** — as in the brief.
- **Non-goals** — as in the brief.
- **Done when**
  - the prep standard is written down (names, positions, colors, hot vs memory cue);
  - the tool route is decided (Mixed In Key · CueGen phrases · rekordbox Intelligent Cue
    Creation · manual · a mix), based on the comparison test below;
  - tested on 10–20 tracks with measured time per track (before / after) and cue accuracy
    against my standard.

## Where automatic cues fit in the workflow

```
import → rekordbox analysis (BPM/grid, key, phrase, vocal)
       → fix beat grid by hand                      ← cues snap to the grid, so first
       → automatic cue seeding (one of A / B / C)   ← candidates tested below
       → listen through: fix / rename cues to my standard, tag (rekordbox-tagging)
       → colour yellow → green
```

- **A Mixed In Key**: after the grid, per batch via XML round trip; needs copies while the
  migration runs, so not usable on the library yet.
- **B CueGen (phrase mode)**: after rekordbox's phrase analysis and grid fix, with
  rekordbox closed, batch by import date (`--mindate`); no file writes. MIK mode only on
  copies (needs MIK's tags in the file).
- **C rekordbox Intelligent Cue Creation**: inside the analysis step itself; for already
  analysed tracks via re-analysis. Grid fixes after it may shift the cues' meaning.

## Comparison test: automatic cues A / B / C against my own

Question: which tool's cues come closest to my standard, with the least fixing, and
without side effects on the library?

**Shared setup (once)**

1. **Reference set**: 10 tracks that already carry my hand-placed cues (several genres,
   intros of different lengths). Their cues in the current XML export are the reference.
2. **Copies**: copy them three times, to `~/Music/_cue-test/{A-mik,B-cuegen,C-icc}/`
   (outside `Library`); hash all copies. Each tool works on its own copies, so the runs
   don't interfere and the library entries stay untouched.
3. **Safety**: rekordbox closed, copy `~/Library/Pioneer/rekordbox/` (whole folder) to a
   dated backup; check Key Analysis "Write the value to the ID3 tag" is off.
4. **Import** each copy folder as new entries into playlists `_cue-test-A/B/C`; analyse
   with BPM/Grid, Key, Phrase, Vocal (Intelligent Cue Creation **off** for A and B);
   fix the grid where needed (same fixes on all three copies of a track).
5. **Baseline export**: XML export; note the test entries have no cues.

**A — Mixed In Key** (as planned before): connect the XML in MIK, analyse only
`_cue-test-A`, export cues, reload the XML in rekordbox, import "MIK Cue Points".

**B — CueGen, phrase mode** (only after the library cleanup is done; `master.db` write approved for then):

1. Download the release zip `CueGen.1.0.37.osx-x64.zip` from GitHub (Julius confirms),
   unpack outside the repo; check the binary runs (`--help`).
2. rekordbox closed; dry run restricted to the test copies:
   `CueGen.Console --dryrun --phrase --glob="**/_cue-test/B-cuegen/**" -v info -l cuegen-dry.log`
   → the log must list exactly the 10 B entries (glob issue #25: if it matches nothing,
   stop and rethink rather than run without `--glob`).
3. Real run with the same options (+ `--max=8`, memory cues; a second pass with `--hc`
   as hot cues if wanted); CueGen's own db backup on.
4. Open rekordbox, export XML; check only the B entries changed (`rb_compare.py`).
5. Variants if time permits: `--order` mapping to my standard (e.g. `Intro` → start,
   `Up` → bass/build, `Chorus` → main/drop, `Down` → breakdown, `Outro` → outro),
   `--offset` to land cues on 64-bar boundaries.

**C — rekordbox Intelligent Cue Creation**:

1. Train the personal trend: put ≥30 tracks with my own cues (several genres, **not** the
   10 test tracks) into the [CUE Analysis playlist], click [Start].
2. Preferences → Analysis → [CUE Analysis]: Set CUE during analysis = Auto; CUE type
   memory (and / or hot); Prohibit overwriting CUEs on; Add a comment to CUE on (Julius
   changes the settings; note the previous values).
3. Re-analyse only `_cue-test-C`. Export XML; check only the C entries changed.
4. Variant C2: Manual mode, cue at 1.1 Bars repeated every 64 bars (or the closest value
   offered) — cheap check whether a pure 64-bar grid already beats the "smart" cues.
5. Reset the CUE Analysis settings to the previous values (or keep them, if C wins).

**Compare (same for A, B, C)**, from the XML export, per track:

- number of cues, hot vs memory, names / comments, colours;
- for every reference cue: distance to the nearest generated cue in bars (from BPM and
  positions); hits = within ±1 bar; extra cues that match nothing;
- fix time per track to reach my standard (stopwatch), against the manual baseline;
- side effects: no other entry changed, copy hashes (A: expected to change, B / C: must
  not change), no duplicate entries.

A small script reads the `POSITION_MARK`s of the test and reference entries from the XML
and prints the hit table (to write in `scripts/dj`).

**Clean up**: remove the test entries (and CueGen's cues on them come with them), delete
`~/Music/_cue-test/` (Julius), `rb_compare.py` shows only the removed test entries; keep
or reset the CUE Analysis settings; keep the rekordbox folder backup until the next restic
snapshot.

**Success criteria**: a tool wins if its cues hit at least about two thirds of my
reference cues within ±1 bar, fixing takes clearly less time than placing by hand, and
nothing outside its test entries changed.

## Approach backlog

Scores 1–3: L = learning per effort, V = value toward the goal, T = time to first signal,
R = risk / reversibility (3 = safe), C = cost (3 = cheap), F = fit.

| Approach | L | V | T | R | C | F | Status |
|---|---|---|---|---|---|---|---|
| Write down the prep standard (names, positions, colors, hot vs memory) | 3 | 3 | 3 | 3 | 3 | 3 | open |
| Measure the manual baseline: time per track for 5 tracks | 3 | 2 | 3 | 3 | 3 | 3 | open |
| Comparison test A / B / C (above), shared setup | 3 | 3 | 2 | 3 | 3 | 3 | open |
| A — Mixed In Key cue export via XML | 3 | 3 | 2 | 3 | 3 | 2 | open (part of the comparison) |
| B — CueGen phrase mode (writes `master.db`; backup + dry run first) | 3 | 3 | 2 | 2 | 3 | 2 | open (part of the comparison; after the library cleanup) |
| C — rekordbox Intelligent Cue Creation, Auto with personal trend; C2 Manual every 64 bars | 3 | 3 | 3 | 3 | 3 | 3 | open (part of the comparison) |
| Generate cues from rekordbox phrase data ourselves (XML import with my names; CueGen's MIT code shows how to read `ANLZ` phrases) | 2 | 3 | 1 | 3 | 3 | 2 | open — fallback if B works but its `master.db` writes are not acceptable |
| Beat grid fine-tuning: rekordbox grid tools vs Mixed In Key grid | 2 | 2 | 2 | 3 | 3 | 2 | open |

## Iterations

_None yet._ Suggested I1: "Which automatic cue source (Mixed In Key, CueGen phrases,
rekordbox Intelligent Cue Creation) comes closest to my standard?" (comparison test above).
It also answers whether Mixed In Key's energy reaches rekordbox (`rekordbox-tagging`).

## Decisions

- 2026-11-14 — Mixed In Key only on copies until the music migration is done (it writes into files).
- 2026-11-15 — CueGen and rekordbox Intelligent Cue Creation join the test (replaces the 2026-11-14 decision to leave Intelligent Cue Creation for later); one comparison test on shared copies.
- 2026-11-15 — CueGen's direct `master.db` writes are acceptable once the library fixes and cleanup are done; test B waits until then, A and C can start now.
- 2026-11-15 — Intelligent Cue Creation gets a retest although it was trained before (results were off), since newer versions may do better.

## Open questions

- [ ] Do Mixed In Key cues arrive as hot or memory cues, with which names and colors?
- [ ] Does rekordbox's XML import update cues of existing entries, or create new entries?
- [ ] Which of my cue names can be derived automatically (energy changes, phrases)?
- [ ] Hot cues, memory cues or both for my standard?
- [ ] Does Mixed In Key's energy level (1–10) reach rekordbox via the XML round trip, or only
  via the file's comment tag? (`rekordbox-tagging` v1 uses it as a starting value; energy
  reference tracks are picked after this test.)
- [x] Is a direct `master.db` write by CueGen acceptable? — yes, once the library fixes and
  cleanup are done (2026-11-15).
- [ ] Does CueGen v1.0.37 work with rekordbox 7.2 (db format, `--glob` matching)?
- [x] Is Intelligent Cue Creation available on the Creative plan? — yes (2026-11-15).
- [x] Was the personal CUE trend trained last time? — yes, results were off; enough tracks
  with my own cues exist for training (≥30) plus the test (10) (2026-11-15).
- [ ] Do Mixed In Key's cues transfer from a copy's entry to the library entry (generated XML
  with the library path and the copy's cues)? Depends on whether XML import updates cues
  of existing entries.

## Summary (when closed)

Outcome · decisions · learnings · artifacts · follow-ups.
