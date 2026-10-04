#!/usr/bin/env node
/**
 * Jellyfin channel diagnosis — why a Jellyfin library produces no channels.
 *
 * Replays EXACTLY what the tvOS app does (JellyfinAPIService.loadSections /
 * fetchAllItems / parseMovieItem / fetchEpisodes), then runs the shared channel
 * filter (scripts/nostalgex-channel-filter.cjs) over the parsed items and reports
 * which channels build, which don't, and — crucially — how many raw server items
 * were dropped before the filter ever ran.
 *
 * Usage:
 *   node scripts/jellyfin-channel-diagnose.mjs --url https://jf.example.com --key <API_KEY> [--user <username>]
 *   node scripts/jellyfin-channel-diagnose.mjs --url http://192.168.1.5:8096 --user chad --pass hunter2
 *
 * An API key comes from Jellyfin Dashboard -> Advanced -> API Keys.
 */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const filter = require(path.join(ROOT, 'scripts/nostalgex-channel-filter.cjs'));

// ---------------------------------------------------------------- args

const args = {};
for (let i = 2; i < process.argv.length; i++) {
  const a = process.argv[i];
  if (a.startsWith('--')) args[a.slice(2)] = process.argv[i + 1]?.startsWith('--') ? true : process.argv[++i];
}
if (!args.url) {
  console.error('Missing --url. See header of this file for usage.');
  process.exit(1);
}
const serverURL = String(args.url).replace(/\/+$/, '');

// Same device id shape the app sends.
const DEVICE_ID = 'nostalgex-diagnose';
const authHeader = (token) =>
  'MediaBrowser ' +
  ['Client="Nostalgex"', 'Device="Apple TV"', `DeviceId="${DEVICE_ID}"`, 'Version="1.0"']
    .concat(token ? [`Token="${token}"`] : [])
    .join(', ');

let token = args.key || '';
let userId = args.userid || '';

async function jf(pathname, query = {}, tok = token) {
  const url = new URL(serverURL + pathname);
  for (const [k, v] of Object.entries(query)) if (v != null) url.searchParams.set(k, v);
  const res = await fetch(url, {
    headers: { Accept: 'application/json', Authorization: authHeader(tok) },
  });
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`HTTP ${res.status} ${pathname} :: ${body.slice(0, 240)}`);
  }
  return res.json();
}

// ---------------------------------------------------------------- auth

async function connect() {
  const info = await fetch(serverURL + '/System/Info/Public').then((r) => r.json());
  console.log(`SERVER  ${info.ServerName} — Jellyfin ${info.Version}`);

  if (args.pass != null || args.anon) {
    const res = await fetch(serverURL + '/Users/AuthenticateByName', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: authHeader('') },
      body: JSON.stringify({ Username: args.user, Pw: args.pass === true ? '' : (args.pass || '') }),
    });
    if (!res.ok) throw new Error(`auth failed: HTTP ${res.status}`);
    const auth = await res.json();
    token = auth.AccessToken;
    userId = auth.User.Id;
    console.log(`AUTH    signed in as ${auth.User.Name}`);
    return;
  }

  if (!token) throw new Error('Provide --key <API_KEY> or --user/--pass.');
  const users = await jf('/Users');
  const picked = args.user ? users.find((u) => u.Name === args.user) : users[0];
  if (!picked) throw new Error(`No such user: ${args.user}. Have: ${users.map((u) => u.Name).join(', ')}`);
  userId = picked.Id;
  console.log(`AUTH    API key, acting as ${picked.Name}`);
}

// ---------------------------------------------------------------- fetch (mirrors the app)

// Byte-for-byte the Fields string JellyfinAPIService.fetchAllItems sends.
const APP_FIELDS = 'ProviderIds,Overview,Genres,Studios,MediaSources,ProductionYear,PremiereDate,DateCreated,UserData';
const PAGE = 200;

/** JellyfinAPIService.sectionType(for:) */
function sectionType(collectionType) {
  switch ((collectionType || '').toLowerCase()) {
    case 'tvshows': return 'show';
    case 'musicvideos': return 'musicvideo';
    default: return 'movie';
  }
}

