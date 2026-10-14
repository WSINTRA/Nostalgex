/**
 * TMDB and OMDb relay for the Apple TV app and the web tuner.
 *
 * The App Store build ships without a TMDB key. It asks this function for one of
 * four read-only TMDB routes; the function adds the key from the Vercel env
 * (`TMDB_API_KEY`), forwards the request, and hands back TMDB's JSON and status.
 * Vercel's edge cache keeps a 200 for a day and serves it stale for a week while
 * refetching, so a title that many libraries share costs TMDB one request, not one
 * per Apple TV.
 *
 * Allowlist. Nothing else is forwarded:
 *   movie/{id}         with append_to_response=keywords
 *   tv/{id}            with append_to_response=keywords
 *   collection/{id}
 *   search/collection  with query (and an optional page)
 *   omdb/{imdbID}      OMDb by IMDb id (tt plus 7 to 9 digits), key from `OMDB_API_KEY`
 *
 * OMDb answers live at the edge for 7 days and are served stale for 30 while
 * refetching: IMDb ratings and vote counts move slowly, and the OMDb free tier allows
 * 1,000 requests a day for every Apple TV and browser together. OMDb reports its
 * daily limit as HTTP 401 "Request limit reached!"; the relay turns that into a 429
 * so clients can tell it from a bad key.
 *
 * `X-Nostalgex-Client: tvos` (the Apple TV app) or `web` (the browser tuner) is a
 * cheap filter against stray browsers and crawlers, not security. Nothing about a
 * request is logged, ids included.
 *
 * CORS. The tuner on nostalgex.app calls this same-origin and needs nothing. A
 * cross-origin page (www vs apex, or the Vite dev server) sends a preflight because
 * of the custom header. Only the origins in ALLOWED_ORIGINS get their Origin echoed
 * back; anything else gets no Access-Control-Allow-Origin and the browser blocks it.
 */

const TMDB = 'https://api.themoviedb.org/3';
const OMDB = 'https://www.omdbapi.com/';
const CLIENT_HEADER = 'x-nostalgex-client';
const CLIENT_VALUES = new Set(['tvos', 'web']);
const ALLOWED_ORIGINS = new Set([
  'https://www.nostalgex.app',
  'https://nostalgex.app',
  'http://localhost:5173',
]);
const CACHE_OK = 'public, s-maxage=86400, stale-while-revalidate=604800';
const OMDB_CACHE_OK = 'public, s-maxage=604800, stale-while-revalidate=2592000';
const NO_STORE = 'no-store';

const ID_ROUTE = /^(movie|tv|collection)\/(\d{1,10})$/;
const SEARCH_ROUTE = 'search/collection';
const QUERY_MAX = 200;
const PAGE_RE = /^[1-9]\d{0,3}$/;
const PAGE_MAX = 1000;
const OMDB_ROUTE = /^omdb\/(tt\d{7,9})$/;

/**
 * The upstream path and query string for a request, or null when the request is not
 * on the allowlist. `service` is 'tmdb' or 'omdb'. The key is added by the handler,
 * never here. Exported for the smoke test.
 */
export function upstreamRequest(query) {
  const path = typeof query?.path === 'string' ? query.path : '';
  const params = new URLSearchParams();

  const omdbMatch = OMDB_ROUTE.exec(path);
  if (omdbMatch) {
    params.set('i', omdbMatch[1]);
    return { service: 'omdb', path: '', params };
  }

  const idMatch = ID_ROUTE.exec(path);
  if (idMatch) {
    const [, kind, id] = idMatch;
    if (kind !== 'collection') params.set('append_to_response', 'keywords');
    return { service: 'tmdb', path: `/${kind}/${id}`, params };
  }

  if (path === SEARCH_ROUTE) {
    const q = typeof query.query === 'string' ? query.query.trim() : '';
    if (!q || q.length > QUERY_MAX) return null;
    params.set('query', q);
    if (query.page !== undefined) {
      const page = typeof query.page === 'string' ? query.page : '';
      if (!PAGE_RE.test(page) || Number(page) > PAGE_MAX) return null;
      params.set('page', page);
    }
    return { service: 'tmdb', path: `/${SEARCH_ROUTE}`, params };
  }

  return null;
}

