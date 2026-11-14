# Track prep (beat grid and cue points)

| | |
|---|---|
| **Slug** | `track-prep` |
| **Status** | active |
| **Started / last update** | 2026-11-14 / 2026-11-14 |
| **Budget** | 3 evenings, then end-of-budget review; €0 (Mixed In Key 11 licence and rekordbox Creative exist) |
| **Roadmap** | — |

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
- **Non-goals / scope** — set building and tagging; rekordbox's own Intelligent Cue
  Creation (did not work well last time; a review of it is a separate, later
  exploration); anything that changes the music files during the storage migration.
- **Context** — rekordbox 7.2.x (Creative), Mixed In Key 11 (installed 2026-11-12 via
  nix-configs #188/#189, file-writing preferences off #190). Mixed In Key still writes its
  analysis (GEOB frames) into analysed files (verified 2026-11-12, track restored from
  restic), so it may only run on copies until the migration is done.
- **Constraints / risk tolerance** — rekordbox changed only through rekordbox (UI, XML
  import); music files in `~/Music/Library` must not change (sha256); tests on copies.
- **Prior knowledge / research**
  - Mixed In Key → rekordbox (vendor docs, not verified): XML round trip — export the
    rekordbox collection as XML, connect it in Mixed In Key, analyse, then in rekordbox
    reload the XML and import the playlist "MIK Cue Points"; existing memory cues need the
    overwrite option ([workflow](https://mixedinkey.com/workflows/export-cue-points-to-rekordbox/),
    [rekordbox guide](https://mixedinkey.com/workflows/use-mixed-in-key-with-rekordbox/)).
    Up to 8 automatic cues per track, named by energy level ("Energy 5"); whether they
    arrive as hot or memory cues is not documented.
  - Third-party tools write rekordbox's database directly (e.g. CueGen) — out of scope
    (no writes to `master.db`).
  - rekordbox XML import reuses existing entries for playlists (proven 2026-11-14,
    storage-migration); whether it updates cues of existing entries is unknown.
- **References** — rekordbox 7.2.18 manual: beat grid editing, INTELLIGENT CUE CREATION
  (p. 43, for the later review), XML import.

## Scrutiny and verdict

- **Exists already?** — `dj-prep-workflow` covers set planning, not track prep.
- **Makes sense?** — yes; cue placement is repetitive and partly automatable.
- **Knowledge level** — medium.
- **Greenfield or researched before?** — rekordbox's auto cues tried before (not good enough).
- **Verdict** — **pursue**.

## Goal and definition of done

- **Goal** — as in the brief.
- **Non-goals** — as in the brief.
- **Done when**
  - the prep standard is written down (names, positions, colors, hot vs memory cue);
  - the tool route is decided (Mixed In Key import · manual · a mix), based on the test below;
  - tested on 10–20 tracks with measured time per track (before / after) and cue accuracy
    against my standard.

## Test plan: Mixed In Key cue points into rekordbox

Goal: does Mixed In Key's cue export reach rekordbox, and is it usable for my standard —
without touching library files or existing entries.

1. **Sandbox**: copy 5–10 representative tracks (different genres, one with existing cues
   as a reference) to `~/Music/_mik-test/` (outside `Library`). Import them into rekordbox
   as new entries in a playlist `_mik-test`; analyse BPM / grid in rekordbox.
2. **Baseline**: export the collection XML; note the test entries' cues (none) and the
   reference track's cues; hash the test files.
3. **Mixed In Key**: connect the exported XML, analyse only the `_mik-test` copies, export
   cue points to the XML (overwrite option as needed).
4. **Import**: in rekordbox reload the XML, import the playlist "MIK Cue Points".
5. **Check** (fresh XML export + `rb_compare.py`):
   - did the test entries get cues, how many, hot or memory, names / colors;
   - were existing entries reused (no duplicates), anything else changed (must be nothing);
   - do cue positions line up with the grid and with phrase starts (manual listening);
   - do the copies' hashes change (expected: yes, Mixed In Key writes GEOB frames).
6. **Map to my standard**: which of `start`, `bass`/`kick`, `main`, `breakdown`, `drop`,
   `outro`, `fade out` can be derived from Mixed In Key's energy cues; time to fix per track.
7. **Clean up**: remove the test entries from the collection, delete `~/Music/_mik-test/`
   (Julius), check `rb_compare.py` shows only the removed test entries.

Success criteria: cues arrive on existing entries without duplicates or side effects, and
fixing them to my standard is faster than placing them by hand.

## Approach backlog

Scores 1–3: L = learning per effort, V = value toward the goal, T = time to first signal,
R = risk / reversibility (3 = safe), C = cost (3 = cheap), F = fit.

| Approach | L | V | T | R | C | F | Status |
|---|---|---|---|---|---|---|---|
| Write down the prep standard (names, positions, colors, hot vs memory) | 3 | 3 | 3 | 3 | 3 | 3 | open |
| Measure the manual baseline: time per track for 5 tracks | 3 | 2 | 3 | 3 | 3 | 3 | open |
| Mixed In Key cue export via XML (test plan above) | 3 | 3 | 2 | 3 | 3 | 3 | open |
| Generate cues from rekordbox phrase data ourselves (XML import with my names) | 2 | 3 | 1 | 2 | 3 | 2 | open |
| Beat grid fine-tuning: rekordbox grid tools vs Mixed In Key grid | 2 | 2 | 2 | 3 | 3 | 2 | open |
| Review rekordbox Intelligent Cue Creation again (own exploration later) | 2 | 2 | 2 | 3 | 3 | 2 | deferred — revisit when the MIK test is done |

## Iterations

_None yet._ Suggested I1: "Does Mixed In Key's cue export reach rekordbox cleanly, and how
close is it to my standard?" (test plan above).

## Decisions

- 2026-11-14 — Not rekordbox's Intelligent Cue Creation for now (did not work well last time); reviewing it again is a later, separate exploration.
- 2026-11-14 — Mixed In Key only on copies until the music migration is done (it writes into files).

## Open questions

- [ ] Do Mixed In Key cues arrive as hot or memory cues, with which names and colors?
- [ ] Does rekordbox's XML import update cues of existing entries, or create new entries?
- [ ] Which of my cue names can be derived automatically (energy changes, phrases)?
- [ ] Hot cues, memory cues or both for my standard?

## Summary (when closed)

Outcome · decisions · learnings · artifacts · follow-ups.
