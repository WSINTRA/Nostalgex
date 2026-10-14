// Default genre gate for "more like this" claims.
//
// TMDB recommendations / similar titles and whole-collection sweeps drift out
// of a channel's genre (Carry On on WESTERNS, every James Bond film on CRIME
// FLICKS, MYSTERY and SCI-FI). So every recommendation / similar / both claim
// and every collection member must also fit the channel's own
// `rules.genres.include` and `rules.genres.requireAll` from channels.json, with
// a keyword rescue for channels that ask for one (see channelRuleGate).
// Exemplars and hand-curated claims are never gated.
//
// channels.json genre names are Plex-flavoured; the title side is TMDB's genre
// list, which differs (TV uses "Sci-Fi & Fantasy", "Action & Adventure",
// "War & Politics"; TMDB has no "Holiday" or "Sport" genre at all). Each TMDB
// genre expands to the Plex names it covers, then matches the way the runtime
// filter does: substring, case-insensitive (nostalgex-channel-filter.cjs).

const TMDB_GENRE_ALIASES = {
  "action & adventure": ["action & adventure", "action", "adventure"],
  "sci-fi & fantasy": ["sci-fi & fantasy", "science fiction", "sci-fi", "fantasy"],
  "science fiction": ["science fiction", "sci-fi"],
  "war & politics": ["war & politics", "war", "politics"],
  kids: ["kids", "children"],
  reality: ["reality", "reality-tv"],
  talk: ["talk", "talk show"],
};

// Every genre name TMDB can emit (movie + TV lists), expanded.
const TMDB_GENRES = [
  "action", "adventure", "animation", "comedy", "crime", "documentary", "drama",
  "family", "fantasy", "history", "horror", "music", "mystery", "romance",
  "science fiction", "thriller", "tv movie", "war", "western",
  "action & adventure", "kids", "news", "reality", "sci-fi & fantasy", "soap",
  "talk", "war & politics",
];

export function expandTmdbGenres(genres) {
  const out = new Set();
  for (const g of genres || []) {
    const k = String(g).toLowerCase();
    for (const a of TMDB_GENRE_ALIASES[k] || [k]) out.add(a);
  }
  return [...out];
}

const ALL_TMDB_NAMES = expandTmdbGenres(TMDB_GENRES);

// Keep only the genre names TMDB can actually produce. An include TMDB never
// emits ("Holiday", "Christmas", "Sports") can't be checked, so a channel whose
// whole list is like that gets no default gate.
function gateable(list) {
  const lower = (list || []).map((g) => String(g).toLowerCase());
  return lower.filter((m) => ALL_TMDB_NAMES.some((a) => a.includes(m)));
}

// The channel's genres.include names TMDB can actually produce.
export function gateableIncludes(rules) {
  return gateable(rules?.genres?.include);
}

// null when the title passes (or the channel has nothing gateable), else a reason.
export function ruleGenreReason(tmdbGenres, includes) {
  if (!includes?.length) return null;
  const names = expandTmdbGenres(tmdbGenres);
  if (names.some((a) => includes.some((m) => a.includes(m)))) return null;
  return `genres ${(tmdbGenres || []).join("/") || "none"} miss channel rule ${includes.join("/")}`;
}

// The whole gate for one channel: channels.json `rules` plus the channel's
// entry in exemplars.json.
//   includes       rules.genres.include: the title needs at least one.
//   requireAll     rules.genres.requireAll: the title needs every one. SCI-FI
//                  lists Science Fiction, which keeps horror-only sequels
//                  (Hellraiser, Stake Land) off it even though Horror is in its
//                  include list. An exemplars.json entry can set
//                  `gateRequireAll: false` to leave its claims ungated by it;
//                  ROM COMS and GIRLS NIGHT do (owner's call, 2026-10-12).
//   rescueKeywords exemplars.json `genreRescueKeywords`: a title that misses
//                  the include list is still kept when its TMDB keywords carry
//                  one of these (exact, case-insensitive). MUSICALS uses it,
//                  because TMDB tags many real musicals Drama or Family, not
//                  Music. It never overrides requireAll.
export function channelRuleGate(rules, exemplarEntry = {}) {
  return {
    includes: gateableIncludes(rules),
    requireAll: exemplarEntry.gateRequireAll === false ? [] : gateable(rules?.genres?.requireAll),
    rescueKeywords: (exemplarEntry.genreRescueKeywords || []).map((k) => String(k).toLowerCase()),
  };
}

export function gateIsEmpty(gate) {
  return !gate.includes.length && !gate.requireAll.length;
}

// Decide one recommendation / similar / collection claim against the gate.
// `title` is { genres: TMDB genre names, keywords: TMDB keyword names }.
// Returns { reason, rescuedBy }: reason is null when the claim stands, and
// rescuedBy names the keyword that kept a title the include list would drop.
export function ruleGateDecision(title, gate) {
  const genres = title?.genres || [];
  const names = expandTmdbGenres(genres);
  const missing = gate.requireAll.filter((m) => !names.some((a) => a.includes(m)));
  if (missing.length) {
    return { reason: `genres ${genres.join("/") || "none"} lack required ${missing.join("+")}`, rescuedBy: null };
  }
  const why = ruleGenreReason(genres, gate.includes);
  if (!why) return { reason: null, rescuedBy: null };
  const keywords = (title?.keywords || []).map((k) => String(k).toLowerCase());
  const rescuedBy = gate.rescueKeywords.find((k) => keywords.includes(k)) || null;
  if (rescuedBy) return { reason: null, rescuedBy };
  return { reason: why, rescuedBy: null };
}

// Manifest sources the default gate applies to.
export const GATED_SOURCES = new Set(["recommendation", "similar", "both", "collection-via", "collection"]);
