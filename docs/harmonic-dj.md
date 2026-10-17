# Harmonic DJ (APU Software) — research note

> Phase 1 of the Harmonic DJ integration (roadmap: DJ toolchain). Researched 2026-10-17
> against the vendor site and docs. "Not determined" means the sources do not say; it is
> not a guess. Third-party sources are marked.

## Sources

- Product page: https://apu.software/hdj/
- Docs (manual): https://docs.apu.software/hdj/manual/
- Manual PDF (1.2.9): https://apu.software/release/APU-HarmonicDJ-Manual-1.2.9.pdf
- Download page: https://apu.software/download/#ref-hdj
- Privacy policy: https://apu.software/privacy-policy/
- Refunds: https://apu.software/refunds/
- Launch article (3rd-party): https://rekkerd.org/plan-harmonic-dj-sets-with-apu-softwares-harmonic-dj/

## Findings

### 1. Distribution

| Platform | Format | Content | URL pattern |
|---|---|---|---|
| macOS | `.dmg` installer, universal | App + VST3 / AU / AAX plug-ins | `https://apu.software/release/APU-HarmonicDJ-Installer-<v>.dmg` |
| Windows | installer `.zip` (x64, x86) | App + VST3 / AAX | `…-Installer-<v>.zip`, `…-Installer-<v>-x86.zip` |
| Linux | `.zip` (x64) | App + VST3; format inside not determined | `…-Linux-x64-<v>.zip` |

- Current version: **1.2.9**, files dated 2026-10-02. Verified with HEAD requests: the dmg
  is 54,648,046 bytes and the Linux zip is 19,514,625 bytes.
- Download URLs include the version, and older versions stay online (1.2.8 and 1.2.0
  return 200). So a `fetchurl` pin with a hash is possible. The ETags are S3 multipart
  ETags, not content hashes, so we must compute the hash ourselves.
- No AppImage, `.deb` or App Store build. The macOS dmg also installs plug-ins into the
  system plug-in folders.
- macOS code-signing and notarization: signed and notarized (see *Inspection* below).
- Changelog: not determined. No public release notes were found.

### 2. Packaging availability

- **nixpkgs:** not packaged. GitHub code search for `apu.software` and `harmonic-dj` gave
  0 hits.
- **NUR or community flakes:** none found.
- **Homebrew cask:** none. `formulae.brew.sh` returned 404 for the likely names, and
  homebrew-cask code search gave 0 hits.

### 3. Licensing and activation

- **Editions:** Community is free: unlimited local analysis, and saved Mixes of up to
  5 tracks each, with no limit on the number of Mixes. Pro is **$40.00 one-time**
  (product page, 2026-10-17). The 3rd-party launch article gave $80 regular and $60
  introductory.
- **Activation:** Community needs no account. You start the Pro trial or enter the
  license (serial) in **About**. "License validation is local and does not require
  online activation" (privacy policy).
- **When Pro lapses:** the app goes back to Community, and your data stays.
- **Not determined:** machine binding, machine count, and where the license is stored.
- **Conflict with declarative config:** activation is a manual step in the GUI. We
  cannot inject the license until we know where it is stored.

### 4. Data storage

- **Library:** one local database, owned by the standalone app. The plug-ins use the
  same database.
- **Mixes:** save automatically, with a revision-history manifest.
- **Exchange formats:**
  - `.hdjmix`
  - `.hdjcollection`: versioned, contains no file paths
  - Library-metadata JSON export: contains file paths
- **The docs do not say:** the database engine, the paths, or whether the location can
  be changed. For the macOS paths and the SQLite format, see *Throwaway test run* below.
  We found no setting to move the location.

### 5. Import / export

- **Library input:** folder scan or drag-in, plus M3U/M3U8 import.
  - **rekordbox XML:** not mentioned.
  - **Traktor NML:** "not supported".
- **Export:**
  - M3U, with absolute paths
  - "Copy Tracklist", as text
  - `.hdjmix`, `.hdjcollection` and Library-metadata JSON
  - No CSV.
