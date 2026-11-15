# rekordbox tagging and collection structure

| | |
|---|---|
| **Slug** | `rekordbox-tagging` |
| **Status** | active |
| **Started / last update** | 2026-11-14 / 2026-11-15 |
| **Budget** | 4 evenings, then end-of-budget review; €0 (rekordbox Creative plan, upgrade only if really necessary) |
| **Roadmap** | — |

## Brief

- **Purpose** — tags and a clear playlist structure are elementary building blocks for
  building sets (together with [`track-prep`](track-prep.md); set planning itself is
  [`dj-prep-workflow`](dj-prep-workflow.md)). Today the collection has no tags, a grown
  playlist tree with housekeeping lists, and few smart playlists.
- **Goal** — my own tag scheme v1 that serves two use cases, plus a simpler playlist
  structure with automated prep playlists and a few smart playlists:
  1. **Set building** — set position (warm-up, peak, closing), vibe, key.
  2. **At the decks** — a proven next track for the one playing; a fitting next track by
     energy and venue.
- **Non-goals / scope** — adopting Tobi's scheme (compare only after v1); track prep (beat
  grid, cues: `track-prep`); tags written into audio files; anything that changes the
  music files (storage-migration tracks them by sha256).
- **Context** — after the 2026-11-14 cleanup ([`music-collection-quality`](music-collection-quality.md),
  storage-migration): rekordbox 7.2.x, ~6,440 entries, all on serenity; date playlists
  `beatport/<YYYY>/<YYYYMMDD>`; `Past gigs/…`, `Setlists/…`, `Sessions/…`; intelligent
  playlists `By Key/…`, `Downtempo (80-105)`; housekeeping lists (`old storage`,
  `new storage`, `beatport dups`, `beatport/_w/o playlist`, `_older`, `_like w/o playlist`).
  Tobi (a friend) shared the handbook of his downtempo project (tag schema, set dramaturgy,
  craft notes); strongly tailored to downtempo, it covers only part of my styles. Analysis and
  collaboration live in the private repo `juliusblank/spannungsbogen` (created via
  `juliusblank/infra`, roadmap #20).
- **Constraints / risk tolerance** — tags only in rekordbox's library (My Tag); rekordbox
  changed only by rekordbox itself (UI, XML import), never by writing `master.db`;
  reading a `master.db` copy is fine. Mixed In Key writes analysis into files (see
  `hosts/serenity/configuration.nix`), so it is not a tagging tool here.
- **Prior knowledge / research** — rekordbox 7.2.18 manual (verified 2026-11-14,
  [PDF](https://cdn.rekordbox.com/files/20260807093645/rekordbox7.2.18_manual_EN.pdf)):
  - **My Tag** (p. 30): own tags in categories, several per track, track filter with
    AND / OR; can be copied into the Comments column (Preferences → Advanced → Browse).
  - **Matching** (p. 32, 75 and the 2-player section): "set 2 tracks as a good match
    combination", stored in the library; the button lights up blue when both are loaded.
    Not in the XML export (checked) — readable only from a `master.db` copy.
  - **Related Tracks** (p. 32): ranks tracks for the loaded track by conditions such as
    BPM, key, [Matching], genre, rating, My Tag.
  - **Track Suggestion** (p. 35): Collection Radar, Mood, Era, Association (needs
    Radar analysis).
  - **Intelligent playlists** (p. 58): filters with =, contains, range, "in the last" …;
    which fields (My Tag, Comments, color) are available is not verified yet.
- **References** — Tobi's handbook (analysis 2026-11-14 in `juliusblank/spannungsbogen`,
  private);
  storage-migration `tools/rb_compare.py`, `tools/rb_merge_xml.py` (playlist changes via
  XML import, proven 2026-11-14: rekordbox reuses existing entries).

## Scrutiny and verdict

- **Exists already?** — not in own docs (`music-collection-quality` excludes "a new tagging
  scheme"). rekordbox has the building blocks (My Tag, Matching, Related Tracks,
  intelligent playlists); Tobi's handbook is a starting point for downtempo.
- **Makes sense?** — yes: both use cases need data rekordbox can hold and query.
- **Knowledge level** — medium (rekordbox features known from the manual; tag design open).
- **Greenfield or researched before?** — greenfield for my scheme; Tobi's handbook as prior art.
- **Verdict** — **pursue**.

## Goal and definition of done

- **Goal** — as in the brief.
- **Non-goals** — as in the brief.
- **Done when**
  - tag scheme v1 written down: ~20–30 My Tags in a few categories, with a definition per tag;
  - applied to a defined track set (first: tracks in `Setlists/…` and `Past gigs/…`);
  - "proven next track" works at the decks via Related Tracks (Matching = my manual mark,
    highest; played-after-each-other pairs from gigs/setlists next);
  - 3–5 smart playlists built and used;
  - target playlist structure decided and migrated (housekeeping lists gone, automated
    prep playlists defined);
  - comparison with Tobi's scheme done, with a decision what to adopt.

## Tag scheme v1 (draft, interview 2026-11-15)

Not yet tested on tracks; the first 20-track test fine-tunes values and definitions.

| Field | Meaning | Values |
|---|---|---|
rekordbox has exactly four My Tag categories (renamable; today `Genre`, `Components`,
`Situation`, `storage`), so energy moves to the star rating.

| Field | Meaning | Values |
|---|---|---|
| **Rating** (stars) = energy | how the track feels in a set, calibrated against 2–3 reference tracks per level | 1–5 stars (0 = not rated yet) |
| Mixed In Key energy | automatic starting value, compared with my stars | 1–10 (if the MIK test shows a way into rekordbox) |
| My Tag **Components** (kept) | what is audible; existing tags stay, vocal tags added | `vocals:full` · `vocals:chops` · `vocals:spoken` · `vocals:none` (only if smart playlists can't filter "no vocal tag", see open questions) |
| My Tag **Set position** (renamed from `Genre`) | where it fits in a set; several allowed | warm-up · build · peak · closing · after-hours |
| My Tag **Situation** (kept) | where it fits; several allowed | club · open air / festival · bar / lounge · private party / wedding |
| My Tag **Vibe** (renamed from `storage`, after the library cleanup) | character; 1–2 per track | dark (minor, tense) · driving (forward push) · hypnotic (repetitive) · deep (warm, subdued) · groovy (swing, bouncy) · melodic (lead / harmony in front) · euphoric (uplifting) · playful (quirky, light) |
| Genre (column) | as delivered by the shop; not edited | — |
| Genre family | derived from the Genre column by script (`spannungsbogen` `genres/mapping.csv`), used for generated playlists; not a tag, not needed for v1 | 11 families (draft) |
| Colour | prep status | none = new · yellow = tagged · green = ready (grid + cues) · blue = proven (played in a set) · red = rejected |

Process: tag together with track prep (one pass per track); first set from `Setlists/…` and
`Past gigs/…`; energy reference tracks are picked after the Mixed In Key test
([`track-prep`](track-prep.md)), so energy tagging waits for it. My Tag → Comments: test on one
track first (what happens to existing comments, fresh XML export).

## Approach backlog

Scores 1–3: L = learning per effort, V = value toward the goal, T = time to first signal,
R = risk / reversibility (3 = safe), C = cost (3 = cheap), F = fit.

| Approach | L | V | T | R | C | F | Status |
|---|---|---|---|---|---|---|---|
| Draft tag categories from the two use cases (set position, vibe, energy, venue, …), test on 20 tracks | 3 | 3 | 3 | 3 | 3 | 3 | open |
| Mine "played after each other" pairs from `Past gigs` / `[as played]` playlists → candidates for Matching | 3 | 3 | 3 | 3 | 3 | 3 | open |
| Read Matching pairs from a `master.db` copy (how many exist, which tracks) | 2 | 2 | 2 | 3 | 3 | 2 | open |
| Verify intelligent-playlist fields (My Tag? Comments? color? rating?) in rekordbox | 3 | 2 | 3 | 3 | 3 | 3 | open |
| Target playlist structure (`Purchased` · `Friends` · `Recordings` · `Sets` · `Prep` · `Smart`), migrate via XML import | 2 | 3 | 2 | 3 | 3 | 3 | open |
| Automated prep playlists generated as XML (e.g. "proven after X", "new and untagged") | 2 | 3 | 2 | 3 | 3 | 2 | open |
| Analyse Tobi's handbook (research agent): summary, comparison, interview, collaboration repo | 3 | 2 | 3 | 3 | 3 | 3 | done (2026-11-14) |
| Shared private repo with Tobi (taxonomy core + genre extensions + dramaturgy) | 2 | 2 | 1 | 3 | 3 | 2 | done — `spannungsbogen` (2026-11-15) |
| Genre families + mapping of the 112 rekordbox genres; fill the 589 empty genres (Beatport IDs, Bandcamp tags, by hand) | 3 | 2 | 2 | 3 | 3 | 3 | open |

## Iterations

_None yet._ Research on Tobi's handbook done 2026-11-14 (report in `spannungsbogen`); it
feeds I1.

## Decisions

- 2026-11-14 — Tagging and track prep are separate explorations: elementary building blocks for set building.
- 2026-11-14 — Start with my own tag group (simple), compare with Tobi's afterwards.
- 2026-11-14 — "Proven next track": one transition relation with a single score (my manual Matching mark highest, then pairs played in gigs/setlists), evidence kept separately so the weighting can change.
- 2026-11-14 — Collaboration with Tobi preferably in a private GitHub repo in my account (to be proposed by the research).
- 2026-11-15 — Repo `juliusblank/spannungsbogen` (private, via OpenTofu in `juliusblank/infra`): the shared parts only (taxonomy, genres, dramaturgy, craft, prompts); my tools stay in `scripts/dj`.
- 2026-11-15 — Energy: no star rating; candidate is a My Tag category with ~5 levels, calibrated against reference tracks (as Tobi does with his 1–10 scale).
- 2026-11-15 — Start my own genre families with a mapping from the raw genres; cover the tracks without genre.
- 2026-11-15 — Tag scheme v1 draft (interview): six My Tag categories (Energy E1–E5, Set position, Vibe, Situation, Vocals, Family); Mixed In Key's 1–10 as an automatic starting value next to my own levels; colour = prep status (5 steps incl. rejected); rating unused; raw Genre column untouched (families in My Tag, avoids possible file writes).
- 2026-11-15 — Tag together with track prep; first set from setlists / past gigs; energy references after the Mixed In Key test.
- 2026-11-15 — Only four My Tag categories: energy = star rating (replaces "no star rating" above; frees a category, 5 steps, shown on the CDJs, usable by Related Tracks and intelligent playlists); `Components` kept with `vocals:*` tags added; `Genre` → Set position; `Situation` kept; `storage` → Vibe after the cleanup. Genre family is no tag (derived from the Genre column when needed).

## Open questions

- [x] Which tag categories and values (v1)? — draft above (2026-11-15); to be tested on 20 tracks.
- [ ] Which fields can intelligent playlists filter on (My Tag, Comments, color, rating)?
- [ ] How many Matching pairs exist today; can they be read reliably from a `master.db` copy?
- [x] Venue and energy: My Tag, rating, color — which field for what? — situation My Tag, energy = rating, colour = prep status (2026-11-15).
- [ ] Which prep playlists can be generated automatically, and how often refreshed?
- [ ] What to adopt from Tobi's handbook, what to extend for techno / house / psy?
- [ ] Which genre families (v1)? — draft of 11 in `spannungsbogen` PR #2; derived from the Genre column, not a tag.
- [ ] My Tag → Comments: does it overwrite or append to existing comments?
- [x] How many My Tag categories does rekordbox allow? — four, renamable (checked in rekordbox
  and manual p. 30, 2026-11-15); tags per category: no limit seen.
- [ ] Can an intelligent playlist or the track filter express "has no `vocals:*` tag"? If not,
  keep `vocals:none` (the track filter has only AND / OR).
- [ ] Bulk updates of My Tags / ratings without the UI: does XML import update the rating of
  existing entries? (Verified 2026-11-15: the XML export has `Rating` (0/51/102/153/204/255)
  and `Comments`, but no My Tag field.)
- [ ] 404 tracks already carry stars (export 2026-11-15: 14 × 1, 39 × 2, 30 × 3, 99 × 4,
  222 × 5): what do they mean today, and do they get reset or converted before stars mean
  energy?

## Summary (when closed)

Outcome · decisions · learnings · artifacts · follow-ups.