/**
 * CORS headers for one request. Every response varies on Origin and the client
 * header, so the edge cache never hands one origin's answer (or a 403 for a missing
 * header) to another. Exported for the smoke test.
 */
export function corsHeaders(origin) {
  const headers = { Vary: 'Origin, X-Nostalgex-Client' };
  if (typeof origin === 'string' && ALLOWED_ORIGINS.has(origin)) {
    headers['Access-Control-Allow-Origin'] = origin;
    headers['Access-Control-Allow-Headers'] = 'X-Nostalgex-Client';
    headers['Access-Control-Allow-Methods'] = 'GET, OPTIONS';
    headers['Access-Control-Max-Age'] = '86400';
  }
  return headers;
}

export default async function handler(req, res) {
  for (const [key, value] of Object.entries(corsHeaders(req.headers?.origin))) {
    res.setHeader(key, value);
  }

  if (req.method === 'OPTIONS') {
    res.setHeader('Allow', 'GET, OPTIONS');
    return res.status(204).end();
  }

  if (req.method !== 'GET') {
    res.setHeader('Allow', 'GET, OPTIONS');
    return res.status(405).json({ error: 'Method not allowed' });
  }

  if (!CLIENT_VALUES.has(req.headers?.[CLIENT_HEADER])) {
    return res.status(403).json({ error: 'Client header required' });
  }

  const upstream = upstreamRequest(req.query || {});
  if (!upstream) {
    return res.status(400).json({ error: 'Unsupported path' });
  }

  if (upstream.service === 'omdb') return relayOMDb(upstream, res);

  const apiKey = process.env.TMDB_API_KEY;
  if (!apiKey) {
    return res.status(500).json({ error: 'Server misconfigured' });
  }

  upstream.params.set('api_key', apiKey);

  let status;
  let data;
  try {
    const upstreamRes = await fetch(`${TMDB}${upstream.path}?${upstream.params}`, {
      headers: { Accept: 'application/json' },
    });
    status = upstreamRes.status;
    data = await upstreamRes.json();
  } catch {
    // Network failure, or TMDB answered with something that is not JSON (an HTML
    // error page during an outage). Either way the app should retry later, so
    // nothing is cached.
    res.setHeader('Cache-Control', NO_STORE);
    return res.status(502).json({ error: 'TMDB unavailable' });
  }

  // Only a 200 is worth keeping at the edge. A 404 for an id that TMDB later
  // creates, or a 429 while rate limited, should not be pinned for a day.
  res.setHeader('Cache-Control', status === 200 ? CACHE_OK : NO_STORE);
  return res.status(status).json(data);
}

/** True when an OMDb answer is its daily-limit error, whatever status it came with. */
export function isOMDbLimit(data) {
  const err = data && typeof data.Error === 'string' ? data.Error.toLowerCase() : '';
  return err.includes('limit reached');
}

async function relayOMDb(upstream, res) {
  const apiKey = process.env.OMDB_API_KEY;
  if (!apiKey) {
    return res.status(500).json({ error: 'Server misconfigured' });
  }

  upstream.params.set('apikey', apiKey);

  let status;
  let data;
  try {
    const upstreamRes = await fetch(`${OMDB}?${upstream.params}`, {
      headers: { Accept: 'application/json' },
    });
    status = upstreamRes.status;
    data = await upstreamRes.json();
  } catch {
    res.setHeader('Cache-Control', NO_STORE);
    return res.status(502).json({ error: 'OMDb unavailable' });
  }

  if (isOMDbLimit(data)) {
    res.setHeader('Cache-Control', NO_STORE);
    return res.status(429).json({ Response: 'False', Error: 'Request limit reached!' });
  }

  // A found title is cached. OMDb's `{"Response":"False"}` (unknown id, or a passing
  // "Error getting data.") comes back as a 200 too and is passed on uncached.
  const found = status === 200 && data && data.Response !== 'False';
  res.setHeader('Cache-Control', found ? OMDB_CACHE_OK : NO_STORE);
  return res.status(status).json(data);
}