- **Tags:** read with TagLib. Corrections "do not rewrite source tags". We found nothing
  that says it writes key or BPM tags into files.
- **Key notation:**
  - Keys show as root + mode, in six modes: Ionian, Dorian, Phrygian, Lydian,
    Mixolydian, Aeolian. There is no Locrian.
  - Separate incoming and outgoing keys come from the first and second half of each
    track.
  - The docs mention Camelot only as not enough to describe a track. A Camelot display
    option: not determined.

### 6. CLI / API

No CLI, headless mode, scripting or API is documented. The only integration surface is
the DAW plug-ins (VST3 / AU / AAX).

### 7. Published tracklist pages

- **Where:** pages are hosted at `https://apu.software/mix/…` and loaded from
  `api.apu.software`.
- **Setup:** the first publish needs email verification, then stores a publishing
  credential on the computer.
- **Uploaded:** title, byline, track display names, keys, BPM and the transition
  strategy.
- **Not uploaded:** audio, paths, ratings, groups and raw analysis.
- **Visibility:** pages are public and can be indexed. Unpublish retires the URL.

## Inspection of the 1.2.9 macOS dmg (2026-10-17)

I downloaded the dmg to a scratch directory, mounted it read-only, and expanded the
package with `pkgutil --expand-full`. Nothing was installed.

- **Hashes:** sha256 `9c5c33ae660e42c2cc9a526b3c97da2a54365e381a11a8724840f36ccc8bedaa`
  (SRI `sha256-nFwzrmYOQsLMmlJrPJfaKlQ2XjgaEahySEDzbMyL7ao=`).
- **dmg content:** only `APU-HarmonicDJ-1.2.9.pkg`, a distribution package.
  - Signed "Developer ID Installer: APU Software, LLC (RPGGCLW336)".
  - Notarized: `spctl` reports "accepted, Notarized Developer ID".
- **Component packages:**

  | Package ID | Installs to | Installer choice |
  |---|---|---|
  | `com.apusoftware.pkg.APUHarmonicDJ.Standalone` | `/Applications/APU Harmonic DJ.app` | Always selected (cannot be turned off) |
  | `com.apusoftware.pkg.APUHarmonicDJ.VST3` | `/Library/Audio/Plug-Ins/VST3` | Optional |
  | `com.apusoftware.pkg.APUHarmonicDJ.AU` | `/Library/Audio/Plug-Ins` | Optional |
  | `com.apusoftware.pkg.APUHarmonicDJ.AAX` | `/Library/Application Support/Avid/…` | Optional |

- **App bundle:**
  - Bundle ID `com.APUSoftware.APUHarmonicDJ`, version 1.2.9.
  - Universal binary (x86_64 + arm64), macOS 10.14 or later.
  - Hardened runtime, Developer ID Application, notarized.
  - The Standalone component has no install scripts, so the app can be copied out of
    the payload as-is.
- **Strings in the binary.** These are clues only; a real install must confirm them:
  - SQLite is linked in.
  - Names: `Harmonic DJ Library.json`, `.mix-publishing.settings`, file types
    `*.hdjmix`, `*.hdjcollection`, `*.hdjprofile`, and an "Application Support"
    reference.
  - There is a "Harmonic DJ Library agent", which looks like a separate process for the
    library.
  - An update check calls apu.software ("Load current APU Software release information").
  - Exact data paths: still not determined.
- **Nix packaging:** a derivation can unpack the dmg (`undmg`), then the pkg (`xar` and
  `cpio`), then copy only the Standalone payload. Both tools are in nixpkgs.

## Throwaway test run on concinnity (2026-10-17)

I started the 1.2.9 app from the unpacked payload in a scratch directory (not installed),
added a test folder with 4 MP3s, and let it analyze them. Then I deleted all files it
created.

- **`HOME` is ignored.** This is a JUCE app, and it writes to the real `~/Library` even
  when `HOME` points somewhere else, so you cannot isolate it that way.
