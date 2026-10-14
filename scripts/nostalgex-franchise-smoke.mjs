#!/usr/bin/env node
/**
 * Golden-vector test for scripts/nostalgex-franchise-builder.js.
 *
 * Reads scripts/franchise-golden.json and franchises.json, the same two files
 * Nostalgex/NostalgexTests/FranchiseGoldenTests.swift reads. Both must pass, so the
 * web tuner and the Apple TV app build the same franchise channels from the same
 * library.
 *
 * Run: `npm run test:franchises`
 */
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { deepStrictEqual } from "node:assert/strict";
import "./nostalgex-franchise-builder.js";

const FB = globalThis.NostalgexFranchiseBuilder;
const here = dirname(fileURLToPath(import.meta.url));
const golden = JSON.parse(readFileSync(resolve(here, "franchise-golden.json"), "utf8"));
const dictionary = JSON.parse(readFileSync(resolve(here, "..", "franchises.json"), "utf8"));

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

/** The comparable shape: item objects reduced to their ids. */
function project(groupings) {
  return groupings.map((g) => ({
    name: g.name,
    stableID: g.stableID,
    placement: g.placement,
    movies: g.movies.map((m) => m.id),
    tvItems: g.tvItems.map((t) => t.id),
    mergedFranchiseIDs: g.mergedFranchiseIDs,
    fromDictionary: g.fromDictionary,
  }));
}

// The dictionary file itself.
check("franchises.json: 19 definitions, unique names, ids verified header", () => {
  const defs = FB.normalizeDefinitions(dictionary);
  deepStrictEqual(defs.length, 19);
  deepStrictEqual(new Set(defs.map((d) => d.canonicalName)).size, 19);
  deepStrictEqual(dictionary.verified, "2026-10-11");
  const ids = defs.flatMap((d) => d.tmdbCollectionIDs);
  deepStrictEqual(new Set(ids).size, ids.length, "a collection id is claimed by two franchises");
  deepStrictEqual([...FB.defaultOnIDs(dictionary)].sort(), ["dict:FAST & FURIOUS", "dict:STAR TREK"]);
});

for (const c of golden.cases) {
  check(`case ${c.name}`, () => {
    const actual = FB.build({
      movies: c.movies,
      tvItems: c.tvItems,
      definitions: c.definitions ?? dictionary,
      availableStockChannelIDs: c.availableStockChannelIDs,
      minimumFilms: c.minimumFilms,
    });
    deepStrictEqual(project(actual), c.expected);
  });
}

for (const v of golden.titleKeys) {
  check(`titleKey ${JSON.stringify(v.title)}`, () => deepStrictEqual(FB.explicitTitleKey(v.title), v.key));
}

for (const v of golden.filmMatches) {
  check(`filmMatch ${JSON.stringify(v.title)}`, () => {
    const def = FB.dictionaryMatchForFilmTitle(v.title, dictionary);
    deepStrictEqual(def ? def.canonicalName : null, v.franchise);
  });
}

for (const v of golden.mergeKeys) {
  check(`mergeKey ${JSON.stringify(v.name)}`, () => deepStrictEqual(FB.franchiseMergeKey(v.name), v.key));
}

for (const v of golden.collectionFolds) {
  check(`collectionFold ${v.about}`, () => {
    const got = FB.stockChannelForCollectionItems({
      items: v.items,
      definitions: dictionary,
      availableStockChannelIDs: v.availableStockChannelIDs,
    });
    deepStrictEqual(got, v.stockChannelID);
  });
}

const total = passed + failures.length;
if (failures.length) {
  console.error(`franchise golden: ${failures.length} of ${total} FAILED`);
  for (const f of failures) console.error(`  x ${f}`);
  process.exit(1);
}
console.log(
  `franchise golden: ${total} checks passed (${golden.cases.length} cases, ${golden.titleKeys.length} title keys, ` +
    `${golden.filmMatches.length} film matches, ${golden.mergeKeys.length} merge keys, ${golden.collectionFolds.length} collection folds)`
);
