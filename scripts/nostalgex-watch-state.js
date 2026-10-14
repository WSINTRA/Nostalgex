// Report Playback without filling Continue Watching: the web port of the tvOS guard.
//
// PARITY CONTRACT with tvOS
//   Nostalgex/Nostalgex/Services/WatchStateGuard.swift   (WatchCleanupPlan, request shapes)
//   Nostalgex/Nostalgex/Services/PlaybackTracker.swift   (when capture and cleanup run)
//
// Both read scripts/watch-cleanup-golden.json: WatchStateGuardTests on the Swift side,
// `npm run test:watch-state` here. Change a rule in one engine without the other and
// one of those tests fails.
//
// The rule: Report Playback keeps Now Playing and real watches flowing to the user's
// server, but a program the tuner played must never be left in Continue Watching (Plex),
// Resume (Jellyfin, Emby) or On Deck.
//
// Plex: timeline reports carry no time or duration (PR #18), so Now Playing lists the
// title and Plex stores nothing; a surf needs no cleanup. A counted episode's next-up
// entry is removed unless its show was already in Continue Watching before tune-in.
// Jellyfin/Emby: the start report bumps PlayCount and a stop without a position marks the
// item played (Emby 4.10.1, 2026-10-13), so reports keep the position; we read UserData
// before the first report and put it back when the session ends.
// Numbers in Nostalgex/docs/plex-session-reporting.md.
//
// USAGE (browser: plain <script src="scripts/nostalgex-watch-state.js">,
// node: `import "./nostalgex-watch-state.js"`, then globalThis):
//
//   const WS = window.NostalgexWatchState;
//   const guard = WS.plexGuard({ serverUrl, authQuery: 'X-Plex-Token=...', fetchImpl: fetch });
//   WS.sharedQueue.enqueue(async () => { prior = await guard.capture(ratingKey, item.type); });
//   ...reports, all through WS.sharedQueue...
//   WS.sharedQueue.enqueue(() => guard.restore(ratingKey, prior, counted));

