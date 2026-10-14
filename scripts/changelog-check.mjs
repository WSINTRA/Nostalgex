#!/usr/bin/env node
/**
 * Fails when the app's version has no changelog entry.
 *
 * Release notes are only a single source if something notices when they are missing.
 * Relying on whoever cuts the build to remember is how 1.0.23 shipped to TestFlight with
 * notes describing a different build.
 *
 * Runs as part of `npm test`.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const pbx = fs.readFileSync(path.join(ROOT, 'Nostalgex/Nostalgex.xcodeproj/project.pbxproj'), 'utf8');
const version = pbx.match(/MARKETING_VERSION = ([0-9.]+);/)?.[1];
if (!version) { console.error('changelog-check: could not read MARKETING_VERSION'); process.exit(1); }

const { entries } = JSON.parse(fs.readFileSync(path.join(ROOT, 'content/changelog.json'), 'utf8'));
const entry = entries.find(e => e.version === version);

if (!entry) {
  console.error(`changelog-check: the app is at ${version} but content/changelog.json has no entry for it.`);
  console.error(`  Newest entry is ${entries[0]?.version}. Add ${version} before shipping —`);
  console.error('  the website, Discord and the release email all read from that file.');
  process.exit(1);
}
if (!entry.title || !Array.isArray(entry.bullets) || entry.bullets.length === 0) {
  console.error(`changelog-check: the ${version} entry has no title or bullets.`);
  process.exit(1);
}
console.log(`changelog-check: ${version} — "${entry.title}", ${entry.bullets.length} bullets. OK`);
