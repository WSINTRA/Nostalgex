#!/usr/bin/env node
/**
 * Seasonal bundles build in every month on the web tuner and in the Docker image.
 *
 * Apple TV stopped gating a switched-on seasonal bundle by month in 1.0.26
 * (AppState+Channels.swift `staticChannelIDsForPoolBuild`). The web port kept the
 * gate, so a returning visitor with SCREAM on got 0 of its channels built in any
 * month but October (TIS THE SEASON: 0 outside December). `activeMonths` now only
 * decides the invite and the guide lead, never whether pools are built.
 *
 * Runs the production scripts/nostalgex-library-load.js against the shipped
 * channels.json, plus the real `isBundleInSeason` from plex-tuner.html (which hands
 * off to scripts/nostalgex-season.js) under a fixed clock for each month. The season
 * itself, `seasonStart` included, is `npm run test:season`. No network.
 * Run: `npm run test:library-load`.
 */
import { readFileSync } from "node:fs";
import vm from "node:vm";
import assert from "node:assert/strict";

const root = new URL("../", import.meta.url);
const loaderSrc = readFileSync(new URL("scripts/nostalgex-library-load.js", root), "utf8");
const seasonSrc = readFileSync(new URL("scripts/nostalgex-season.js", root), "utf8");
const tuner = readFileSync(new URL("plex-tuner.html", root), "utf8");
const config = JSON.parse(readFileSync(new URL("channels.json", root), "utf8"));

let passed = 0;
const failures = [];
function check(label, fn) {
  try {
    fn();
    passed += 1;
  } catch (err) {
    failures.push(`${label}\n    ${String(err.message).split("\n").join("\n    ")}`);
  }
}

const sandbox = { localStorage: { getItem: () => "1", setItem() {} }, document: { getElementById: () => null } };
sandbox.globalThis = sandbox;
vm.createContext(sandbox);
vm.runInContext(loaderSrc, sandbox);
const LL = sandbox.NostalgexLibraryLoad;

/** plex-tuner.html's own isBundleInSeason, run with the clock pinned to a month. */
function isBundleInSeasonAt(month) {
  const start = tuner.indexOf("function isBundleInSeason(bundle)");
  const end = tuner.indexOf("\n  }\n", start);
  assert(start >= 0 && end > start, "isBundleInSeason not found in plex-tuner.html");
  const src = tuner.slice(start, end + 4);
  const RealDate = Date;
  class FixedDate extends RealDate {
    constructor(...args) {
      super(...(args.length ? args : [2026, month - 1, 15, 20, 0, 0]));
    }
  }
  const ctx = { Date: FixedDate };
  ctx.globalThis = ctx;
  vm.createContext(ctx);
  vm.runInContext(seasonSrc, ctx);
  vm.runInContext(`${src}\nthis.fn = isBundleInSeason;`, ctx);
  return ctx.fn;
}

const bundles = config.bundles.map((b) => ({ ...b, activeMonths: b.activeMonths || null }));
const channels = config.channels.map((c) => ({ id: c.id }));
const byID = new Map(bundles.map((b) => [b.id, b]));
const seasonal = bundles.filter((b) => b.activeMonths);

check("the shipped config still has seasonal bundles to test", () => {
  assert.deepEqual(seasonal.map((b) => b.id).sort(), ["seasonal", "tis-the-season"]);
});

// A returning visitor (not the first load) with NOSTALGEX, SCREAM and TIS THE SEASON on.
const enabled = new Set(["nostalgex", "seasonal", "tis-the-season"]);
for (const month of [1, 3, 7, 9, 10, 11, 12]) {
  check(`month ${month}: every channel of every enabled bundle is built`, () => {
    const isBundleInSeason = isBundleInSeasonAt(month);
    // Passing the season check the way the old callers did must not change anything.
    const ids = LL.staticChannelIDsForPoolBuild({
      buildAll: false,
      bundles,
      enabledBundleIDs: enabled,
      allChannelsUnfiltered: channels,
      isBundleInSeason,
    });
    for (const id of enabled) {
      const missing = byID.get(id).channelIDs.filter((ch) => !ids.has(ch));
      assert.deepEqual(missing, [], `${byID.get(id).name}: channels not built in month ${month}`);
    }
  });
}

check("a bundle that is switched off is not built on a returning visit", () => {
  const ids = LL.staticChannelIDsForPoolBuild({
    buildAll: false, bundles, enabledBundleIDs: new Set(["nostalgex"]), allChannelsUnfiltered: channels,
  });
  for (const b of seasonal) {
    assert.equal(b.channelIDs.some((ch) => ids.has(ch)), false, `${b.name} built while off`);
  }
});

check("the first load builds every channel", () => {
  const ids = LL.staticChannelIDsForPoolBuild({
    buildAll: true, bundles, enabledBundleIDs: new Set(["nostalgex"]), allChannelsUnfiltered: channels,
  });
  assert.equal(ids.size, channels.length);
});

check("activeMonths still drives the invite and the guide lead (isBundleInSeason)", () => {
  const scream = byID.get("seasonal");
  const holiday = byID.get("tis-the-season");
  assert.equal(isBundleInSeasonAt(10)(scream), true);
  assert.equal(isBundleInSeasonAt(11)(scream), false);
  assert.equal(isBundleInSeasonAt(12)(holiday), true);
  assert.equal(isBundleInSeasonAt(7)(holiday), false);
});

check("Settings row label: SPOTLIGHTED <month>, never OFF SEASON", () => {
  const ctx = { globalThis: null };
  ctx.globalThis = ctx;
  vm.createContext(ctx);
  vm.runInContext(seasonSrc, ctx);
  const label = (b) => ctx.NostalgexSeason.seasonalSpotlightLabel(b, new Date(2026, 6, 4, 12));
  assert.equal(label(byID.get("seasonal")), "SPOTLIGHTED OCT");
  assert.equal(label(byID.get("tis-the-season")), "SPOTLIGHTED NOV 19 TO DEC 31");
  assert.equal(label(byID.get("nostalgex")), "");
  assert.equal(label({ activeMonths: [11, 12] }), "SPOTLIGHTED NOV, DEC");
  assert.equal(tuner.includes("OFF SEASON"), false, "plex-tuner.html still prints OFF SEASON");
  assert.equal(tuner.includes("seasonalSpotlightLabel(bundle, new Date())"), true, "the bundle row does not use the label");
});

check("plex-tuner.html no longer hands the season check to the pool build", () => {
  const calls = [...tuner.matchAll(/LL\.staticChannelIDsForPoolBuild\(\{([\s\S]*?)\}\)/g)];
  assert.equal(calls.length, 2, "expected the two pool-build call sites");
  for (const c of calls) assert.equal(c[1].includes("isBundleInSeason"), false);
});

if (failures.length) {
  console.error(`library-load smoke: ${failures.length} failed, ${passed} passed`);
  for (const f of failures) console.error(`  FAIL ${f}`);
  process.exit(1);
}
console.log(`library-load smoke: ${passed} passed`);