- **Data and settings locations (confirmed):**

  | Path | Content | Format |
  |---|---|---|
  | `~/Library/APU Harmonic DJ/harmonic-dj.sqlite` | Library: tracks, analysis, ratings, groups, Gems, scan queue | SQLite, `journal_mode=delete` (no WAL) |
  | `~/Library/APU Harmonic DJ/mixes.json` | Mix catalog (IDs, names, active Mix) | JSON |
  | `~/Library/APU Harmonic DJ/mixes/<id>.hdjmix` | One file per Mix | JSON (`.hdjmix`) |
  | `~/Library/APU Harmonic DJ/mix-history/<id>/` | Revision history per Mix | not inspected |
  | `~/Library/Application Support/APU Harmonic DJ/APU Harmonic DJ.global.settings` | App settings (`appearanceMode`, `scaleFactor`, column layouts, …) | JUCE XML `<PROPERTIES>` |
  | `~/Library/Preferences/com.APUSoftware.APUHarmonicDJ.plist` | Only file-dialog state | plist |
  | `~/Library/Caches/com.juce.locks/juceAppLock_APU Harmonic DJ` | Single-instance lock | empty |
  | `~/Library/Containers/com.APUSoftware.APUHarmonicDJ.APUHarmonicDJAUv3/` | Sandbox container of the AUv3 plug-in | system-managed |

- **Embedded AUv3 plug-in.** The app bundle contains
  `Contents/PlugIns/APU Harmonic DJ.appex`, which macOS registers at first launch. So an
  "app only" install still adds an Audio Unit. Removing it would break the code signature.
- **No license file appeared.** We did not start the Pro trial or activate Pro, so where
  the license is stored is still not determined.
- **Database schema (relevant tables):**
  - `tracks`:
    - Primary key `path`, which is **absolute**.
    - `portable_id`, `content_hash`, `bpm`, `bpm_accuracy_percent`.
    - `key_analysis` (JSON), `level_analysis`.
  - `track_key_profiles`:
    - One row per track and loudness contour profile (`none`, `ecma418`,
      `iso226-2003@68…92`, `iso226-2023@68…92`).
    - Key columns: `key`, `keycode`, `key_mode`, `key_accuracy_percent`.
    - In / out keys: `key_start` / `key_end`, `keycode_start` / `keycode_end`.
  - `track_ratings` (1–5).
  - Other tables: `track_bpm_overrides`, `library_groups`, `track_group_membership`,
    `gem_transitions`, `track_path_aliases`, `remote_collection*`.
- **Key codes.** These look like Camelot numbers with a mode letter, for example `09A`
  (aeolian), `12L` (lydian), `07P` (phrygian), `04D` (dorian), `07M` (mixolydian). The
  letter for Ionian is not seen yet. The number for Lydian, Phrygian and other modes does
  not match the Camelot number of the root (for example A lydian = `12L`). The mapping
  must be confirmed before anyone compares it with rekordbox's Camelot keys.
- **Result differs by profile.** The key often changes with the loudness profile. One
  track was `Em phrygian` with `none` but `Bm phrygian` with most ISO profiles. Key
  accuracy was 50–57 % on all 4 test tracks. Which profile the UI shows is set in the
  app.
- **Backup:**
  - **Tested:** copying `~/Library/APU Harmonic DJ/` while the app was closed gave a
    database that passed `PRAGMA integrity_check`.
  - **Restore with the app:** tested on serenity, see *Restore test* below (passed).
  - **Gotcha:** both data folders are named `APU Harmonic DJ`. Copy them to separate
    destinations, or they merge.

## Evaluation on serenity

### Setup (2026-10-17)

- **Install:** module `custom.harmonicDj` deployed (generation 101, branch
  `docs/harmonic-dj`). App: `~/Applications/Home Manager Apps/APU Harmonic DJ.app` →
  nix store. `codesign --verify --deep --strict` ok; `spctl`: Notarized Developer ID.
