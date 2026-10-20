#!/usr/bin/env node
/**
 * Jellyfin Quick Connect in the web tuner (the Docker image serves the same page).
 *
 *   1. NostalgexJellyfinUrls.quickConnectInitiate against a recording fetch: POST first,
 *      GET again only on 405 or 404, same URL and headers, no body.
 *   2. web-tuner.html's own Jellyfin sign-in section, run in a VM with a small fake DOM
 *      against fake servers with each Jellyfin route table for Initiate (12.x POST only,
 *      10.9 to 10.11 both, 10.7 and 10.8 GET only): code shown, poll, sign-in saved.
 *      Negative controls: the old GET-only initiate fails the same 12.x checks.
 *   3. Live, only when NOSTALGEX_JF_URL, NOSTALGEX_JF_APPROVER_TOKEN (admin API key or the
 *      user's own token) and NOSTALGEX_JF_USER are set: the same page section with Node's
 *      fetch against a real Jellyfin, through AuthenticateWithQuickConnect. Prints no token.
 *
 * Measured 2026-10-19 on Jellyfin 12.2.0: GET /QuickConnect/Initiate 405, POST 200.
 *
 * Run: `npm run test:jellyfin-quick-connect`
 */
import { readFileSync } from "node:fs";
import vm from "node:vm";
import assert from "node:assert/strict";
import "./nostalgex-jellyfin-urls.js";

const JU = globalThis.NostalgexJellyfinUrls;
const S = "http://192.168.1.50:8096";
const HEADERS = { Accept: "application/json", Authorization: 'MediaBrowser Client="Nostalgex", Device="Browser", DeviceId="d", Version="1.0"' };

let passed = 0;
const failures = [];
async function check(label, fn) {
  try { await fn(); passed += 1; } catch (e) { failures.push(`${label}: ${e.stack || e.message}`); }
}
async function fails(fn) {
  try { await fn(); } catch (e) { return true; }
  return false;
}

// ── 1. The module ──────────────────────────────────────────────────────────

function recordingFetch(answers) {
  const calls = [];
  const fetch = async (url, init = {}) => {
    calls.push({ url, method: init.method || "GET", headers: init.headers, body: init.body });
    const next = answers.length ? answers.shift() : 500;
    if (next === "throw") throw new TypeError("Failed to fetch");
    return { status: next, ok: next >= 200 && next < 300, json: async () => ({ Code: "123456", Secret: "s" }) };
  };
  return { calls, fetch, methods: () => calls.map((c) => c.method) };
}

// Each takes an initiate implementation so the old one can be run through them too.
const initiateChecks = {
  "initiate is one POST to /QuickConnect/Initiate, headers kept, no body": async (initiate) => {
    const r = recordingFetch([200]);
    const res = await initiate(S, HEADERS, r.fetch);
    assert.equal(res.status, 200);
    assert.deepEqual(r.methods(), ["POST"]);
    assert.equal(r.calls[0].url, `${S}/QuickConnect/Initiate`);
    assert.equal(r.calls[0].headers, HEADERS);
    assert.equal(r.calls[0].body, undefined);
  },
  "a 405 (Jellyfin 10.7, 10.8) tries GET once, same URL and headers": async (initiate) => {
    const r = recordingFetch([405, 200]);
    const res = await initiate(S, HEADERS, r.fetch);
    assert.equal(res.status, 200);
    assert.deepEqual(r.methods(), ["POST", "GET"]);
    assert.deepEqual(r.calls.map((c) => c.url), [`${S}/QuickConnect/Initiate`, `${S}/QuickConnect/Initiate`]);
    assert.equal(r.calls[1].headers, HEADERS);
  },
};

