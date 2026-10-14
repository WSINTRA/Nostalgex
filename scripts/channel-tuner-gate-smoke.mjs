#!/usr/bin/env node
/**
 * Smoke test for the membership generator's genre gate
 * (scripts/channel-keyword-tuner/genre-gate.mjs), built from the real rule data
 * in channels.json and exemplars.json. Locks in the 2026-10-12 cleanup so a
 * regeneration can't quietly undo it:
 *   - MUSICALS keeps off-genre titles tagged musical / song and dance / broadway,
 *     but not "based on play or musical" (plays) and not "singing".
 *   - SCI-FI applies genres.requireAll Science Fiction, so horror-only titles
 *     stay off even though Horror is in its include list.
 *   - ROM COMS and GIRLS NIGHT do not apply requireAll to claims (owner's call).
 * Fixture genres and keywords are TMDB's as of 2026-10-13. No network.
 * Run: `npm run test:tuner-gate`.
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { channelRuleGate, ruleGateDecision } from "./channel-keyword-tuner/genre-gate.mjs";

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const channels = JSON.parse(fs.readFileSync(path.join(root, "channels.json"), "utf8")).channels;
const exemplars = JSON.parse(
  fs.readFileSync(path.join(root, "scripts/channel-keyword-tuner/exemplars.json"), "utf8"),
).channels;

let pass = 0;
const failures = [];
function check(name, actual, expected) {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a === e) pass++;
  else failures.push(`${name}: expected ${e}, got ${a}`);
}

function gateFor(name) {
  const ch = channels.find((c) => c.name === name);
  if (!ch) throw new Error(`channels.json has no ${name}`);
  return channelRuleGate(ch.rules, exemplars.find((e) => e.id === ch.id) || {});
}
// "kept", "kept:<keyword>" when a rescue keyword saved it, or "dropped".
function verdict(gate, genres, keywords = []) {
  const d = ruleGateDecision({ genres, keywords }, gate);
  if (d.reason) return "dropped";
  return d.rescuedBy ? `kept:${d.rescuedBy}` : "kept";
}

// ---- The gates the rule data produces ----
const musicals = gateFor("MUSICALS");
const scifi = gateFor("SCI-FI");
const romcoms = gateFor("ROM COMS");
const girls = gateFor("GIRLS NIGHT");
check("MUSICALS rescue keywords", musicals.rescueKeywords, ["musical", "song and dance", "broadway"]);
check("MUSICALS has no requireAll", musicals.requireAll, []);
check("SCI-FI requireAll", scifi.requireAll, ["science fiction"]);
check("ROM COMS requireAll off", romcoms.requireAll, []);
check("GIRLS NIGHT requireAll off", girls.requireAll, []);
check("TRUE CRIME requireAll stays on", gateFor("TRUE CRIME").requireAll, ["documentary"]);

// ---- MUSICALS: keyword rescue ----
check("Mother India (Drama, musical)", verdict(musicals, ["Drama"], ["musical"]), "kept:musical");
check("Wicked (Drama/Romance/Fantasy)", verdict(musicals, ["Drama", "Romance", "Fantasy"],
  ["musical", "based on play or musical", "singing", "musical comedy"]), "kept:musical");
check("song and dance rescues", verdict(musicals, ["Comedy"], ["song and dance"]), "kept:song and dance");
check("broadway rescues", verdict(musicals, ["Drama"], ["Broadway"]), "kept:broadway");
check("Roxanne (play, not a musical)", verdict(musicals, ["Comedy", "Romance"], ["based on play or musical"]), "dropped");
check("singing alone does not rescue", verdict(musicals, ["Animation", "Drama"], ["singing"]), "dropped");
check("Music genre passes on its own", verdict(musicals, ["Music", "Drama"]), "kept");
check("off-genre, no keyword", verdict(musicals, ["Action", "Drama", "History"]), "dropped");

// ---- SCI-FI: requireAll Science Fiction ----
check("Hellraiser III (Horror/Thriller)", verdict(scifi, ["Horror", "Thriller"]), "dropped");
check("Stake Land: Origins (Horror)", verdict(scifi, ["Horror"]), "dropped");
check("Science Fiction + Horror", verdict(scifi, ["Horror", "Science Fiction"]), "kept");
check("TV Sci-Fi & Fantasy counts", verdict(scifi, ["Sci-Fi & Fantasy", "Drama"]), "kept");
check("requireAll reason names the genre",
  ruleGateDecision({ genres: ["Horror"] }, scifi).reason, "genres Horror lack required science fiction");

// ---- ROM COMS / GIRLS NIGHT: requireAll not applied to claims ----
check("Hairspray stays on ROM COMS", verdict(romcoms, ["Comedy"], ["woman played by man"]), "kept");
check("Sleepers stays on GIRLS NIGHT", verdict(girls, ["Crime", "Drama", "Thriller"]), "kept");
const romcomRules = channels.find((c) => c.name === "ROM COMS").rules;
check("without the opt-out ROM COMS would drop it",
  verdict(channelRuleGate(romcomRules, {}), ["Comedy"]), "dropped");

// ---- A rescue keyword never overrides requireAll ----
const strict = { includes: ["music"], requireAll: ["science fiction"], rescueKeywords: ["musical"] };
check("rescue cannot beat requireAll", verdict(strict, ["Drama"], ["musical"]), "dropped");
check("requireAll met, rescue still works", verdict(strict, ["Science Fiction"], ["musical"]), "kept:musical");

if (failures.length) {
  console.error(`channel tuner gate smoke: ${failures.length} failed, ${pass} passed`);
  for (const f of failures) console.error(`  FAIL ${f}`);
  process.exit(1);
}
console.log(`channel tuner gate smoke: ${pass} passed`);