- **First run:** one click (appearance setup). No library folder or license prompt.
- **Files created** (all files newer than a marker set before first launch):

  | Path | In *Storage* table? |
  |---|---|
  | `~/Library/APU Harmonic DJ/` (`harmonic-dj.sqlite`, `mixes.json`, `mixes/`, `mix-history/`) | yes |
  | `~/Library/Application Support/APU Harmonic DJ/APU Harmonic DJ.global.settings` | yes |
  | `~/Library/Application Support/APU Harmonic DJ/APU Harmonic DJ.settings` | **new**: window position, `audioSetup`, `filterState` (plugin editor state) |
  | `~/Library/Preferences/com.APUSoftware.APUHarmonicDJ.plist` | yes (do not back up) |
  | `~/Library/Containers/com.APUSoftware.APUHarmonicDJ.APUHarmonicDJAUv3/` | yes (do not back up) |
  | `~/Library/Application Scripts/com.APUSoftware.APUHarmonicDJ.APUHarmonicDJAUv3/` | **new** (AUv3, system-managed; do not back up) |
  | `~/Library/Caches/com.juce.locks/juceAppLock_APU Harmonic DJ` | yes (do not back up) |
  | `/private/var/folders/…/C/com.APUSoftware.APUHarmonicDJ` | yes (cache; do not back up) |

  Paths match the concinnity run. A default empty Mix is created at first launch.
- **Defaults** (UI toolbar, unchanged): key profile `ECMA-418 (Precise)`, level reference
  `K-System (83 dB SPL)`, Active Mix target `-14.0 LUFS` (pre-limiter). Neither settings
  file stores the profile. `filterState` in `.settings` is a JUCE base64 block
  (`<size>.<data>`); decoded, it is the plugin editor state only:
  `<APUHarmonicDJ editorWidth="1152" editorHeight="648" chordGain="-18.0" preferDark="1"
  hostBPM="0"/>`.
- **Where the profile is stored (answered).** The toolbar profile is a **per-Mix
  setting**: `settings.keyProfile` in the active Mix's `mixes/<id>.hdjmix` (switching
  to ISO 226-2003 @ 83 changed it from `ecma418` to `iso226-2003@83`, and added a
  "Change Key Profile" revision to `mix-history/<id>/history.json`). It survives
  restarts. Other per-Mix settings in the same object: `targetLufs` (-14.0), `keyModel`
  (`benchmark-guided-modal`), `bpmStrategy` (`rounded-match`), `keyChangePolicy`,
  `keyMatchingScope`, `allowedModes` / `allowedRoots` (bit masks, all set), pitch-shift
  limits and the transition preset (`factory/general-purpose`). Not checked yet: which
  profile a **new** Mix starts with.

### Restore test (2026-10-17): passed

With the app closed:
1. `ditto` both folders to separate destinations (`hdj-data/`, `hdj-settings/`);
   `integrity_check` = `ok`; per-file `shasum` manifest saved.
2. Moved the originals away (same effect as deleting, but reversible), then `ditto`
   the copies back. Restored files equal the manifest.
3. Started the app: 27 tracks, group `evaluation`, keys and BPM shown, status **Ready**,
   nothing queued. Quit the app, and check with `pgrep` that it is gone before copying.
4. Compared the DB after the run with the backup: `harmonic-dj.sqlite` and all Mix
   files are **byte-identical**; `tracks` (`scanned_time_ms`, `status`, `content_hash`,
   analysis columns), `track_key_profiles`, groups, membership and scan queues show
   0 differences. → **No rescan.**
5. The only changed file is `.settings`: `filterState` is rewritten on quit
   (`chordGain` `-18.0` → `-18.00000190734863`, float formatting only).

### Evaluation folder

- **Path:** `/Users/jbl/Music/purchased/Beatport/2026/20260507` — 27 AIFF tracks, added
  with **Add Folder** into a new library group `evaluation`.
- **Beatport file names.** Newer Beatport downloads are named
  `<date>_<Artist>_<Title>_(<Mix>)_<id>_<BPM>_<Key>_<Quality>_<nn>.aiff`. This covers the
  evaluation folder (26 of 27 have a key; one has an empty key field), so Beatport is a
  third reference for T4 here. Older parts of the library do not use this format.

### Database after the first analysis (copy, read-only)