for (const [label, fn] of Object.entries(initiateChecks)) {
  await check(label, () => fn(JU.quickConnectInitiate));
}
await check("a 404 tries GET once", async () => {
  const r = recordingFetch([404, 200]);
  assert.equal((await JU.quickConnectInitiate(S, HEADERS, r.fetch)).status, 200);
  assert.deepEqual(r.methods(), ["POST", "GET"]);
});
await check("two 404s hand back the 404 (not Jellyfin)", async () => {
  const r = recordingFetch([404, 404]);
  assert.equal((await JU.quickConnectInitiate(S, HEADERS, r.fetch)).status, 404);
  assert.deepEqual(r.methods(), ["POST", "GET"]);
});
await check("Quick Connect off (401) is not retried", async () => {
  const r = recordingFetch([401, 200]);
  assert.equal((await JU.quickConnectInitiate(S, HEADERS, r.fetch)).status, 401);
  assert.deepEqual(r.methods(), ["POST"]);
});
for (const status of [400, 403, 500, 502, 503]) {
  await check(`HTTP ${status} is not retried`, async () => {
    const r = recordingFetch([status, 200]);
    assert.equal((await JU.quickConnectInitiate(S, HEADERS, r.fetch)).status, status);
    assert.deepEqual(r.methods(), ["POST"]);
  });
}
await check("a network failure rejects as fetch does, no retry", async () => {
  const r = recordingFetch(["throw", 200]);
  await assert.rejects(() => JU.quickConnectInitiate(S, HEADERS, r.fetch), /Failed to fetch/);
  assert.deepEqual(r.methods(), ["POST"]);
});
await check("retry rule: 405 and 404 only", () => {
  for (const s of [405, 404]) assert.equal(JU.quickConnectInitiateRetriesWithGet(s), true, s);
  for (const s of [200, 204, 400, 401, 403, 500]) assert.equal(JU.quickConnectInitiateRetriesWithGet(s), false, s);
});
await check("without a fetch argument it uses the page's fetch", async () => {
  const saved = globalThis.fetch;
  const r = recordingFetch([200]);
  globalThis.fetch = r.fetch;
  try { await JU.quickConnectInitiate(S, HEADERS); } finally { globalThis.fetch = saved; }
  assert.deepEqual(r.methods(), ["POST"]);
});

// The web tuner's call before this fix, through the same checks.
const oldInitiate = (serverUrl, headers, fetch) => fetch(`${serverUrl}/QuickConnect/Initiate`, { headers });
for (const label of Object.keys(initiateChecks)) {
  await check(`negative control: the old GET-only initiate fails "${label}"`, async () =>
    assert.equal(await fails(() => initiateChecks[label](oldInitiate)), true));
}

// ── 2. web-tuner.html's own Jellyfin section, against a fake DOM ────────────

const page = readFileSync(new URL("../web-tuner.html", import.meta.url), "utf8");
const moduleSource = readFileSync(new URL("./nostalgex-jellyfin-urls.js", import.meta.url), "utf8");
const htmlIds = new Set([...page.matchAll(/\bid=["']([^"']+)["']/g)].map((m) => m[1]));
const sectionStart = "  // ---- Jellyfin Auth ----";
const sectionEnd = "  document.getElementById('connect-jellyfin-btn').addEventListener";
const a = page.indexOf(sectionStart), b = page.indexOf(sectionEnd, a);
assert(a >= 0 && b > a, "web-tuner.html Jellyfin section anchors");
const section = page.slice(a, b);

const NEW_CALL = `      const initRes = await NostalgexJellyfinUrls.quickConnectInitiate(url,
        { 'Accept': 'application/json', 'Authorization': jellyfinAuthHeader('') });`;
const OLD_CALL = `      const initRes = await fetch(\`\${url}/QuickConnect/Initiate\`, {
        headers: { 'Accept': 'application/json', 'Authorization': jellyfinAuthHeader('') },
      });`;

class FakeElement {
  constructor(id) {
    this.id = id; this.value = ""; this.textContent = ""; this.style = {}; this._classes = new Set();
    this.classList = { add: (c) => this._classes.add(c), remove: (c) => this._classes.delete(c), contains: (c) => this._classes.has(c) };
  }
  addEventListener() {}
}
class FakeStorage {
  constructor() { this.m = new Map(); }
  getItem(k) { return this.m.has(k) ? this.m.get(k) : null; }
  setItem(k, v) { this.m.set(k, String(v)); }
  removeItem(k) { this.m.delete(k); }
}