async function fetchAllItems(parentId, includeItemTypes) {
  const out = [];
  let start = 0;
  for (;;) {
    const page = await jf('/Items', {
      userId,
      ParentId: parentId,
      Recursive: 'true',
      IncludeItemTypes: includeItemTypes,
      Fields: APP_FIELDS,
      StartIndex: String(start),
      Limit: String(PAGE),
      SortBy: 'SortName',
    });
    const items = page.Items || [];
    out.push(...items);
    const total = page.TotalRecordCount ?? out.length;
    start += items.length;
    if (!items.length || out.length >= total) break;
  }
  return out;
}

// ---------------------------------------------------------------- parse (mirrors the app)

const minutesFromTicks = (ticks) => (ticks ? Math.floor(Number(ticks) / 600_000_000) : 0);
const providerId = (raw, key) => {
  const ids = raw.ProviderIds || {};
  const hit = Object.entries(ids).find(([k]) => k.toLowerCase() === key);
  return hit?.[1] || null;
};

/** Every place JellyfinAPIService can silently discard a server item. */
const drops = { noRuntime: [], noGenres: [], noYear: [], noRating: [], noTmdb: [] };

function parseMovie(raw, isMusicSection) {
  const durationMin = minutesFromTicks(raw.RunTimeTicks);
  if (durationMin <= 0) { drops.noRuntime.push(raw.Name); return null; }  // <- app's hard drop
  const genres = raw.Genres || [];
  if (!genres.length) drops.noGenres.push(raw.Name);
  if (!raw.ProductionYear) drops.noYear.push(raw.Name);
  if (!raw.OfficialRating) drops.noRating.push(raw.Name);
  if (!providerId(raw, 'tmdb')) drops.noTmdb.push(raw.Name);
  const isMusicVideo = isMusicSection || (durationMin <= 10 && genres.some((g) => /music/i.test(g)));
  return {
    title: raw.Name || '',
    genres,
    year: raw.ProductionYear ?? null,
    originallyAvailableAt: raw.PremiereDate ? String(raw.PremiereDate).slice(0, 10) : null,
    contentRating: raw.OfficialRating ?? null,
    duration: durationMin,
    rating: raw.CommunityRating ?? 0,
    userRating: 0,
    type: 'movie',
    viewCount: raw.UserData?.PlayCount ?? (raw.UserData?.Played ? 1 : 0),
    addedAt: raw.DateCreated ? Math.floor(Date.parse(raw.DateCreated) / 1000) : 0,
    studio: raw.Studios?.[0]?.Name ?? null,
    tmdbID: providerId(raw, 'tmdb'),
    librarySource: isMusicVideo ? 'musicVideo' : 'movie',
  };
}

function parseEpisodes(show, episodes) {
  const showGenres = show.Genres || [];
  if (!showGenres.length) drops.noGenres.push(`${show.Name} (series)`);
  if (!providerId(show, 'tmdb')) drops.noTmdb.push(`${show.Name} (series)`);
  const out = [];
  for (const ep of episodes) {
    const durationMin = minutesFromTicks(ep.RunTimeTicks);
    if (durationMin <= 0) { drops.noRuntime.push(`${show.Name} ${ep.Name}`); continue; }
    out.push({
      title: show.Name || ep.SeriesName || '',
      genres: showGenres,
      year: show.ProductionYear ?? null,
      originallyAvailableAt: (ep.PremiereDate || show.PremiereDate || '').slice(0, 10) || null,
      contentRating: show.OfficialRating ?? ep.OfficialRating ?? null,
      duration: durationMin,
      rating: show.CommunityRating ?? 0,
      userRating: 0,
      type: 'episode',
      viewCount: ep.UserData?.PlayCount ?? (ep.UserData?.Played ? 1 : 0),
      addedAt: ep.DateCreated ? Math.floor(Date.parse(ep.DateCreated) / 1000) : 0,
      studio: show.Studios?.[0]?.Name ?? null,
      tmdbID: providerId(show, 'tmdb'),
      librarySource: 'tv',
    });
  }
  return out;
}

// ---------------------------------------------------------------- run

function bar(label, n, total) {
  const pct = total ? Math.round((n / total) * 100) : 0;
  return `${label.padEnd(26)} ${String(n).padStart(6)} / ${total}  (${String(pct).padStart(3)}%)`;
}