- `pragma integrity_check` = `ok`, `journal_mode` = `delete`, 655 KB for 27 tracks.
- `tracks`: 27 rows, all with BPM; `path` is the absolute file path.
- `library_groups`: `evaluation` with 27 members.
- `track_key_profiles`: 14 profiles × 27 tracks. `profile_id` values: `none`, `ecma418`,
  `iso226-2003@{68,73,79,83,85,92}`, `iso226-2023@{68,73,79,83,85,92}` (the number is
  the reference SPL). `key` / `keycode` hold `start->end` when in and out keys differ,
  e.g. `Bbm aeolian->F ionian` / `03A->07B`. `key_root_value` counts from A = 0.

### Key-code mapping (answered)

Checked on all 490 key values (14 profiles, in and out keys) with a script on a DB copy;
0 mismatches:

- **Number** = Camelot number of the mode's **parent major scale** (root minus the mode
  offset: ionian 0, dorian 2, phrygian 4, lydian 5, mixolydian 7, aeolian 9 semitones).
- **Letter** = mode: `B` ionian, `D` dorian, `P` phrygian, `L` lydian, `M` mixolydian,
  `A` aeolian.
- Examples: `Gbm phrygian` → parent D major = 10 → `10P`; `E dorian` → parent D major →
  `10D`; `A lydian` → parent E major → `12L`.
- **Consequence:** `B` and `A` codes are plain Camelot. Equal numbers mean the same set of
  notes, so `10P`, `10D`, `10B` and `10A` share a scale. For rekordbox comparisons, map
  modes to major / minor first (rekordbox has only these two).

### First look: HDJ (`ecma418`) vs Beatport file name

Not T4 yet (rekordbox is missing); a pre-check on 26 tracks with a Beatport key:

| | Count |
|---|---|
| Same root and major / minor quality (lydian, mixolydian count as major; dorian, phrygian, aeolian as minor) | 19 |
| Same parent scale (relative / modal neighbour) | 2 |
| Different | 5 |

BPM: 22 equal (rounded), 4 different, none half / double (Beatport 125 → HDJ 101.9,
142 → 105.0, 162 → 102.1, 80 → 107.1). Check these four in rekordbox and by ear in T4.

### T1a — Mix into rekordbox, ASCII paths (2026-10-17): passed

- **HDJ:** new Mix `evaluation T1` (source group `evaluation`, target 5 tracks). A new
  Mix starts with `keyProfile` `ecma418`; it does not inherit the profile of the other
  Mix. "Generate Tracklist" filled only 3 tracks (segment 1–3), probably because of the
  Mix defaults `maximumBpmDifference: 0` and `bpmStrategy: rounded-match`.
- **M3U export** (`~/Documents/evaluation T1.m3u`): `#EXTM3U`, `#EXTENC:UTF-8`,
  `#PLAYLIST:<name>`, then one absolute path per line; CRLF line endings; no `#EXTINF`.
  All 3 paths exist and equal `tracks.path` in the HDJ DB byte for byte.
- **rekordbox 7.2.14 import:** playlist `evaluation T1` with 3 tracks, no missing-file
  marker, waveforms / analysis present. Collection count unchanged (7037 before and
  after) → no duplicates. Track 1 shows `DJ Play Count` 5, so rekordbox reused the
  existing collection entry (a new entry would start at 0).
- **Not covered:** non-ASCII paths (see below) → T1b.

### Unicode normalization (found during T1)

The files on disk have **NFD** names (decomposed, e.g. `a` + U+0301), but HDJ stores and
exports paths in **NFC** (composed `á`). Seen on all 4 non-ASCII names in the evaluation
folder (`gázel` ×2, `kośa`, `Überhaupt`). APFS resolves both forms to the same file, so
HDJ can open them. rekordbox matches the NFC path to its collection entry (T1b).

### T1b — non-ASCII and `#` paths (2026-10-17): failed on `#`

- **HDJ:** Mix `evaluation T1b`, 5 tracks, incl. `gázel – Binary Affection` (locked)
  and `Temple Tears – Reda` (path contains `F#`). M3U as in T1a; `gázel` exported as NFC.
