#!/usr/bin/env node
/**
 * The web tuner's version line (bottom of Settings). Four parts, and a fifth with
 * --builds:
 *
 *   1. scripts/tuner-version.mjs: package.json "tunerVersion" is a release number,
 *      NOSTALGEX_TUNER_VERSION overrides it, and the meta tag goes on the two tuner
 *      pages only.
 *   2. plex-tuner.html's own "Web tuner version" section, run in a VM against a fake
 *      DOM and fetch: nostalgex.app shows WEB TUNER 1.0.3, Docker shows the
 *      container's config.json value with "· DOCKER", and dev, empty, a placeholder
 *      or a missing file show nothing. Negative controls break the section in memory.
 *   3. The Settings markup: the line sits after the footer, hidden until filled in.
 *   4. docker/40-config.sh under sh, with its two paths pointed at a temp dir: the
 *      environment wins, else the version the build wrote, else an empty string.
 *   5. --builds (after `npm run build` and `npm run build:selfhost`): dist/ and
 *      dist-selfhost/ carry the version in the tuner pages and config.json.
 *
 * Run: `npm run test:tuner-version`, and `npm run test:tuner-version:builds` after
 * both builds.
 */
import { readFileSync, writeFileSync, mkdtempSync, mkdirSync, existsSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";
import vm from "node:vm";
import assert from "node:assert/strict";
import {
  RELEASE_VERSION, committedTunerVersion, resolveTunerVersion, addTunerVersionMeta,
} from "./tuner-version.mjs";

const ROOT = fileURLToPath(new URL("..", import.meta.url));
const BUILDS = process.argv.includes("--builds");

let passed = 0;
const failures = [];
async function check(label, fn) {
  try { await fn(); passed += 1; } catch (e) { failures.push(`${label}: ${e.stack || e.message}`); }
}

// ── 1. scripts/tuner-version.mjs ───────────────────────────────────────────

const committed = committedTunerVersion(ROOT);
await check("package.json tunerVersion is a release number", () => assert.match(committed, RELEASE_VERSION));
await check("no env: package.json", () => assert.equal(resolveTunerVersion({}, ROOT), committed));
await check("empty env: package.json", () => assert.equal(resolveTunerVersion({ NOSTALGEX_TUNER_VERSION: "" }, ROOT), committed));
await check("blank env: package.json", () => assert.equal(resolveTunerVersion({ NOSTALGEX_TUNER_VERSION: "  " }, ROOT), committed));
await check("env wins", () => assert.equal(resolveTunerVersion({ NOSTALGEX_TUNER_VERSION: "1.0.9" }, ROOT), "1.0.9"));
await check("env prerelease", () => assert.equal(resolveTunerVersion({ NOSTALGEX_TUNER_VERSION: "1.1.0-rc1" }, ROOT), "1.1.0-rc1"));
for (const bad of ['1.0.3"><script>', "1.0 3", "1.0.3/x"]) {
  await check(`env ${JSON.stringify(bad)} fails the build`, () => assert.throws(() => resolveTunerVersion({ NOSTALGEX_TUNER_VERSION: bad }, ROOT)));
}
for (const [v, ok] of [["1.0.3", true], ["10.20.30", true], ["1.0.3-rc1", true], ["1.0.3-rc.1", true], ["dev", false], ["", false], ["1.0", false], ["v1.0.3", false], ["1.0.3 ", false]]) {
  await check(`RELEASE_VERSION ${JSON.stringify(v)}`, () => assert.equal(RELEASE_VERSION.test(v), ok));
}
{
  const page = '<!DOCTYPE html>\n<html>\n<head>\n<meta charset="UTF-8">\n<title>x</title>';
  await check("meta on plex-tuner.html", () => assert.equal(
    addTunerVersionMeta(page, "1.0.3", "/x/plex-tuner.html"),
    '<!DOCTYPE html>\n<html>\n<head>\n<meta charset="UTF-8">\n<meta name="nostalgex-tuner-version" content="1.0.3">\n<title>x</title>',
  ));
  await check("meta on web-tuner.html", () => assert.match(addTunerVersionMeta(page, "1.0.3", "web-tuner.html"), /name="nostalgex-tuner-version" content="1.0.3"/));
  await check("no meta on index.html", () => assert.equal(addTunerVersionMeta(page, "1.0.3", "/x/index.html"), page));
  await check("a tuner page without <meta charset> fails the build", () => assert.throws(() => addTunerVersionMeta("<head></head>", "1.0.3", "plex-tuner.html")));
}

// ── 2. The page's own section, against a fake DOM ──────────────────────────

const tuner = readFileSync(new URL("../plex-tuner.html", import.meta.url), "utf8");
const START = "  // ── Web tuner version (bottom of Settings)";
const CALL = "  loadTunerVersion();\n";
function section(src = tuner) {
  const a = src.indexOf(START);
  const b = src.indexOf(CALL, a);
  if (a < 0 || b < 0) throw new Error("plex-tuner.html: the web tuner version section moved; update this test");
  return src.slice(a, b + CALL.length);
}

/**
 * Run the section once. `meta` is the page's meta tags by name, `config` what
 * config.json answers: an object (200), a number (that status), or an Error (thrown).
 */
async function render({ meta = {}, config, src } = {}) {
  const el = { textContent: "", hidden: true };
  const fetches = [];
  const document = {
    getElementById: (id) => (id === "cfg-tuner-version" ? el : null),
    querySelector: (sel) => {
      const m = /^meta\[name="([^"]+)"\]$/.exec(sel);
      if (!m) throw new Error(`unexpected selector ${sel}`);
      return m[1] in meta ? { getAttribute: (a) => (a === "content" ? meta[m[1]] : null) } : null;
    },
  };
  const fetch = async (url, opts) => {
    fetches.push({ url, opts });
    if (config instanceof Error) throw config;
    if (config === undefined) return { ok: false, status: 404, json: async () => { throw new Error("404"); } };
    if (typeof config === "number") return { ok: config >= 200 && config < 300, status: config, json: async () => ({}) };
    return { ok: true, status: 200, json: async () => config };
  };
  const ctx = vm.createContext({ document, fetch, console });
  const code = section(src).replace(CALL, "  globalThis.__done = loadTunerVersion();\n");
  vm.runInContext(code, ctx);
  await ctx.__done;
  return { text: el.textContent, hidden: el.hidden, fetches };
}

