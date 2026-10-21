# DJ preparation workflow

| | |
|---|---|
| **Slug** | `dj-prep-workflow` |
| **Status** | active |
| **Started / last update** | 2026-10-17 / 2026-10-21 |
| **Budget** | open; per iteration (see below). Money: Harmonic DJ Pro ($40) only at the decision gate |
| **Roadmap** | #32 (Harmonic DJ evaluation); related #15, #16 |

Detailed evidence: [`docs/harmonic-dj.md`](../harmonic-dj.md). Spec: `docs/SPEC.md` →
*DJ Toolchain → Harmonic DJ*.

## Brief

- **Purpose** — spend less time compiling set playlists and listening through them to
  hear whether the tracks fit together.
- **Goal** — for a set I have pre-selected, get a good running order (key, BPM, energy)
  with little effort, and have it in rekordbox ready to play.
- **Non-goals / scope** — replacing rekordbox as the library or the key / BPM analyzer;
  writing into rekordbox's database or XML import; tag writing.
- **Context** — dig on Spotify → buy on Beatport → library folder per purchase date →
  rekordbox (analysis, cue points) → sets ordered by hand with Camelot.
- **Constraints / risk tolerance** — no writes into rekordbox's data (M3U import only);
  local over cloud; one-time payment over subscriptions; work on copies when touching
  files.
- **Prior knowledge / research** — `docs/harmonic-dj.md` (vendor research, install,
  storage, tests T1–T4, rekordbox limitations).
- **References** — Harmonic DJ <https://apu.software/hdj/>; rekordbox 7.2.16 manual;
  DJ.Studio, SetFlow and other set planners (see backlog).

## Scrutiny and verdict

- **Exists already?** Yes, a whole category: Harmonic DJ, DJ.Studio, SetFlow, Mixgraph,
  Djoid, MixReady; online playlist analyzers (TuneBad, Song Finder, Brizm). None avoids
  rekordbox's M3U `#` limitation; only Harmonic DJ and DJ.Studio analyze audio
  themselves, only Harmonic DJ has modes and in / out keys.
- **Makes sense?** Yes — the workflow round trip works (T1, T2); the value of the
  suggestions (T5) is the open question.