- **rekordbox 7.2.14** (File → Import → Import Playlist): playlist with **4 of 5 tracks**,
  collection count unchanged (7037).
  - `gázel` (NFC in the M3U, NFD on disk): **imported**, existing entry → Unicode
    normalization is **not** a problem.
  - `Reda` (`…_110_F#_Minor_07.aiff`): **silently dropped**, although it is in the
    collection. Likely cause: rekordbox treats `#` as a URL fragment and truncates the path.
- **Scope:** 126 of 6217 audio files under `~/Music` (~2 %) have `#` in the path (107 in
  the file name, mostly Beatport keys like `F#_Minor`; the rest via 46 folders).

### T1c — M3U workarounds for `#` (2026-10-17): none works

Single-track M3Us for `Reda` (`~/Documents/hdj-t1c/`), imported one by one:

| Variant | Result | rekordbox import log |
|---|---|---|
| Plain path with `#` (as HDJ exports) | 0 tracks, no message | not listed — the line is skipped, as if it were a comment |
| `file:///…F%23_Minor…` (percent-encoded URL) | 0 tracks, error dialog | listed as `…%28Original_Mix%29…F%23…` — `file://` stripped, escapes **not decoded** |
| Plain path with `%23` | 0 tracks, error dialog | listed as `…F%23_Minor…` — not decoded |

The log is written to `~/Documents/rekordbox/Import Log - <date>.txt` (UTF-16 LE, CRLF),
not to `~/Documents` as the dialog says. **Result:** no M3U spelling brings a path with
`#` into rekordbox 7.2.14; the plain form fails silently.

### Known issue: HDJ M3U drops tracks with `#` in the path (open)

- **Symptom:** a track whose path contains `#` is missing after importing an HDJ M3U
  into rekordbox 7.2.14. No error, no log entry. Affects ~2 % of the library (126 files).
- **Contrast:** rekordbox's own playlist export (`20260507.m3u8`) contains the **same
  path bytes** for `Reda`, and re-importing it keeps the track (user test, 2026-10-17).
  The formats differ:

  | | rekordbox export (works) | HDJ export (drops `#` lines) |
  |---|---|---|
  | Extension | `.m3u8` | `.m3u` |
  | Before each path | `#EXTINF:<seconds>,<Artist> - <Title>` | nothing |
  | Header | `#EXTM3U` | `#EXTM3U`, `#EXTENC:UTF-8`, `#PLAYLIST:<name>` |
  | Encoding / line ends | UTF-8, CRLF | UTF-8, CRLF |

- **Hypothesis (not tested):** rekordbox accepts a `#` path only right after an
  `#EXTINF` line, or decides by the `.m3u8` extension. A single-track test with
  `#EXTINF` and / or `.m3u8` would tell; same risk as T1c (playlist import only).
- **Not pursued for now:** rekordbox XML import (risk of overwriting existing track
  data) and renaming the 126 files.
- **Until fixed:** after importing an HDJ M3U, compare the track count with the HDJ Mix
  and add missing `#` tracks by hand.

## Claims from the task brief

| Claim | Result |
|---|---|
| Standalone app for macOS / Windows / Linux | Confirmed (it also ships as plug-ins) |
| Key with 6 modes, BPM, loudness | Confirmed; analysis is local |
| Route-based tracklist planning | Confirmed (scores the whole route, weakest transition first) |
| Separate in / out key evidence | Confirmed |
| Shareable tracklist page | Confirmed (public, email-verified) |
| Community: unlimited analysis, 5-track preview | Mostly: 5 tracks per saved Mix, Mixes unlimited |
| Pro ~$80 | Contradicted: $40 one-time now ($80 / $60 at launch, 3rd-party) |

## Consequences for this repo

- There is no nixpkgs package and no cask. On macOS, the options are a custom derivation
  that unpacks the dmg (the plug-ins are a complication), a self-written cask, or a
  manual install documented in the spec.