await check("the page calls loadTunerVersion() at load", () => assert.ok(section().endsWith(CALL)));

const HOSTED = { "nostalgex-tuner-version": "1.0.3" };
const DOCKER = { "nostalgex-build": "selfhost", "nostalgex-tuner-version": "1.0.3" };
const cases = [
  // name, meta, config.json, expected line ("" = hidden)
  ["nostalgex.app", HOSTED, undefined, "WEB TUNER 1.0.3"],
  ["nostalgex.app ignores config.json", HOSTED, { tunerVersion: "9.9.9" }, "WEB TUNER 1.0.3"],
  ["Docker: the container's value", DOCKER, { tunerVersion: "1.0.9", enrichment: true }, "WEB TUNER 1.0.9 · DOCKER"],
  ["Docker: same as the build", DOCKER, { tunerVersion: "1.0.3" }, "WEB TUNER 1.0.3 · DOCKER"],
  ["Docker: prerelease", DOCKER, { tunerVersion: "1.1.0-rc1" }, "WEB TUNER 1.1.0-rc1 · DOCKER"],
  ["Docker: empty value, the build's", DOCKER, { tunerVersion: "" }, "WEB TUNER 1.0.3 · DOCKER"],
  ["Docker: dev, the build's", DOCKER, { tunerVersion: "dev" }, "WEB TUNER 1.0.3 · DOCKER"],
  ["Docker: no config.json, the build's", DOCKER, undefined, "WEB TUNER 1.0.3 · DOCKER"],
  ["Docker: config.json throws, the build's", DOCKER, new Error("offline"), "WEB TUNER 1.0.3 · DOCKER"],
  ["Docker: config.json is null", DOCKER, null, "WEB TUNER 1.0.3 · DOCKER"],
  ["Docker: neither has one", { "nostalgex-build": "selfhost" }, { tunerVersion: "" }, ""],
  ["Docker: dev and no meta", { "nostalgex-build": "selfhost" }, { tunerVersion: "dev" }, ""],
  ["Docker: no file and no meta", { "nostalgex-build": "selfhost" }, undefined, ""],
  ["no meta", {}, undefined, ""],
  ["meta dev", { "nostalgex-tuner-version": "dev" }, undefined, ""],
  ["meta empty", { "nostalgex-tuner-version": "" }, undefined, ""],
  ["meta undefined", { "nostalgex-tuner-version": "undefined" }, undefined, ""],
  ["meta placeholder", { "nostalgex-tuner-version": "%NOSTALGEX_TUNER_VERSION%" }, undefined, ""],
  ["meta markup", { "nostalgex-tuner-version": "<b>1.0.3</b>" }, undefined, ""],
  ["Docker: a number, not a string", { "nostalgex-build": "selfhost" }, { tunerVersion: 103 }, ""],
];
for (const [name, meta, config, want] of cases) {
  await check(`page: ${name}`, async () => {
    const r = await render({ meta, config });
    assert.equal(r.text, want);
    assert.equal(r.hidden, want === "");
  });
}
await check("nostalgex.app makes no request", async () => assert.deepEqual((await render({ meta: HOSTED })).fetches, []));
await check("Docker asks config.json, uncached, relative", async () => {
  const r = await render({ meta: DOCKER, config: { tunerVersion: "1.0.3" } });
  assert.deepEqual(r.fetches.map((f) => [f.url, f.opts && f.opts.cache]), [["config.json", "no-store"]]);
});