async function main() {
  await connect();

  const views = await jf('/UserViews', { userId });
  const sections = (views.Items || []).map((v) => ({
    key: v.Id,
    title: v.Name || 'Library',
    collectionType: v.CollectionType ?? null,
    type: sectionType(v.CollectionType),
  }));

  console.log('\n=== LIBRARIES (as the app sees them) ===');
  for (const s of sections) {
    const note = s.collectionType == null ? '  <- no CollectionType: app treats it as MOVIES' : '';
    console.log(`  ${s.title.padEnd(28)} CollectionType=${String(s.collectionType).padEnd(12)} -> ${s.type}${note}`);
  }

  const items = [];
  let rawMovies = 0, rawSeries = 0, rawEpisodes = 0;

  for (const s of sections) {
    if (s.type === 'show') {
      const series = await fetchAllItems(s.key, 'Series');
      rawSeries += series.length;
      process.stdout.write(`\n  scanning ${s.title}: ${series.length} series`);
      for (const show of series) {
        const eps = await fetchAllItems(show.Id, 'Episode');
        rawEpisodes += eps.length;
        items.push(...parseEpisodes(show, eps));
      }
      process.stdout.write(` / ${rawEpisodes} episodes\n`);
    } else {
      const raw = await fetchAllItems(s.key, 'Movie');
      rawMovies += raw.length;
      process.stdout.write(`\n  scanning ${s.title}: ${raw.length} movies\n`);
      for (const r of raw) {
        const parsed = parseMovie(r, s.type === 'musicvideo');
        if (parsed) items.push(parsed);
      }
    }
  }

  const rawTotal = rawMovies + rawEpisodes;
  console.log('\n=== PARSE ===');
  console.log(`  server returned      ${rawTotal} items (${rawMovies} movies, ${rawSeries} series -> ${rawEpisodes} episodes)`);
  console.log(`  app kept             ${items.length}`);
  console.log(`  DROPPED, no runtime  ${drops.noRuntime.length}   <- RunTimeTicks missing/0; the app discards these outright`);
  if (drops.noRuntime.length) console.log(`     e.g. ${drops.noRuntime.slice(0, 5).join(' | ')}`);

  console.log('\n=== METADATA COVERAGE (of kept items) ===');
  const kept = items.length;
  console.log('  ' + bar('has genres', kept - items.filter((i) => !i.genres.length).length, kept));
  console.log('  ' + bar('has year', items.filter((i) => i.year).length, kept));
  console.log('  ' + bar('has content rating', items.filter((i) => i.contentRating).length, kept));
  console.log('  ' + bar('has tmdbID', items.filter((i) => i.tmdbID).length, kept));
  const genreHist = new Map();
  for (const i of items) for (const g of i.genres) genreHist.set(g, (genreHist.get(g) || 0) + 1);
  const topGenres = [...genreHist].sort((a, b) => b[1] - a[1]).slice(0, 15);
  console.log(`  top genres: ${topGenres.map(([g, n]) => `${g}(${n})`).join(', ') || 'NONE'}`);

  // -------------------------------------------------------------- channels
  const config = JSON.parse(fs.readFileSync(path.join(ROOT, 'channels.json'), 'utf8'));
  let manifest = null;
  try { manifest = JSON.parse(fs.readFileSync(path.join(ROOT, 'channels-memberships.json'), 'utf8')); } catch {}
  const exclusiveRules = config.exclusiveRules || [];

  const pools = new Map();
  for (const ch of config.channels) {
    const { items: pool } = filter.filterPool(items, ch, { manifest, exclusiveRules });
    pools.set(ch.id, pool.length);
  }

  console.log('\n=== BUNDLES (what the Packages screen will show) ===');
  const byID = new Map(config.channels.map((c) => [c.id, c]));
  for (const b of config.bundles || []) {
    const rows = b.channelIDs.map((id) => {
      const ch = byID.get(id);
      const n = pools.get(id) ?? 0;
      const min = ch?.minItems ?? 50;
      return { name: ch?.name ?? `#${id}`, n, min, ok: n >= min };
    });
    const ok = rows.filter((r) => r.ok);
    console.log(`\n  ${b.name}  ${ok.length}/${rows.length} CH`);
    for (const r of rows) {
      console.log(`     ${r.ok ? 'OK  ' : 'MISS'} ${r.name.padEnd(24)} pool=${String(r.n).padStart(5)}  needs ${r.min}`);
    }
  }

  const built = config.channels.filter((c) => (pools.get(c.id) ?? 0) >= (c.minItems ?? 50));
  console.log(`\n=== TOTAL: ${built.length}/${config.channels.length} channels would build ===`);
}

main().catch((e) => { console.error('\nFAILED:', e.message); process.exit(1); });