- The license must be activated once by hand on each machine.
- Rekordbox exchange is limited to M3U (paths only). Keys and BPM do not flow into
  rekordbox.
- There is no CLI. But the database is plain SQLite with readable key, BPM and in/out
  columns, so read-only MCP / SQLite access is possible. Its schema is undocumented and
  can change between versions.

## Backup handoff

> For the backup work (roadmap #10, draft PR #126: restic, `home/modules/backup.nix`).
> This section has all the facts. Status: copy tested on concinnity (v1.2.9); copy and
> restore with the app tested on serenity (v1.2.9, 27 tracks), no rescan.

**What to change in `custom.backup` (serenity):**
- `paths`: add `~/Library/APU Harmonic DJ` and
  `~/Library/Application Support/APU Harmonic DJ`.
- `inhibitApps`: add `"APU Harmonic DJ"`. This is `CFBundleExecutable` of the 1.2.9 app
  (15 characters, so `pgrep -x` matches it without truncation). Not yet observed as a
  running process name.
- Not covered by `inhibitApps`: the AUv3 running inside a DAW, which uses the same DB
  from a different process. Accept this, or add the DAW to `inhibitApps` too.
- restic stores absolute paths, so the two folders with the same name do not merge in a
  restic snapshot or restore. The "separate destinations" rule below applies to manual
  `cp` copies only.

**What to back up.** Two folders, which have the same name:

| Source | Content | Size (4 test tracks) |
|---|---|---|
| `~/Library/APU Harmonic DJ/` | `harmonic-dj.sqlite` (library DB: analysis, key profiles, ratings, groups, Gems), `mixes.json`, `mixes/*.hdjmix`, `mix-history/` | ~300 KB; the DB grows with the library |
| `~/Library/Application Support/APU Harmonic DJ/` | `APU Harmonic DJ.global.settings` (JUCE XML) | < 1 KB |

Do **not** back up these, because the system or the app creates them again:
- `~/Library/Preferences/com.APUSoftware.APUHarmonicDJ.plist` (only file-dialog state)
- `~/Library/Caches/com.juce.locks/…`
- `~/Library/Containers/com.APUSoftware.APUHarmonicDJ.APUHarmonicDJAUv3/`
  (sandbox container of the AUv3)
- `~/Library/Application Scripts/com.APUSoftware.APUHarmonicDJ.APUHarmonicDJAUv3/`
  (AUv3, system-managed)
- `/private/var/folders/…/com.APUSoftware.APUHarmonicDJ` (Metal shader cache)

**Rules:**
1. **Copy only while the app is closed.** Check with
   `pgrep -f 'APU Harmonic DJ.app/Contents/MacOS'`. The app may also run as an AUv3 in a
   DAW, which uses the same DB.
2. The DB uses `journal_mode=delete` (no WAL). A closed app leaves one consistent file.
   For a copy while the app runs, use `sqlite3 … ".backup"` instead of `cp`. That case
   is not tested.
3. **Use separate destinations, for example `hdj-data/` and `hdj-settings/`.** Both
   source folders are named `APU Harmonic DJ`, so `cp -R a b dest/` merges them into
   one folder. This happened in the test.
4. Check the copy with
   `sqlite3 "file:<copy>/harmonic-dj.sqlite?immutable=1" "pragma integrity_check"`. The
   result must be `ok`.

**Restore (tested on serenity 2026-10-17, see *Restore test*):**
1. Quit the app and check it is gone (`pgrep`, rule 1).
2. Copy `hdj-data/` back to `~/Library/APU Harmonic DJ/` and `hdj-settings/` back to
   `~/Library/Application Support/APU Harmonic DJ/`.
3. Start the app. The library must be complete, without a rescan.

**Limits:**
- The DB keys tracks by **absolute path** (`tracks.path`). A restore onto another
  machine or user, or after the music moved, needs the same paths. HDJ has a
  `track_path_aliases` table and a "moved file" handling, but we did not test them.
- The backup does not include the audio files. They are part of the music backup.
- The location of the license is not known (see *Findings §3*). After Pro activation,
  check whether a license file must be backed up too.