(function (global) {
  'use strict';

  const LIBRARY = 'com.plexapp.plugins.library';

  // ── The decision (must match WatchCleanupPlan in Swift) ──
  // prior: { resumePosition, playCount, played, lastPlayedDate, showKey, showInContinueWatching }
  // or null when the read failed. resumePosition is Plex ms or Jellyfin/Emby 100ns ticks.

  // Reports carry no position, so a surf leaves nothing to undo. An episode scrobble adds
  // the next episode to Continue Watching: remove it unless the show was already there.
  // Unknown prior: leave it, rather than remove a row the user had.
  function plexPlan(prior, counted) {
    if (!counted || !prior || !prior.showKey || prior.showInContinueWatching) return [];
    return [{ kind: 'removeShowFromContinueWatching', show: prior.showKey }];
  }

  function mediaServerPlan(prior, counted) {
    if (!prior) return [{ kind: 'userData', position: 0 }];
    if (counted) return [{ kind: 'userData', position: 0, playCount: prior.playCount + 1, played: true }];
    if (prior.resumePosition === 0 && prior.playCount === 0 && !prior.played) return [{ kind: 'markUnplayed' }];
    const step = { kind: 'userData', position: prior.resumePosition, playCount: prior.playCount, played: prior.played };
    if (prior.lastPlayedDate) step.lastPlayedDate = prior.lastPlayedDate;
    return [step];
  }

  /** Compact form used by scripts/watch-cleanup-golden.json. */
  function describe(step) {
    switch (step.kind) {
      case 'removeShowFromContinueWatching': return `removeShowFromContinueWatching ${step.show}`;
      case 'markUnplayed': return 'markUnplayed';
      case 'userData': {
        const parts = [`userData position=${step.position}`];
        if (step.playCount != null) parts.push(`playCount=${step.playCount}`);
        if (step.played != null) parts.push(`played=${step.played}`);
        if (step.lastPlayedDate) parts.push(`lastPlayedDate=${step.lastPlayedDate}`);
        return parts.join(' ');
      }
      default: return step.kind;
    }
  }

  // ── Ordering ──
  // Every report and cleanup goes through one queue, so a Jellyfin/Emby restore always
  // lands after the last report (which would otherwise write a position over it).
  function createReportQueue() {
    let tail = Promise.resolve();
    return {
      enqueue(op) {
        tail = tail.then(op).catch(() => {});
        return tail;
      },
      drain() { return tail; },
    };
  }

  // ── Backoff (must match PulseBackoff in Swift) ──
  // A server that stops answering gets fewer 10 second pulses, never a changed setting:
  // each failure skips 1, 2, 4 ... up to 30 pulses; any answered report resets it.
  // Starts, stops, scrobbles and cleanup always go out.
  function createPulseBackoff() {
    let failures = 0;
    let skip = 0;
    return {
      allowPulse() {
        if (skip > 0) { skip -= 1; return false; }
        return true;
      },
      record(success) {
        if (success) { failures = 0; skip = 0; return; }
        failures += 1;
        skip = Math.min(30, 1 << Math.min(failures - 1, 5));
      },
    };
  }

  async function send(fetchImpl, method, url, opts) {
    const o = opts || {};
    try {
      const res = await fetchImpl(url, {
        method,
        headers: Object.assign({ Accept: 'application/json' }, o.headers || {}),
        body: o.body,
        keepalive: !!o.keepalive,
      });
      let json = null;
      if (o.json) { try { json = await res.json(); } catch (_) { json = null; } }
      return { status: res.status, json };
    } catch (_) {
      return null;
    }
  }

  // ── Plex ──
  function plexGuard({ serverUrl, authQuery, fetchImpl, retryDelayMs }) {
    const f = fetchImpl || global.fetch.bind(global);
    const url = (path, params) => {
      const q = new URLSearchParams(params || {}).toString();
      return `${serverUrl}${path}?${q}${q && authQuery ? '&' : ''}${authQuery || ''}`;
    };
    const ok = r => r && r.status >= 200 && r.status < 300;

    async function continueWatching() {
      const r = await send(f, 'GET', url('/hubs/continueWatching/items', { count: '200' }), { json: true });
      if (!ok(r) || !r.json || !r.json.MediaContainer) return null;
      return r.json.MediaContainer.Metadata || [];
    }

    const delay = retryDelayMs == null ? 1000 : retryDelayMs;

    return {
      url,
      /** `key` is the bare rating key; /library/metadata/{rk} is answered with 404. */
      scrobbleUrl: rk => url('/:/scrobble', { key: rk, identifier: LIBRARY }),
      /** Position-free: no time or duration, so Plex lists it in Now Playing and stores nothing. */
      timelineUrl: (rk, state, sessionId) => url('/:/timeline', {
        ratingKey: rk, key: `/library/metadata/${rk}`, state, 'X-Plex-Session-Identifier': sessionId,
      }),
      /** Episodes only: is the show already in Continue Watching? Films cost no request. */
      async capture(rk, type) {
        if (type && type !== 'episode') return null;
        const r = await send(f, 'GET', url(`/library/metadata/${encodeURIComponent(rk)}`), { json: true });
        const meta = ok(r) && r.json && r.json.MediaContainer && (r.json.MediaContainer.Metadata || [])[0];
        if (!meta || meta.type !== 'episode' || !meta.grandparentRatingKey) return null;
        const show = String(meta.grandparentRatingKey);
        const row = await continueWatching();
        return {
          resumePosition: 0, playCount: 0, played: false, lastPlayedDate: null,
          showKey: show,
          // Unreadable row: assume the show was there, so we never remove a real entry.
          showInContinueWatching: row
            ? row.some(e => String(e.grandparentRatingKey) === show || String(e.ratingKey) === show)
            : true,
        };
      },
      async restore(rk, prior, counted, opts) {
        const keepalive = !!(opts && opts.keepalive);
        for (const step of plexPlan(prior, counted)) {
          // Plex adds the next episode about a second after the scrobble. Look up to three times.
          for (let attempt = 0; attempt < 3; attempt++) {
            const row = (await continueWatching()) || [];
            const added = row.filter(x => String(x.grandparentRatingKey) === step.show);
            for (const e of added) {
              const r = await send(f, 'PUT', url('/actions/removeFromContinueWatching', { ratingKey: String(e.ratingKey) }), { keepalive });
              console.log('[Tracker] cleanup', rk, 'removeFromContinueWatching next-up', e.ratingKey, r ? r.status : 'failed');
            }
            if (added.length || attempt === 2) break;
            await new Promise(res => setTimeout(res, delay));
          }
        }
      },
    };
  }

  // ── Jellyfin / Emby ── (both answer the /Users/{id}/... routes)
  function mediaServerGuard({ serverUrl, userId, authHeader, fetchImpl }) {
    const f = fetchImpl || global.fetch.bind(global);
    const base = `${serverUrl}/Users/${encodeURIComponent(userId)}`;
    const headers = () => ({ Authorization: typeof authHeader === 'function' ? authHeader() : authHeader });
    const ok = r => r && r.status >= 200 && r.status < 300;

    function stepRequest(step, id) {
      const item = encodeURIComponent(id);
      if (step.kind === 'markUnplayed') return ['DELETE', `${base}/PlayedItems/${item}`, null];
      if (step.kind === 'userData') {
        const body = { PlaybackPositionTicks: step.position };
        if (step.playCount != null) body.PlayCount = step.playCount;
        if (step.played != null) body.Played = step.played;
        if (step.lastPlayedDate) body.LastPlayedDate = step.lastPlayedDate;
        return ['POST', `${base}/Items/${item}/UserData`, JSON.stringify(body)];
      }
      return null;
    }

    return {
      markPlayedUrl: id => `${base}/PlayedItems/${encodeURIComponent(id)}`,
      async capture(id) {
        const r = await send(f, 'GET', `${base}/Items/${encodeURIComponent(id)}`, { json: true, headers: headers() });
        const data = ok(r) && r.json && r.json.UserData;
        if (!data) return null;
        return {
          resumePosition: data.PlaybackPositionTicks || 0,
          playCount: data.PlayCount || 0,
          played: !!data.Played,
          lastPlayedDate: data.LastPlayedDate || null,
          showKey: null,
          showInContinueWatching: false,
        };
      },
      async restore(id, prior, counted, opts) {
        const keepalive = !!(opts && opts.keepalive);
        for (const step of mediaServerPlan(prior, counted)) {
          const req = stepRequest(step, id);
          if (!req) continue;
          const h = headers();
          if (req[2]) h['Content-Type'] = 'application/json';
          const r = await send(f, req[0], req[1], { headers: h, body: req[2] || undefined, keepalive });
          console.log('[Tracker] cleanup', id, describe(step), r ? r.status : 'failed');
        }
      },
    };
  }

  const api = {
    plexPlan,
    mediaServerPlan,
    describe,
    createReportQueue,
    createPulseBackoff,
    sharedQueue: createReportQueue(),
    plexGuard,
    mediaServerGuard,
  };

  global.NostalgexWatchState = api;
  if (typeof module !== 'undefined' && typeof module.exports !== 'undefined') {
    module.exports = api;
  }
})(typeof window !== 'undefined' ? window : globalThis);