/** The page section in a VM. `fetch` is what the page's own fetch calls go through. */
function pageFixture({ fetch, transform = (src) => src, serverUrl = S, clientId = "nostalgex-qc-smoke" }) {
  const elements = new Map();
  const intervals = new Map();
  let seq = 0;
  const document = {
    getElementById(id) {
      assert(htmlIds.has(id), `fixture element exists in web-tuner.html: ${id}`);
      if (!elements.has(id)) elements.set(id, new FakeElement(id));
      return elements.get(id);
    },
  };
  const context = {
    console: { log() {}, warn() {}, error() {} },
    document, fetch,
    location: { protocol: "http:", href: "http://tuner.local/web-tuner.html" },
    sessionStorage: new FakeStorage(), localStorage: new FakeStorage(),
    setInterval: (fn) => { const id = ++seq; intervals.set(id, fn); return id; },
    clearInterval: (id) => intervals.delete(id),
    getClientId: () => clientId,
  };
  context.window = context;
  vm.createContext(context);
  const src = transform(section);
  vm.runInContext(`${moduleSource}\n${src}`, context);
  document.getElementById("jf-url").value = serverUrl;
  return {
    context,
    el: (id) => document.getElementById(id),
    intervals,
    // One poll, awaited, then let the sign-in finish (completeJellyfinAuth is not awaited).
    async tick() {
      for (const fn of [...intervals.values()]) await fn();
      for (let i = 0; i < 30; i++) await new Promise((r) => setImmediate(r));
    },
    saved: () => JSON.parse(context.localStorage.getItem("plex90_saved_auth") || "null"),
    shownError: () => (document.getElementById("connect-jellyfin-error").style.display === "block"
      ? document.getElementById("connect-jellyfin-error").textContent : null),
  };
}

/** A fake Jellyfin with one version's route table for Initiate. */
function fakeJellyfin({ initiate, quickConnectOn = true, unreachable = false, notJellyfin = false }) {
  const calls = [];
  let approved = false;
  const json = (status, body) => ({ status, ok: status >= 200 && status < 300, json: async () => body });
  const fetch = async (url, init = {}) => {
    const u = new URL(url);
    const method = init.method || "GET";
    calls.push({ method, path: u.pathname, query: Object.fromEntries(u.searchParams), body: init.body, headers: init.headers });
    if (unreachable) throw new TypeError("Failed to fetch");
    if (notJellyfin) return json(404, null);
    switch (u.pathname) {
      case "/QuickConnect/Initiate":
        if (!initiate.includes(method)) return json(405, null);
        if (!quickConnectOn) return json(401, null);
        return json(200, { Authenticated: false, Secret: "s3cr3t", Code: "123456", DeviceId: "d", DeviceName: "Browser" });
      case "/QuickConnect/Connect":
        if (method !== "GET") return json(405, null);
        return json(200, { Authenticated: approved, Secret: u.searchParams.get("Secret"), Code: "123456" });
      case "/Users/AuthenticateWithQuickConnect":
        if (method !== "POST") return json(405, null);
        if (!approved || JSON.parse(init.body).Secret !== "s3cr3t") return json(401, null);
        return json(200, { AccessToken: "tok", ServerId: "srv", User: { Id: "u1", Name: "lab", ServerName: "Lab" } });
      case "/System/Info/Public":
        return json(200, { ServerName: "Lab", Version: "12.2.0", ProductName: "Jellyfin Server", Id: "srv" });
      default:
        return json(404, null);
    }
  };
  return { fetch, calls, approve: () => { approved = true; }, log: () => calls.map((c) => `${c.method} ${c.path}`) };
}

