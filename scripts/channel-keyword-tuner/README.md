# Channel Keyword Tuner

Derives the TMDB keyword vocabulary for a Nostalgex channel from a curated list
of exemplar shows/movies. The output is what you paste into `channels.json`.

## Why this exists

Channel rules tuned against one Plex library don't generalize — they break for
other users. Instead, we define each channel by 10–20 canonical exemplars
("these shows unambiguously belong on MAN CAVE") and let TMDB's tagged keywords
become the channel's semantic fingerprint.

## Usage

```bash
export TMDB_API_KEY=your_key_here

# Run all channels in exemplars.json
node scripts/channel-keyword-tuner/index.mjs

# Run a single channel
node scripts/channel-keyword-tuner/index.mjs --channel 56

# Check a regeneration without touching the shipped files, on a TMDB
# snapshot you can rerun against
node scripts/channel-keyword-tuner/index.mjs --cache /tmp/tmdb-cache.json --out /tmp/regen
```

Output: `channels-memberships.json` at the repo root (the manifest the app and
web tuner read) and `scripts/channel-keyword-tuner/report.md`. With `--out`,
both go to that folder instead. `--cache` keeps every TMDB response in one
JSON file (no API key in it) and reuses it, so two runs see the same data;
TMDB recommendations shift week to week, so without it two runs a month apart
never match.

## The genre gate

Every recommendation, similar and collection claim has to fit the channel's
genre rule before it lands in the manifest. Exemplars and `handCurated` titles
are never gated. The rule comes from `channels.json` plus optional fields on
the channel's entry in `exemplars.json` (`genre-gate.mjs`, tested by
`npm run test:tuner-gate`):

- `rules.genres.include` (channels.json): the title needs at least one.
- `rules.genres.requireAll` (channels.json): the title needs every one. SCI-FI
  uses it to keep horror-only titles off.
- `gateRequireAll: false` (exemplars.json): skip `requireAll` for that
  channel's claims. ROM COMS and GIRLS NIGHT set it.
- `genreRescueKeywords` (exemplars.json): keep a title that misses `include`
  when its TMDB keywords carry one of these. MUSICALS uses `musical`,
  `song and dance` and `broadway`. A rescue never overrides `requireAll`.

The app and the web filter never read these exemplars.json fields; they only
shape what the generator writes.

## Workflow

1. Add or edit a channel entry in `exemplars.json` with 10–20 canonical titles
2. Run the script
3. Open `report.md`, copy the suggested `keywords` + `keywordsRequireAnyGenre`
   block into `channels.json`
4. Tune the exemplar list and re-run if the result looks off

## Notes

- Uses the first TMDB search hit per title — check the "matched" name in the
  audit section if a result looks wrong, and add the year to the exemplar
  title to disambiguate (TMDB search supports `Title (Year)` patterns).
- TMDB free tier is 50 req/sec, well above what we need.
- Exemplar lists are inputs to this script, not shipped to the app.

## Claims that do not come from exemplars

A bare run of `index.mjs` rebuilds `channels-memberships.json` from the
exemplars and the `handCurated` blocks. Two sets of claims come from elsewhere
and have to be put back afterwards:

| Script | Channel | What it claims |
|---|---|---|
| `discover-standup.mjs` | STAND-UP (58), exclusive | every TMDB title with the `stand-up comedy` keyword |
| `discover-world-horror.mjs` | WORLD HORROR (418) | every TMDB horror film whose original language is not English, at 25 votes or more (`--min-votes` to change; about 2,000 films) |

Run them after the tuner, in either order. Both are idempotent.

`handCurated` blocks survive every run, bare or `--channel`, because they are
applied last. CRITERION (211) and MYSTERY BOX TV (419) are built entirely from
them. Their TMDB ids are what the app matches on, so check each new id against
TMDB (`tv/{id}` or `movie/{id}`: name and year) before adding it.