- **Knowledge level** — high on the workflow and rekordbox; medium on the tools.
- **Greenfield or researched before?** Researched: started as the Harmonic DJ
  evaluation (roadmap #32) on 2026-10-17.
- **Verdict** — **pursue**, with Harmonic DJ as the main candidate.

## Goal and definition of done

- **Goal** — plan real sets from a pre-selected rekordbox base list with a tool
  (Harmonic DJ first), bring the order back into rekordbox, and save time.
- **Non-goals** — see Brief.
- **Done when** —
  - T5 passes for at least one real set: the tool's order saves time against compiling
    and listening by hand, and its transitions are at least as good as my own order;
  - the tool decision is made (Harmonic DJ Community / Pro, or an alternative);
  - the analysis scope is decided (which parts of the collection the tool analyzes);
  - the workflow is written down so it is repeatable.

## Approach backlog

Scores 1–3: L = learning per effort, V = value toward the goal, T = time to first signal,
R = risk / reversibility (3 = safe), C = cost (3 = cheap), F = fit.

| Approach | L | V | T | R | C | F | Status |
|---|---|---|---|---|---|---|---|
| T5a — real set in Harmonic DJ, base list only | 3 | 3 | 2 | 3 | 2 | 3 | open (next) |
| T6 — base list with a track HDJ has not analyzed | 3 | 2 | 3 | 3 | 3 | 3 | open (next) |
| T5b — HDJ adds tracks from a larger analyzed pool | 2 | 3 | 1 | 3 | 2 | 2 | open (needs scope + cleanup) |
| DJ.Studio 7-day trial, same set (without rekordbox link) | 2 | 2 | 2 | 2 | 2 | 2 | open |
| Own ordering script on HDJ's DB data (→ MCP #16 later) | 2 | 2 | 2 | 3 | 3 | 3 | open |
| Online analyzer check (TuneBad / Song Finder) against T4 references | 2 | 1 | 3 | 2 | 3 | 2 | open (pre-buy check) |
| Beatport previews analyzed in HDJ before buying | 1 | 2 | 1 | 3 | 3 | 2 | open (larger topic, #15) |
| rekordbox Spotify integration: keys for Spotify tracks? | 2 | 1 | 3 | 3 | 3 | 2 | open (1-minute check) |
| T4 listening on 4–5 major / minor cases | 1 | 1 | 2 | 3 | 3 | 3 | optional |
| Rename the 126 files with `#` + relocate in rekordbox | 1 | 2 | 1 | 1 | 3 | 2 | later (own step) |
| T3 — write HDJ data into tags | — | — | — | — | — | — | deferred (not needed) |
| rekordbox XML import / direct DB writes (Mixo-style) | — | — | — | — | — | — | dropped (risk) |

## Iterations

### I1 — Does Harmonic DJ run cleanly and safely next to rekordbox? (2026-10-17)

- **Selected approaches:** nix derivation (app only, no plug-ins) and first run on
  serenity; storage check; restore test.
- **Results** — app installs from the notarized dmg (signature intact); data in
  `~/Library/APU Harmonic DJ/` + `~/Library/Application Support/APU Harmonic DJ/`;
  restore test passed (DB byte-identical, no rescan); key profile is a per-Mix setting;
  key codes decoded (number = Camelot of the parent major scale, letter = mode).
- **Conclusions** — safe to evaluate; backup is two folders, app closed.
- **Consequences applied** — backup handoff for #126 (paths, `inhibitApps`); spec
  storage table and open questions updated.
- **Goal check** — continue.

### I2 — Does the round trip with rekordbox work, and are the keys trustworthy? (2026-10-17/18)

- **Selected approaches:** T1 (Mix → M3U → rekordbox), T2 (rekordbox → HDJ → rekordbox),
  T4 (key / BPM comparison script on 27 tracks).
- **Results** —
  - T1 / T2 **passed with limitations**: tracks resolve to existing entries, order and
    duplicates kept, NFC / NFD names fine; rekordbox **drops tracks with `#` in the
    path** (its own M3U import limitation, ~2 % of the library) and always creates
    `<name> (1)` instead of importing over a playlist.
  - T4: roots agree almost always; rekordbox says minor for 25 of 26 tracks where
    Beatport and HDJ mostly say major / a major mode; BPM HDJ = rekordbox on all 27.
- **Conclusions** — the workflow works; rekordbox stays the analyzer; the tool's value
  is in ordering, not in replacing keys.
- **Consequences applied** — **intended use = set planning only** (spec purpose and
  workflow); T3 deferred; T4 listening optional; T5 refined (a: base list only,
  b: larger pool); T6 added; analysis-scope step in the decision gate; `#` known issue
  + rename TODO; XML import ruled out; scripts in `scripts/dj/`.
- **Goal check** — goal sharpened to the planning-only use; next: T5a and T6.

## Decisions

- 2026-10-17 — Harmonic DJ as a nix derivation, app only, serenity only — reproducible,
  no plug-ins in `/Library`.
- 2026-10-17 — rekordbox XML import and direct DB writes ruled out — risk of
  overwriting existing track data.
- 2026-10-18 — Intended use: set planning from a pre-selected base list; rekordbox
  stays the analyzer — matches the purpose, avoids tag writing.
- 2026-10-18 — Analysis scope is decided after T6; `rekordbox_backup/` is never
  analyzed.

## Open questions

- [ ] T5: does a tool-made order save time and sound at least as good as mine?
- [ ] T6: what does HDJ do with base-list tracks it has not analyzed?
- [ ] Pro needed? Community saves at most 5 tracks per Mix; real sets have ≈ 15–30.
- [ ] Which generator settings (BPM range, key strictness) give useful orders?
- [ ] Analysis scope: curated subset, grow on demand, or whole collection?
- [ ] Where is the Pro license stored (check on trial start)?
- [x] Key codes vs Camelot — answered (I1).
- [x] Where the key profile is stored — per Mix (I1).
- [x] M3U path matching — works incl. NFC / NFD; `#` paths dropped by rekordbox (I2).

## Summary (when closed)

—