const VERSIONS = {
  "Jellyfin 12.x": ["POST"],
  "Jellyfin 10.9 to 10.11": ["POST", "GET"],
  "Jellyfin 10.7 and 10.8": ["GET"],
};

/** The whole sign-in on one fake server. Throws when anything is off. */
async function signInScenario(version, transform) {
  const server = fakeJellyfin({ initiate: VERSIONS[version] });
  const f = pageFixture({ fetch: server.fetch, transform });
  await f.context.jellyfinQuickConnect();
  assert.equal(f.shownError(), null, "no error after Initiate");
  assert.equal(f.el("connect-jf-code").textContent, "123456", "code shown");
  assert.equal(f.el("connect-jellyfin-quick").classList.contains("active"), true);
  assert.equal(f.intervals.size, 1, "polling");
  await f.tick();
  assert.equal(f.saved(), null, "nothing saved before approval");
  server.approve();
  await f.tick();
  assert.equal(f.intervals.size, 0, "polling stopped");
  const initiate = version === "Jellyfin 10.7 and 10.8" ? ["POST /QuickConnect/Initiate", "GET /QuickConnect/Initiate"] : ["POST /QuickConnect/Initiate"];
  assert.deepEqual(server.log(), [...initiate, "GET /QuickConnect/Connect", "GET /QuickConnect/Connect",
    "POST /Users/AuthenticateWithQuickConnect", "GET /System/Info/Public"]);
  const connect = server.calls.find((c) => c.path === "/QuickConnect/Connect");
  assert.equal(connect.query.Secret, "s3cr3t");
  const auth = server.calls.find((c) => c.path === "/Users/AuthenticateWithQuickConnect");
  assert.deepEqual(JSON.parse(auth.body), { Secret: "s3cr3t" });
  assert.match(auth.headers.Authorization, /^MediaBrowser Client="Nostalgex", Device="Browser", DeviceId="nostalgex-qc-smoke"/);
  const saved = f.saved();
  assert.equal(saved.backend, "jellyfin");
  assert.equal(saved.token, "tok");
  assert.equal(saved.jellyfinUserId, "u1");
  assert.equal(saved.serverUrl, S);
  assert.equal(f.context.location.href, "plex-tuner.html");
  return server;
}

for (const version of Object.keys(VERSIONS)) {
  await check(`page: Quick Connect signs in on ${version}`, () => signInScenario(version));
}
await check("page: Quick Connect off says so, one request, no polling", async () => {
  const server = fakeJellyfin({ initiate: ["POST"], quickConnectOn: false });
  const f = pageFixture({ fetch: server.fetch });
  await f.context.jellyfinQuickConnect();
  assert.equal(f.shownError(), "QUICK CONNECT IS NOT ENABLED ON THIS SERVER");
  assert.deepEqual(server.log(), ["POST /QuickConnect/Initiate"]);
  assert.equal(f.intervals.size, 0);
});
await check("page: an unreachable server gets the network message, no retry", async () => {
  const server = fakeJellyfin({ initiate: ["POST"], unreachable: true });
  const f = pageFixture({ fetch: server.fetch });
  await f.context.jellyfinQuickConnect();
  assert.match(f.shownError(), /^COULD NOT REACH THE JELLYFIN SERVER/);
  assert.deepEqual(server.log(), ["POST /QuickConnect/Initiate"]);
});
await check("page: a server that isn't Jellyfin (404 both ways) is an error, not a code", async () => {
  const server = fakeJellyfin({ initiate: [], notJellyfin: true });
  const f = pageFixture({ fetch: server.fetch });
  await f.context.jellyfinQuickConnect();
  assert.equal(f.shownError(), "QUICK CONNECT IS NOT ENABLED ON THIS SERVER");
  assert.deepEqual(server.log(), ["POST /QuickConnect/Initiate", "GET /QuickConnect/Initiate"]);
  assert.equal(f.intervals.size, 0);
});

// The page as it was: its own section with the old GET-only call put back.
await check("negative control: the page still has the call this test swaps out", () =>
  assert.equal(section.includes(NEW_CALL), true));