// Negative controls: break the section in memory and the matching check must fail.
async function mustFail(label, broken, meta, config, want) {
  await check(`negative control: ${label}`, async () => {
    assert.notEqual(broken, section(), "the edit did not apply");
    const r = await render({ meta, config, src: broken });
    assert.notEqual(r.text, want, "the broken section still passed");
  });
}
const sec = section();
await mustFail("no validation shows dev",
  tuner.replace(sec, () => sec.replace("return v.length <= 40 && TUNER_RELEASE_VERSION.test(v) ? v : '';", "return v;")),
  { "nostalgex-tuner-version": "dev" }, undefined, "");
await mustFail("ignoring config.json shows the build's",
  tuner.replace(sec, () => sec.replace("if (docker) {", "if (false) {")),
  DOCKER, { tunerVersion: "1.0.9" }, "WEB TUNER 1.0.9 · DOCKER");
await mustFail("no DOCKER suffix",
  tuner.replace(sec, () => sec.replace("' \\u00b7 DOCKER'", "''")),
  DOCKER, { tunerVersion: "1.0.9" }, "WEB TUNER 1.0.9 · DOCKER");

// ── 3. The Settings markup ─────────────────────────────────────────────────

await check("the line is after the footer, inside the panel, hidden until filled", () => {
  const footer = tuner.indexOf('<div class="config-footer">');
  const line = tuner.indexOf('<div class="config-version" id="cfg-tuner-version" hidden></div>');
  const overlayEnd = tuner.indexOf("<!-- Key hints", footer);
  assert.ok(footer > 0 && line > footer && line < overlayEnd);
});

// ── 4. docker/40-config.sh ─────────────────────────────────────────────────

