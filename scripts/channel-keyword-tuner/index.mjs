#!/usr/bin/env node
// Channel keyword tuner — derives TMDB keyword vocabulary for Nostalgex channels
// from a curated list of exemplar shows/movies. Outputs a markdown report.
//
// Usage:
//   TMDB_API_KEY=xxx node scripts/channel-keyword-tuner/index.mjs
//   TMDB_API_KEY=xxx node scripts/channel-keyword-tuner/index.mjs --channel 56
//   ... --cache /tmp/tmdb-cache.json   keep every TMDB response on disk and
//                                      reuse it, so a rerun sees the same data
//   ... --out /tmp/regen               write the manifest and report there
//                                      instead of over the shipped files
//
// Input:  scripts/channel-keyword-tuner/exemplars.json, channels.json
// Output: channels-memberships.json, scripts/channel-keyword-tuner/report.md

import fs from "node:fs/promises";
import fsSync from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import { channelRuleGate, gateIsEmpty, ruleGateDecision } from "./genre-gate.mjs";

const require = createRequire(import.meta.url);
const { titleContainsWord } = require("../nostalgex-channel-filter.cjs");

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const TMDB = "https://api.themoviedb.org/3";

// Auto-load plex-90/.env so the script just works without `source .env` first.
(function loadDotEnv() {
  const envPath = path.join(__dirname, "..", "..", ".env");
  if (!fsSync.existsSync(envPath)) return;
  for (const line of fsSync.readFileSync(envPath, "utf8").split("\n")) {
    const m = line.match(/^\s*([A-Z_][A-Z0-9_]*)\s*=\s*(.*)\s*$/);
    if (m && !process.env[m[1]]) process.env[m[1]] = m[2].replace(/^['"]|['"]$/g, "");
  }
})();

const KEY = process.env.TMDB_API_KEY;

if (!KEY) {
  console.error("Missing TMDB_API_KEY env var");
  process.exit(1);
}

const args = process.argv.slice(2);
// --channel accepts a single id or comma-separated list, e.g. --channel 56,81
const channelFilter = args.includes("--channel")
  ? args[args.indexOf("--channel") + 1].split(",").map(s => Number(s.trim())).filter(n => !isNaN(n))
  : null;
const argPath = (flag) => (args.includes(flag) ? path.resolve(args[args.indexOf(flag) + 1]) : null);
const cachePath = argPath("--cache");
const outDir = argPath("--out");

// TMDB supports two auth styles:
//   v3 API key — short string, passed as ?api_key=xxx
//   v4 Read Access Token — long JWT starting with "eyJ", passed as Bearer header
const isBearerToken = KEY.startsWith("eyJ");

// Optional disk cache (--cache). Keyed by path and query without the key, so
// the file holds no credentials. TMDB recommendations shift week to week; a
// cached run is the only way to compare two generator versions on one dataset.
const diskCache = cachePath && fsSync.existsSync(cachePath)
  ? JSON.parse(fsSync.readFileSync(cachePath, "utf8"))
  : {};

async function tmdb(pathPart, params = {}) {
  const query = new URLSearchParams(params).toString();
  const cacheKey = query ? `${pathPart}?${query}` : pathPart;
  if (cachePath && cacheKey in diskCache) {
    const hit = diskCache[cacheKey];
    if (hit?.__status) throw new Error(`TMDB ${hit.__status} ${pathPart}`);
    return hit;
  }
  const url = new URL(TMDB + pathPart);
  if (!isBearerToken) url.searchParams.set("api_key", KEY);
  for (const [k, v] of Object.entries(params)) url.searchParams.set(k, v);
  const headers = isBearerToken ? { Authorization: `Bearer ${KEY}` } : {};
  const r = await fetch(url, { headers });
  if (!r.ok) {
    if (cachePath && r.status === 404) diskCache[cacheKey] = { __status: 404 };
    throw new Error(`TMDB ${r.status} ${pathPart}`);
  }
  const json = await r.json();
  if (cachePath) diskCache[cacheKey] = json;
  return json;
}

async function findExemplar(title, mediaType) {
  const endpoint = mediaType === "tv" ? "/search/tv" : "/search/movie";
  const data = await tmdb(endpoint, { query: title });
  const hit = (data.results || [])[0];
  if (!hit) return null;
  return { id: hit.id, name: hit.name || hit.title, year: (hit.first_air_date || hit.release_date || "").slice(0, 4) };
}

async function fetchKeywords(id, mediaType) {
  const endpoint = mediaType === "tv" ? `/tv/${id}/keywords` : `/movie/${id}/keywords`;
  const data = await tmdb(endpoint);
  const list = mediaType === "tv" ? data.results : data.keywords;
  return (list || []).map(k => k.name);
}

async function fetchGenres(id, mediaType) {
  const endpoint = mediaType === "tv" ? `/tv/${id}` : `/movie/${id}`;
  const data = await tmdb(endpoint);
  return (data.genres || []).map(g => g.name);
}

async function fetchRelated(id, mediaType) {
  // Returns array of { id, name, source: "recommendation"|"similar" }
  const base = mediaType === "tv" ? `/tv/${id}` : `/movie/${id}`;
  const [recs, sims] = await Promise.all([
    tmdb(`${base}/recommendations`).catch(() => ({ results: [] })),
    tmdb(`${base}/similar`).catch(() => ({ results: [] })),
  ]);
  const out = [];
  for (const r of recs.results || []) {
    out.push({
      id: r.id,
      name: r.name || r.title,
      source: "recommendation",
      year: (r.first_air_date || r.release_date || "").slice(0, 4),
    });
  }
  for (const s of sims.results || []) {
    out.push({
      id: s.id,
      name: s.name || s.title,
      source: "similar",
      year: (s.first_air_date || s.release_date || "").slice(0, 4),
    });
  }
  return out;
}

// Movies only — TV has no equivalent collection concept on TMDB.
// Returns the collection ID and name if the movie belongs to one, else null.
async function fetchMovieCollection(id) {
  const data = await tmdb(`/movie/${id}`).catch(() => null);
  if (!data?.belongs_to_collection) return null;
  return { id: data.belongs_to_collection.id, name: data.belongs_to_collection.name };
}

// Returns the full set of movies in a TMDB collection.
async function fetchCollectionMembers(collectionID) {
  const data = await tmdb(`/collection/${collectionID}`).catch(() => null);
  if (!data) return { name: `Collection ${collectionID}`, members: [] };
  return {
    name: data.name || `Collection ${collectionID}`,
    members: (data.parts || []).map(p => ({ id: p.id, name: p.title || p.original_title })),
  };
}

// In-memory cache for collection lookups — script runs once, cache lives for that run.
const movieCollectionCache = new Map(); // movieID → { id, name } | null
const collectionMembersCache = new Map(); // collectionID → { name, members }

async function getMovieCollectionCached(movieID) {
  if (movieCollectionCache.has(movieID)) return movieCollectionCache.get(movieID);
  const c = await fetchMovieCollection(movieID);
  movieCollectionCache.set(movieID, c);
  return c;
}

async function getCollectionMembersCached(collectionID) {
  if (collectionMembersCache.has(collectionID)) return collectionMembersCache.get(collectionID);
  const c = await fetchCollectionMembers(collectionID);
  collectionMembersCache.set(collectionID, c);
  return c;
}

// Fetch genres + provenance (original language, origin/production countries) +
// TMDB keywords in one shot. Used by the candidate gate and the global-lock
// check so a channel can require a genre (Animation) and an origin (Japanese),
// and so the build can route items with marker keywords (e.g. "stand-up comedy")
// to a single channel.
async function fetchDetails(id, mediaType) {
  const detail = mediaType === "tv" ? `/tv/${id}` : `/movie/${id}`;
  const kwPath = mediaType === "tv" ? `/tv/${id}/keywords` : `/movie/${id}/keywords`;
  const [data, kw] = await Promise.all([
    tmdb(detail).catch(() => ({})),
    tmdb(kwPath).catch(() => ({})),
  ]);
  const kwList = mediaType === "tv" ? kw.results : kw.keywords;
  return {
    genres: (data.genres || []).map((g) => g.name),
    keywords: (kwList || []).map((k) => (k.name || "").toLowerCase()),
    originalLanguage: data.original_language || "",
    originCountries: data.origin_country || [],
    productionCountries: (data.production_countries || []).map((c) => c.iso_3166_1),
    productionCompanies: (data.production_companies || []).map((c) => (c.name || "").toLowerCase()),
  };
}

// Per-channel candidate gate. Every non-exemplar claim (TMDB recs/similar,
// explicit collection members, auto-swept siblings) must pass it.
//   requireGenres              — at least one TMDB genre in the list
//   requireOriginalLanguage    — original_language in the list
//   requireProductionCompanies — at least one TMDB production company whose
//                                name contains one of these strings
// Returns null when the item passes, or a short reason when it is dropped.
function gateReason(det, wantGenres, wantLangs, wantCompanies) {
  const genreOK = !wantGenres.length || det.genres.some((g) => wantGenres.includes(g.toLowerCase()));
  const langOK = !wantLangs.length || wantLangs.includes((det.originalLanguage || "").toLowerCase());
  const companies = det.productionCompanies || [];
  const companyOK = !wantCompanies.length || companies.some((pc) => wantCompanies.some((w) => pc.includes(w)));
  if (genreOK && langOK && companyOK) return null;
  return [
    !genreOK && `genres ${det.genres.join("/") || "none"}`,
    !langOK && `lang ${det.originalLanguage || "?"}`,
    !companyOK && `companies ${companies.join("/") || "none"}`,
  ].filter(Boolean).join(", ");
}

// Global locks declare "any item with signal X can only appear on channel Y."
// Configured in exemplars.json's top-level globalLocks block. Returns the
// channelID this item is locked to, or null if no lock applies.
function findGlobalLock(details, globalLocks) {
  if (!Array.isArray(globalLocks) || !globalLocks.length) return null;
  const keywords = details.keywords || [];
  const genres = (details.genres || []).map((g) => g.toLowerCase());
  for (const lock of globalLocks) {
    const m = lock.match || {};
    if (m.keyword && keywords.includes(m.keyword.toLowerCase())) return lock.channelID;
    if (m.genre && genres.some((g) => g === m.genre.toLowerCase())) return lock.channelID;
  }
  return null;
}

const detailCache = new Map(); // `${mediaType}:${id}` → details
async function getDetailsCached(id, mediaType) {
  const key = `${mediaType}:${id}`;
  if (detailCache.has(key)) return detailCache.get(key);
  const d = await fetchDetails(id, mediaType);
  detailCache.set(key, d);
  return d;
}

async function processChannel(ch, globalLocks = [], rules = {}) {
  const exemplarsList = ch.exemplars || [];
  const collectionsList = ch.tmdbCollections || [];
  console.error(`\n=== CH ${ch.id} ${ch.name} (${ch.mediaType}) — ${exemplarsList.length} exemplars, ${collectionsList.length} TMDB collections ===`);

  const perTitle = [];
  const keywordCounts = new Map();
  const genreCounts = new Map();
  const missing = [];

  // related[tmdbID] = { name, sources: Set<exemplarTitle>, kind: "recommendation"|"similar"|"both" }
  const related = new Map();
  const exemplarIDs = new Set();
  // Pattern A — explicit TMDB collections, claimed wholesale.
  // [{ collectionID, collectionName, members: [{id, name}] }]
  const explicitCollections = [];
  // Pattern B — auto-swept sibling claims from any movie's belongs_to_collection.
  // collectionSiblings[id] = { name, collectionID, collectionName, viaTitle }
  const collectionSiblings = new Map();

  for (const title of exemplarsList) {
    const found = await findExemplar(title, ch.mediaType);
    if (!found) {
      console.error(`  ✗ ${title} — not found on TMDB`);
      missing.push(title);
      continue;
    }
    exemplarIDs.add(found.id);
    const [keywords, genres, relatedList] = await Promise.all([
      fetchKeywords(found.id, ch.mediaType),
      fetchGenres(found.id, ch.mediaType),
      fetchRelated(found.id, ch.mediaType),
    ]);
    console.error(`  ✓ ${title} (${found.year}) — ${keywords.length} kw, ${genres.length} genres, ${relatedList.length} related`);
    perTitle.push({ title, matched: found.name, year: found.year, tmdbID: found.id, keywords, genres });
    for (const k of keywords) keywordCounts.set(k, (keywordCounts.get(k) || 0) + 1);
    for (const g of genres) genreCounts.set(g, (genreCounts.get(g) || 0) + 1);
    for (const r of relatedList) {
      if (exemplarIDs.has(r.id)) continue; // skip — already an exemplar
      const existing = related.get(r.id);
      if (existing) {
        existing.sources.add(title);
        if (existing.kind !== r.source) existing.kind = "both";
        if (!existing.year && r.year) existing.year = r.year;
      } else {
        related.set(r.id, { name: r.name, sources: new Set([title]), kind: r.source, year: r.year });
      }
    }
  }

  // --- Pattern A: explicit TMDB collections ----------------------------
  // Movies only — TMDB doesn't have a TV equivalent.
  if (ch.mediaType === "movie") {
    for (const cid of collectionsList) {
      const col = await getCollectionMembersCached(cid);
      console.error(`  📦 Collection ${cid} "${col.name}" — ${col.members.length} members`);
      if (!col.members.length) console.error(`  ⚠️  collection ${cid} returned no members — dead or wrong id in tmdbCollections`);
      explicitCollections.push({ collectionID: cid, collectionName: col.name, members: col.members });
    }
  }

  // --- Pattern B: auto-sweep sibling films from any claimed movie's collection
  // Skip TV (no concept) and skip if explicitly disabled per channel.
  const autoSweepEnabled = ch.mediaType === "movie" && ch.autoSweepCollections !== false;
  if (autoSweepEnabled) {
    const claimedMovieIDs = new Set([
      ...perTitle.map(p => p.tmdbID),
      ...[...related.entries()]
        .filter(([_, r]) => r.sources.size >= (Number(process.env.MIN_RELATED || 2)))
        .map(([id]) => id),
    ]);
    const seenCollectionIDs = new Set(explicitCollections.map(c => c.collectionID));
    for (const movieID of claimedMovieIDs) {
      const collection = await getMovieCollectionCached(movieID);
      if (!collection) continue;
      if (seenCollectionIDs.has(collection.id)) continue;
      seenCollectionIDs.add(collection.id);
      const col = await getCollectionMembersCached(collection.id);
      const viaTitle = perTitle.find(p => p.tmdbID === movieID)?.title
        || related.get(movieID)?.name
        || `TMDB ${movieID}`;
      console.error(`  🔗 Sweeping collection "${col.name}" via ${viaTitle} — ${col.members.length} members`);
      for (const m of col.members) {
        if (exemplarIDs.has(m.id) || related.has(m.id) || collectionSiblings.has(m.id)) continue;
        collectionSiblings.set(m.id, {
          name: m.name,
          collectionID: collection.id,
          collectionName: col.name,
          viaTitle,
        });
      }
    }
  }

  const total = perTitle.length;
  const ranked = [...keywordCounts.entries()]
    .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
    .map(([kw, n]) => ({ kw, n, pct: Math.round((n / total) * 100) }));

  const rankedGenres = [...genreCounts.entries()]
    .sort((a, b) => b[1] - a[1])
    .map(([g, n]) => ({ g, n, pct: Math.round((n / total) * 100) }));

  // Rank related shows by how many exemplars they appear next to
  let rankedRelated = [...related.entries()]
    .map(([id, r]) => ({
      id,
      name: r.name,
      year: r.year,
      count: r.sources.size,
      kind: r.kind,
      sources: [...r.sources],
    }))
    .sort((a, b) => b.count - a.count || a.name.localeCompare(b.name));

  // Candidate gate: TMDB recommendations/similar are noisy and can drag in
  // titles from the wrong medium (live-action Spy Kids), wrong origin (Western
  // animation like An American Tail onto an anime channel), or wrong category
  // entirely (Jurassic World into DOCS via viewer-overlap recs). Apply two
  // filters before letting a candidate be claimed:
  //   1. Per-channel requires — requireGenres / requireOriginalLanguage
  //   1b. Default genre gate: the channel's own rules.genres.include and
  //       requireAll from channels.json, plus any genreRescueKeywords from
  //       exemplars.json (genre-gate.mjs). Applies to every channel that has
  //       one, so Bond stops landing on CRIME FLICKS / MYSTERY via recs.
  //   2. Global locks — items with a marker signal (e.g. "stand-up comedy"
  //      keyword) can only ever appear on the channel they're locked to
  // Only candidates at/above the claim threshold are checked (one cached TMDB
  // call each); lower-confidence rows pass through unchanged.
  const wantGenres = (ch.requireGenres || []).map((g) => g.toLowerCase());
  const wantLangs = (ch.requireOriginalLanguage || []).map((l) => l.toLowerCase());
  const wantCompanies = (ch.requireProductionCompanies || []).map((c) => c.toLowerCase());
  const ruleGate = channelRuleGate(rules, ch);
  const hasGate = wantGenres.length || wantLangs.length || wantCompanies.length || !gateIsEmpty(ruleGate);
  function ruleReason(det, name) {
    const d = ruleGateDecision(det, ruleGate);
    if (d.rescuedBy) console.error(`  + kept "${name}" off-genre, keyword "${d.rescuedBy}"`);
    return d.reason;
  }
  const minRelated = Number(process.env.MIN_RELATED || 2);
  if (hasGate || globalLocks.length) {
    const gated = [];
    for (const rel of rankedRelated) {
      if (rel.count < minRelated) { gated.push(rel); continue; }
      const det = await getDetailsCached(rel.id, ch.mediaType);
      const lockedTo = findGlobalLock(det, globalLocks);
      if (lockedTo != null && lockedTo !== ch.id) {
        console.error(`  🔒 lock dropped "${rel.name}" — globally locked to CH ${lockedTo}`);
        continue;
      }
      const why = gateReason(det, wantGenres, wantLangs, wantCompanies)
      || ruleReason(det, rel.name);
      if (!why) {
        if (lockedTo != null) rel._exclusiveTo = lockedTo;
        gated.push(rel);
      } else {
        console.error(`  ⊘ gate dropped "${rel.name}" — ${why}`);
      }
    }
    rankedRelated = gated;
  }

  // Gate Pattern A (explicit collections) and Pattern B (collection siblings).
  // Without this, claiming a single film with belongs_to_collection sweeps the
  // entire series in — which is how the full Jurassic Park Collection ended up
  // in DOCS via Fallen Kingdom, and similar leakage in ANIME. Explicit
  // collections are gated too: a wrong id in tmdbCollections (MARVEL listed
  // 295, the Pirates of the Caribbean Collection) otherwise claims a whole
  // unrelated franchise with nothing to stop it.
  async function gateCollectionMember(member, label) {
    if (!hasGate && !globalLocks.length) return { ok: true };
    const det = await getDetailsCached(member.id, ch.mediaType);
    const lockedTo = findGlobalLock(det, globalLocks);
    if (lockedTo != null && lockedTo !== ch.id) {
      console.error(`  🔒 ${label} lock dropped "${member.name}" — locked to CH ${lockedTo}`);
      return { ok: false };
    }
    const why = gateReason(det, wantGenres, wantLangs, wantCompanies)
        || ruleReason(det, member.name);
    if (why) {
      console.error(`  ⊘ ${label} dropped "${member.name}" — ${why}`);
      return { ok: false };
    }
    return { ok: true, exclusiveTo: lockedTo };
  }

  for (const col of explicitCollections) {
    const filtered = [];
    for (const m of col.members) {
      const g = await gateCollectionMember(m, `collection "${col.collectionName}"`);
      if (g.ok) { if (g.exclusiveTo != null) m._exclusiveTo = g.exclusiveTo; filtered.push(m); }
    }
    col.members = filtered;
  }
  const siblingsFiltered = new Map();
  for (const [id, sib] of collectionSiblings.entries()) {
    const g = await gateCollectionMember({ id, name: sib.name }, `sibling via "${sib.viaTitle}"`);
    if (g.ok) {
      if (g.exclusiveTo != null) sib._exclusiveTo = g.exclusiveTo;
      siblingsFiltered.set(id, sib);
    }
  }

  // Mark exemplars themselves so the manifest entry carries the exclusive flag
  // (otherwise a stand-up exemplar of STAND-UP wouldn't be marked exclusive).
  if (globalLocks.length) {
    for (const t of perTitle) {
      const det = detailCache.get(`${ch.mediaType}:${t.tmdbID}`);
      // Exemplars don't get fetchDetails called; reuse keywords/genres we already have.
      const proxy = { keywords: (t.keywords || []).map((k) => k.toLowerCase()), genres: t.genres || [] };
      const lockedTo = findGlobalLock(det || proxy, globalLocks);
      if (lockedTo != null && lockedTo === ch.id) t._exclusiveTo = lockedTo;
      else if (lockedTo != null && lockedTo !== ch.id) {
        // An exemplar that's globally locked away — author probably misplaced it.
        console.error(`  ⚠️  exemplar "${t.title}" is locked to CH ${lockedTo}, not this channel (${ch.id})`);
      }
    }
  }

  return { channel: ch, perTitle, ranked, rankedGenres, rankedRelated, explicitCollections, collectionSiblings: [...siblingsFiltered.entries()].map(([id, v]) => ({ id, ...v })), missing, total };
}

function renderReport(results, minRelatedCount) {
  const lines = [];
  lines.push(`# Channel Keyword Tuner Report`);
  lines.push(`Generated: ${new Date().toISOString()}`);
  lines.push("");

  for (const r of results) {
    const { channel: ch, perTitle, ranked, rankedGenres, rankedRelated, explicitCollections = [], collectionSiblings = [], missing, total } = r;
    lines.push(`## CH ${ch.id} ${ch.name}`);
    lines.push(`Matched ${total}/${(ch.exemplars || []).length} exemplars on TMDB`);
    if (missing.length) lines.push(`**Not found:** ${missing.join(", ")}`);
    lines.push("");

    if (explicitCollections.length || collectionSiblings.length) {
      lines.push(`### TMDB collections`);
      for (const col of explicitCollections) {
        lines.push(`- 📦 **${col.collectionName}** (explicit, collection ${col.collectionID}) — ${col.members.length} members`);
      }
      const byCol = new Map();
      for (const sib of collectionSiblings) {
        if (!byCol.has(sib.collectionID)) byCol.set(sib.collectionID, { name: sib.collectionName, via: sib.viaTitle, count: 0 });
        byCol.get(sib.collectionID).count++;
      }
      for (const [id, c] of byCol) {
        lines.push(`- 🔗 **${c.name}** (auto-swept via "${c.via}", collection ${id}) — ${c.count} sibling members`);
      }
      lines.push("");
    }

    lines.push(`### Related shows from TMDB graph (≥${minRelatedCount} exemplars)`);
    lines.push(`These are claimed for this channel in the manifest.`);
    lines.push(`| Title | Exemplars | Source |`);
    lines.push(`|---|---|---|`);
    for (const rel of rankedRelated.filter(r => r.count >= minRelatedCount)) {
      lines.push(`| ${rel.name} | ${rel.count} | ${rel.kind} |`);
    }
    lines.push("");

    lines.push(`<details><summary>All related shows (lower confidence — for review)</summary>\n`);
    lines.push(`| Title | Exemplars | Source | Found via |`);
    lines.push(`|---|---|---|---|`);
    for (const rel of rankedRelated.filter(r => r.count < minRelatedCount && r.count >= 2)) {
      lines.push(`| ${rel.name} | ${rel.count} | ${rel.kind} | ${rel.sources.join(", ")} |`);
    }
    lines.push(`\n</details>`);
    lines.push("");

    lines.push(`### Recurring TMDB keywords (≥2 exemplars)`);
    lines.push(`| Keyword | Count | % |`);
    lines.push(`|---|---|---|`);
    for (const { kw, n, pct } of ranked.filter(r => r.n >= 2)) {
      lines.push(`| ${kw} | ${n} | ${pct}% |`);
    }
    lines.push("");

    lines.push(`### TMDB genres on exemplars`);
    lines.push(`| Genre | Count | % |`);
    lines.push(`|---|---|---|`);
    for (const { g, n, pct } of rankedGenres) {
      lines.push(`| ${g} | ${n} | ${pct}% |`);
    }
    lines.push("");

    lines.push(`### Suggested channels.json snippet`);
    const top = ranked.filter(r => r.n >= Math.max(2, Math.floor(total * 0.2))).slice(0, 25).map(r => r.kw);
    const topGenres = rankedGenres.filter(r => r.n >= Math.floor(total * 0.5)).map(r => r.g);
    lines.push("```json");
    lines.push(JSON.stringify({
      keywords: top,
      keywordsRequireAnyGenre: topGenres,
    }, null, 2));
    lines.push("```");
    lines.push("");

    lines.push(`<details><summary>Per-exemplar keywords (audit)</summary>\n`);
    for (const t of perTitle) {
      lines.push(`- **${t.title}** → matched "${t.matched}" (${t.year}, TMDB ${t.tmdbID})`);
      lines.push(`  - keywords: ${t.keywords.join(", ") || "(none)"}`);
      lines.push(`  - genres: ${t.genres.join(", ") || "(none)"}`);
    }
    lines.push(`\n</details>`);
    lines.push("");
  }

  return lines.join("\n");
}

function yearInRange(yearStr, rules) {
  if (!rules?.yearRange) return true;
  const y = Number.parseInt(String(yearStr), 10);
  if (!Number.isFinite(y)) return false;
  if (rules.yearRange.min != null && y < rules.yearRange.min) return false;
  if (rules.yearRange.max != null && y > rules.yearRange.max) return false;
  return true;
}

function buildManifest(results, minRelatedCount, channelRulesById, handCurated = []) {
  // Manifest key format: "<mediaType>:<tmdbID>" → { channels, source, name, mediaType }
  // mediaType + name are denormalized for the dev UI (the app ignores them).
  const items = {};

  function claim(mediaType, id, name, channelID, source, year, exclusiveTo) {
    const rules = channelRulesById[channelID];
    if (!yearInRange(year, rules)) return;
    const titleLower = String(name || "").toLowerCase().replace(/ \(\d{4}\)$/, "");
    const curated = rules?.titleContains;
    if (Array.isArray(curated) && curated.length > 0) {
      const matches = curated.some((t) => titleContainsWord(titleLower, t));
      if (!matches) return;
    }
    const key = `${mediaType}:${id}`;
    if (!items[key]) items[key] = { channels: [], source, name, mediaType };
    if (!items[key].channels.includes(channelID)) items[key].channels.push(channelID);
    // Honor exclusive lock if a global lock matched. Once set, the runtime
    // filter blocks this item from every other channel (manifest-claimed or not).
    if (exclusiveTo != null) items[key].exclusive = exclusiveTo;
  }

  for (const r of results) {
    const { channel: ch, perTitle, rankedRelated, explicitCollections = [], collectionSiblings = [] } = r;
    for (const t of perTitle) {
      claim(ch.mediaType, t.tmdbID, t.matched || t.title, ch.id, `exemplar:${t.title}`, t.year, t._exclusiveTo);
    }
    for (const rel of rankedRelated.filter(r => r.count >= minRelatedCount)) {
      claim(ch.mediaType, rel.id, rel.name, ch.id, `${rel.kind}:${rel.count} exemplars`, rel.year, rel._exclusiveTo);
    }
    // Pattern A — every member of an explicit TMDB collection
    for (const col of explicitCollections) {
      for (const m of col.members) {
        claim(ch.mediaType, m.id, m.name, ch.id, `collection:${col.collectionName}`, null, m._exclusiveTo);
      }
    }
    // Pattern B — sibling films swept in via an already-claimed film's collection
    for (const sib of collectionSiblings) {
      claim(ch.mediaType, sib.id, sib.name, ch.id, `collection-via:${sib.viaTitle} (${sib.collectionName})`, null, sib._exclusiveTo);
    }
  }

  // Hand-curated claims are applied last and deliberately bypass `claim()`:
  // they are an explicit editorial decision, so channel rules (year range,
  // titleContains) must not veto them. Applying them on EVERY run — bare or
  // --channel filtered — is what keeps them from being silently wiped, which
  // is how CRITERION ended up with no generator input at all.
  //
  // The tmdbID is authoritative. The runtime matches on `<mediaType>:<tmdbID>`
  // and ignores `name`, so a wrong id serves the wrong film with a plausible
  // label: before 2026-09-05, 38 of CRITERION's 53 ids were wrong and the
  // channel was quietly serving 2 Fast 2 Furious, Super Mario Bros. and Bambi.
  for (const block of handCurated) {
    const mediaType = block.mediaType || "movie";
    for (const t of block.titles || []) {
      if (!t.tmdbID) continue;
      const key = `${mediaType}:${t.tmdbID}`;
      if (!items[key]) {
        items[key] = { channels: [], source: `hand-curated:${block.label}`, name: t.title, mediaType };
      }
      if (!items[key].channels.includes(block.channelID)) {
        items[key].channels.push(block.channelID);
      }
    }
  }

  return {
    version: 1,
    generated: new Date().toISOString(),
    minRelatedCount,
    items,
  };
}

async function main() {
  const exemplarsPath = path.join(__dirname, "exemplars.json");
  const channelsJsonPath = path.join(__dirname, "..", "..", "channels.json");
  const raw = JSON.parse(await fs.readFile(exemplarsPath, "utf8"));
  const channelsJson = JSON.parse(await fs.readFile(channelsJsonPath, "utf8"));
  const channelRulesById = Object.fromEntries(
    (channelsJson.channels || []).map((c) => [c.id, c.rules || {}]),
  );
  const channels = channelFilter
    ? raw.channels.filter(c => channelFilter.includes(c.id))
    : raw.channels;

  if (!channels.length) {
    console.error(`No channels to process${channelFilter ? ` (filter: ${channelFilter})` : ""}`);
    process.exit(1);
  }

  const minRelatedCount = Number(process.env.MIN_RELATED || 2);
  const globalLocks = raw.globalLocks || [];
  if (globalLocks.length) {
    console.error(`Global locks active: ${globalLocks.length}`);
    for (const l of globalLocks) {
      const sig = l.match?.keyword ? `keyword "${l.match.keyword}"` : l.match?.genre ? `genre "${l.match.genre}"` : "?";
      console.error(`  → ${sig} → CH ${l.channelID}`);
    }
  }

  const results = [];
  for (const ch of channels) {
    results.push(await processChannel(ch, globalLocks, channelRulesById[ch.id]));
  }

  if (cachePath) {
    await fs.writeFile(cachePath, JSON.stringify(diskCache));
    console.error(`\nTMDB cache ${cachePath}: ${Object.keys(diskCache).length} responses`);
  }
  if (outDir) await fs.mkdir(outDir, { recursive: true });

  const report = renderReport(results, minRelatedCount);
  const reportPath = outDir ? path.join(outDir, "report.md") : path.join(__dirname, "report.md");
  await fs.writeFile(reportPath, report);
  console.error(`\nWrote ${reportPath}`);

  // Manifest is what the app consumes. When running on a subset of channels,
  // merge with the existing manifest so we don't lose claims for channels we
  // didn't re-process this run. The merge base is always the shipped file.
  const shippedManifestPath = path.join(__dirname, "..", "..", "channels-memberships.json");
  const manifestPath = outDir ? path.join(outDir, "channels-memberships.json") : shippedManifestPath;
  let existing = null;
  if (channelFilter) {
    try {
      existing = JSON.parse(await fs.readFile(shippedManifestPath, "utf8"));
    } catch { /* first run */ }
  }
  const fresh = buildManifest(results, minRelatedCount, channelRulesById, raw.handCurated || []);
  let manifest = fresh;
  if (existing) {
    // Drop any items whose ONLY channels are the ones being re-processed (so
    // they get rebuilt), then layer fresh on top.
    const processedIDs = new Set(channels.map(c => c.id));
    const merged = { ...existing.items };
    for (const [key, val] of Object.entries(merged)) {
      val.channels = val.channels.filter(id => !processedIDs.has(id));
      if (val.channels.length === 0) delete merged[key];
    }
    for (const [key, val] of Object.entries(fresh.items)) {
      if (merged[key]) {
        for (const cid of val.channels) {
          if (!merged[key].channels.includes(cid)) merged[key].channels.push(cid);
        }
      } else {
        merged[key] = val;
      }
    }
    manifest = { version: 1, generated: fresh.generated, minRelatedCount, items: merged };
  }
  await fs.writeFile(manifestPath, JSON.stringify(manifest, null, 2));
  console.error(`Wrote ${manifestPath} — ${Object.keys(manifest.items).length} items claimed`);
}

main().catch(err => {
  console.error("Fatal:", err);
  // Keep what was fetched so a rerun picks up where this one stopped.
  if (cachePath) fsSync.writeFileSync(cachePath, JSON.stringify(diskCache));
  process.exit(1);
});
