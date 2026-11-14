# rekordbox tagging and collection structure

| | |
|---|---|
| **Slug** | `rekordbox-tagging` |
| **Status** | active |
| **Started / last update** | 2026-11-14 / 2026-11-14 |
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
  Tobi (a friend) shared a project of agent instructions for several AI models for tagging,
  strongly tailored to downtempo; it covers only part of my styles.
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
- **References** — Tobi's archive (`JuliusPUNKTzip.7z`, research report pending);
  storage-migration `tools/rb_compare.py`, `tools/rb_merge_xml.py` (playlist changes via
  XML import, proven 2026-11-14: rekordbox reuses existing entries).

## Scrutiny and verdict

- **Exists already?** — not in own docs (`music-collection-quality` excludes "a new tagging
  scheme"). rekordbox has the building blocks (My Tag, Matching, Related Tracks,
  intelligent playlists); Tobi's project is a starting point for downtempo.
- **Makes sense?** — yes: both use cases need data rekordbox can hold and query.
- **Knowledge level** — medium (rekordbox features known from the manual; tag design open).
- **Greenfield or researched before?** — greenfield for my scheme; Tobi's project as prior art.
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
| Analyse Tobi's project (research agent): summary, comparison, interview, collaboration repo | 3 | 2 | 3 | 3 | 3 | 3 | selected |
| Shared private repo with Tobi (taxonomy core + genre extensions + agent instructions) | 2 | 2 | 1 | 3 | 3 | 2 | open |

## Iterations

_None yet._ Started 2026-11-14 with the research agent on Tobi's archive (results feed I1).

## Decisions

- 2026-11-14 — Tagging and track prep are separate explorations: elementary building blocks for set building.
- 2026-11-14 — Start with my own tag group (simple), compare with Tobi's afterwards.
- 2026-11-14 — "Proven next track": one transition relation with a single score (my manual Matching mark highest, then pairs played in gigs/setlists), evidence kept separately so the weighting can change.
- 2026-11-14 — Collaboration with Tobi preferably in a private GitHub repo in my account (to be proposed by the research).

## Open questions

- [ ] Which tag categories and values (v1)?
- [ ] Which fields can intelligent playlists filter on (My Tag, Comments, color, rating)?
- [ ] How many Matching pairs exist today; can they be read reliably from a `master.db` copy?
- [ ] Venue and energy: My Tag, rating, color — which field for what?
- [ ] Which prep playlists can be generated automatically, and how often refreshed?
- [ ] What to adopt from Tobi's project, what to extend for techno / house / psy?

## Summary (when closed)

Outcome · decisions · learnings · artifacts · follow-ups.