const toOldCall = (src) => src.replace(NEW_CALL, OLD_CALL);
await check("negative control: the old page fails the Jellyfin 12.x sign-in", async () =>
  assert.equal(await fails(() => signInScenario("Jellyfin 12.x", toOldCall)), true));
await check("negative control: the old page shows NOT ENABLED on Jellyfin 12.x after a GET 405", async () => {
  const server = fakeJellyfin({ initiate: ["POST"] });
  const f = pageFixture({ fetch: server.fetch, transform: toOldCall });
  await f.context.jellyfinQuickConnect();
  assert.equal(f.shownError(), "QUICK CONNECT IS NOT ENABLED ON THIS SERVER");
  assert.deepEqual(server.log(), ["GET /QuickConnect/Initiate"]);
});

// ── 3. Live, against a real Jellyfin (opt-in) ──────────────────────────────

const live = { url: process.env.NOSTALGEX_JF_URL, approver: process.env.NOSTALGEX_JF_APPROVER_TOKEN, user: process.env.NOSTALGEX_JF_USER };
let liveSummary = "live: skipped (set NOSTALGEX_JF_URL, NOSTALGEX_JF_APPROVER_TOKEN, NOSTALGEX_JF_USER)";
if (live.url && live.approver && live.user) {
  await check(`live: Quick Connect through AuthenticateWithQuickConnect on ${live.url}`, async () => {
    const log = [];
    const fetchLogged = async (url, init = {}) => {
      const res = await fetch(url, init);
      log.push(`${init.method || "GET"} ${new URL(url).pathname} ${res.status}`);
      return res;
    };
    const f = pageFixture({ fetch: fetchLogged, serverUrl: live.url, clientId: `nostalgex-qc-live-${Date.now()}` });
    await f.context.jellyfinQuickConnect();
    assert.equal(f.shownError(), null, `error: ${f.shownError()}`);
    const code = f.el("connect-jf-code").textContent;
    assert.match(code, /^\d{6}$/);
    await f.tick();
    assert.equal(f.saved(), null, "not signed in before approval");
    const approve = await fetch(`${live.url}/QuickConnect/Authorize?code=${encodeURIComponent(code)}&userId=${encodeURIComponent(live.user)}`, {
      method: "POST",
      headers: { Authorization: `MediaBrowser Client="Nostalgex", Device="Smoke", DeviceId="nostalgex-qc-approver", Version="1.0", Token="${live.approver}"` },
    });
    log.push(`POST /QuickConnect/Authorize ${approve.status} (approver)`);
    assert.equal(approve.status, 200);
    for (let i = 0; i < 10 && !f.saved(); i++) {
      await f.tick();
      if (!f.saved()) await new Promise((r) => setTimeout(r, 300));
    }
    const saved = f.saved();
    assert(saved, "signed in");
    assert.equal(saved.backend, "jellyfin");
    assert.equal(saved.jellyfinUserId, live.user);
    assert.equal(f.context.location.href, "plex-tuner.html");
    const views = await fetch(`${live.url}/UserViews?userId=${encodeURIComponent(saved.jellyfinUserId)}`, {
      headers: { Accept: "application/json", Authorization: f.context.jellyfinAuthHeader(saved.token) },
    });
    const libraries = views.ok ? ((await views.json()).Items || []).length : -1;
    assert.equal(views.status, 200);
    liveSummary = `live: ${log.join(" | ")} | saved backend=${saved.backend} token length ${saved.token.length}`
      + ` user matches ${saved.jellyfinUserId === live.user} | GET /UserViews with the new token ${views.status}, ${libraries} libraries`;
  });
}

if (failures.length) {
  console.error(`jellyfin-quick-connect: ${failures.length} failed, ${passed} passed`);
  for (const f of failures) console.error("  " + f);
  process.exit(1);
}
console.log(`jellyfin-quick-connect: ${passed} passed`);
console.log(liveSummary);