const script = readFileSync(new URL("../docker/40-config.sh", import.meta.url), "utf8");
await check("40-config.sh still reads and writes the paths this test rewrites", () => {
  assert.ok(script.includes("/usr/share/nginx/html/config.json"));
  assert.ok(script.includes("/tmp/nostalgex"));
});
function runConfig({ env = {}, built }) {
  const dir = mkdtempSync(join(tmpdir(), "nx-tunerver-"));
  try {
    mkdirSync(join(dir, "html"));
    if (built !== undefined) writeFileSync(join(dir, "html", "config.json"), built);
    const sh = script
      .split("/usr/share/nginx/html/config.json").join(join(dir, "html", "config.json"))
      .split("/tmp/nostalgex").join(join(dir, "out"));
    writeFileSync(join(dir, "40-config.sh"), sh);
    const clean = { PATH: process.env.PATH, ...env };
    const log = execFileSync("sh", [join(dir, "40-config.sh")], { env: clean, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
    return { conf: JSON.parse(readFileSync(join(dir, "out", "config.json"), "utf8")), log };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}
// What scripts/selfhost-build.mjs writes.
const BUILT = JSON.stringify({ tunerVersion: "1.0.3", musicLookups: false, enrichment: true }, null, 2) + "\n";
const shCases = [
  ["env wins over the build", { NOSTALGEX_TUNER_VERSION: "1.0.9" }, BUILT, "1.0.9"],
  ["empty env (a local docker build): the build's", { NOSTALGEX_TUNER_VERSION: "" }, BUILT, "1.0.3"],
  ["unset env: the build's", {}, BUILT, "1.0.3"],
  ["unsafe env: the build's", { NOSTALGEX_TUNER_VERSION: '1.0.3","enrichment":true' }, BUILT, "1.0.3"],
  ["one-line built file", {}, '{"tunerVersion":"1.0.4","enrichment":true}\n', "1.0.4"],
  ["no built file, no env", {}, undefined, ""],
  ["built file without a version", {}, '{"enrichment":true}\n', ""],
];
for (const [name, env, built, want] of shCases) {
  await check(`40-config.sh: ${name}`, () => {
    const { conf, log } = runConfig({ env, built });
    assert.equal(conf.tunerVersion, want);
    assert.equal(conf.enrichment, true);
    assert.equal(conf.musicLookups, false);
    assert.match(log, want ? new RegExp(`Nostalgex tuner ${want.replace(/\./g, "\\.")},`) : /Nostalgex tuner \(no version\),/);
  });
}
await check("40-config.sh: enrichment off is unchanged", () => {
  const { conf } = runConfig({ env: { NOSTALGEX_ENRICHMENT: "off", NOSTALGEX_TUNER_VERSION: "1.0.3" }, built: BUILT });
  assert.deepEqual(conf, { tunerVersion: "1.0.3", musicLookups: false, enrichment: false });
});
await check("40-config.sh output feeds the page", async () => {
  const { conf } = runConfig({ env: { NOSTALGEX_TUNER_VERSION: "1.0.9" }, built: BUILT });
  assert.equal((await render({ meta: DOCKER, config: conf })).text, "WEB TUNER 1.0.9 · DOCKER");
});

// ── 5. --builds: dist/ and dist-selfhost/ ──────────────────────────────────

let builtChecks = 0;
if (BUILDS) {
  const want = resolveTunerVersion(process.env, ROOT);
  const metaOf = (html) => (/<meta name="nostalgex-tuner-version" content="([^"]*)">/.exec(html) || [])[1];
  const read = (p) => {
    const f = join(ROOT, p);
    if (!existsSync(f)) throw new Error(`${p} is missing. Run npm run build and npm run build:selfhost first.`);
    return readFileSync(f, "utf8");
  };
  const before = passed;
  for (const page of ["dist/plex-tuner.html", "dist/web-tuner.html", "dist-selfhost/plex-tuner.html", "dist-selfhost/web-tuner.html", "dist-selfhost/index.html"]) {
    await check(`${page} carries ${want}`, () => assert.equal(metaOf(read(page)), want));
  }
  for (const page of ["dist/index.html", "dist/apple-tv.html"]) {
    await check(`${page} has no tuner version`, () => assert.equal(metaOf(read(page)), undefined));
  }
  await check(`dist-selfhost/config.json carries ${want}`, () => assert.equal(JSON.parse(read("dist-selfhost/config.json")).tunerVersion, want));
  await check("both built tuners keep the version line and its loader", () => {
    for (const page of ["dist/plex-tuner.html", "dist-selfhost/plex-tuner.html"]) {
      const html = read(page);
      assert.ok(html.includes('id="cfg-tuner-version"'), `${page}: no version line`);
      assert.ok(html.includes("loadTunerVersion();"), `${page}: no loader`);
    }
  });
  await check("the built pages render the line", async () => {
    const hosted = await render({ meta: { "nostalgex-tuner-version": metaOf(read("dist/plex-tuner.html")) } });
    const docker = await render({
      meta: { "nostalgex-build": "selfhost", "nostalgex-tuner-version": metaOf(read("dist-selfhost/plex-tuner.html")) },
      config: JSON.parse(read("dist-selfhost/config.json")),
    });
    const expect = RELEASE_VERSION.test(want);
    assert.equal(hosted.text, expect ? `WEB TUNER ${want}` : "");
    assert.equal(docker.text, expect ? `WEB TUNER ${want} · DOCKER` : "");
  });
  builtChecks = passed - before;
}

if (failures.length) {
  console.error(`tuner version: ${failures.length} failed, ${passed} passed`);
  for (const f of failures) console.error(`  FAIL ${f}`);
  process.exit(1);
}
console.log(`tuner version: ${passed} checks passed${BUILDS ? ` (${builtChecks} on the builds)` : ""}, tunerVersion ${committed}`);
