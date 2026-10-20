#!/usr/bin/env node
// Claims every non-English horror film TMDB knows (above a vote floor) for
// WORLD HORROR (id 418) in channels-memberships.json.
//
// Why a list and not a rule: WORLD HORROR needs each film's original language,
// and neither app carries it. The Plex, Jellyfin and Emby listings do not have
// it, the shared enrichment cache (media_enrichments) has no language column,
// and OMDb is rate limited to 1,000 lookups a day for everyone. TMDB knows it,
// so the language test runs here, once, and the result ships as manifest claims
// that the Apple TV app, the web tuner and the Docker image already understand.
// The channel is `manifestOnly`, so nothing reaches it except these claims.
//
// Same shape as discover-standup.mjs. Rerun it after a full regeneration of the
// manifest by index.mjs, which rebuilds the file from exemplars and would drop
// these claims. It is idempotent: it first removes every 418 claim, then adds
// the current list.
//
// Usage:
//   node scripts/channel-keyword-tuner/discover-world-horror.mjs            (writes)
//   node scripts/channel-keyword-tuner/discover-world-horror.mjs --dry-run  (counts only)
//   node scripts/channel-keyword-tuner/discover-world-horror.mjs --min-votes 50
//
// Needs TMDB_API_KEY (read from the repo .env when present).

import fs from "node:fs/promises";
import fsSync from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const MANIFEST_PATH = path.join(__dirname, "..", "..", "channels-memberships.json");

(function loadDotEnv() {
  const envPath = path.join(__dirname, "..", "..", ".env");
  if (!fsSync.existsSync(envPath)) return;
  for (const line of fsSync.readFileSync(envPath, "utf8").split("\n")) {
    const m = line.match(/^\s*([A-Z_][A-Z0-9_]*)\s*=\s*(.*)\s*$/);
    if (m && !process.env[m[1]]) process.env[m[1]] = m[2].replace(/^['"]|['"]$/g, "");
  }
})();

const TMDB = "https://api.themoviedb.org/3";
const KEY = process.env.TMDB_API_KEY;
const CHANNEL_ID = 418;
const HORROR = 27;
// Animation and Family: the channel excludes them too, and the animation genre
// lock would block most of them anyway.
const WITHOUT_GENRES = "16,10751";
const SOURCE = "tmdb-discover:world horror";

const args = process.argv.slice(2);
const DRY_RUN = args.includes("--dry-run");
const MIN_VOTES = args.includes("--min-votes") ? Number(args[args.indexOf("--min-votes") + 1]) : 25;

if (!KEY) {
  console.error("Missing TMDB_API_KEY");
  process.exit(1);
}
if (!Number.isFinite(MIN_VOTES) || MIN_VOTES < 0) {
  console.error("--min-votes needs a number");
  process.exit(1);
}

const isBearer = KEY.startsWith("eyJ");

async function tmdb(pathPart, params = {}) {
  const url = new URL(TMDB + pathPart);
  if (!isBearer) url.searchParams.set("api_key", KEY);
  for (const [k, v] of Object.entries(params)) url.searchParams.set(k, String(v));
  const headers = isBearer ? { Authorization: `Bearer ${KEY}` } : {};
  for (let attempt = 0; attempt < 3; attempt++) {
    const r = await fetch(url, { headers });
    if (r.ok) return r.json();
    if (r.status !== 429 && r.status < 500) throw new Error(`TMDB ${r.status} ${pathPart}`);
    await new Promise((res) => setTimeout(res, 1000 * (attempt + 1)));
  }
  throw new Error(`TMDB kept failing on ${pathPart}`);
}

/**
 * Every horror film at or above the vote floor, any language. TMDB stops at page 500.
 * Paging is not stable when many films share a sort value (vote counts tie a lot near
 * the floor), so the sweep runs in two sort orders and the caller takes the union.
 */
async function discoverHorror(sortBy) {
  const out = [];
  let page = 1;
  let totalPages = 1;
  do {
    const data = await tmdb("/discover/movie", {
      with_genres: HORROR,
      without_genres: WITHOUT_GENRES,
      "vote_count.gte": MIN_VOTES,
      include_adult: false,
      sort_by: sortBy,
      page,
    });
    totalPages = Math.min(data.total_pages || 1, 500);
    for (const r of data.results || []) {
      out.push({
        id: r.id,
        name: r.title,
        year: (r.release_date || "").slice(0, 4),
        language: r.original_language || "",
      });
    }
    if (page % 100 === 0 || page === totalPages) console.error(`  ${sortBy}: page ${page}/${totalPages}`);
    page++;
  } while (page <= totalPages);
  if (totalPages === 500) console.error("  warning: TMDB's 500 page cap was reached; raise --min-votes");
  return out;
}

async function main() {
  console.error(`Discovering horror on TMDB (vote count >= ${MIN_VOTES})...`);
  const all = [
    ...(await discoverHorror("vote_count.desc")),
    ...(await discoverHorror("primary_release_date.desc")),
  ];
  const seen = new Set();
  const films = all
    .filter((f) => f.language && f.language !== "en")
    .filter((f) => (seen.has(f.id) ? false : (seen.add(f.id), true)))
    .sort((a, b) => a.id - b.id);

  const byLang = {};
  for (const f of films) byLang[f.language] = (byLang[f.language] || 0) + 1;
  console.error(`\n${new Set(all.map((f) => f.id)).size} horror films, ${films.length} not in English.`);
  console.error(
    "  by language: " +
      Object.entries(byLang)
        .sort((a, b) => b[1] - a[1])
        .map(([l, n]) => `${l} ${n}`)
        .join(", "),
  );
  if (DRY_RUN) return;

  const m = JSON.parse(await fs.readFile(MANIFEST_PATH, "utf8"));
  m.items = m.items || {};

  // Start clean: drop every earlier WORLD HORROR claim, and the entries that only
  // existed for it.
  let removed = 0;
  for (const [key, entry] of Object.entries(m.items)) {
    if (!entry.channels?.includes(CHANNEL_ID)) continue;
    entry.channels = entry.channels.filter((c) => c !== CHANNEL_ID);
    removed++;
    if (entry.channels.length === 0 && entry.source === SOURCE) delete m.items[key];
  }

  let added = 0;
  let joined = 0;
  for (const f of films) {
    const key = `movie:${f.id}`;
    const entry = m.items[key];
    if (entry) {
      entry.channels.push(CHANNEL_ID);
      joined++;
    } else {
      m.items[key] = { channels: [CHANNEL_ID], source: SOURCE, name: f.name, mediaType: "movie" };
      added++;
    }
  }

  m.generated = new Date().toISOString();
  await fs.writeFile(MANIFEST_PATH, JSON.stringify(m, null, 2));
  console.error(`\nManifest updated: ${removed} earlier claims cleared, ${added} new entries, ` +
    `${joined} existing entries joined, ${films.length} claimed for WORLD HORROR.`);
}

main().catch((err) => {
  console.error("Fatal:", err.message || err);
  process.exit(1);
});
