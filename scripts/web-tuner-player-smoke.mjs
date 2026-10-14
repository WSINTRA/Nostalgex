// Guards the web tuner's player against the iPhone playback regression.
//
// On iPhone a <video> without `playsinline` is not allowed to run inline at all:
// iOS hands playback to the native fullscreen player, and pauses the element on
// the way out. Measured 2026-10-13 against the built tuner under a WebKit shim of
// Apple's rules: every play() the schedule made was refused (NotAllowedError), the
// element sat loaded and paused on a still frame, and nothing ever retried. These
// are source assertions, so the attributes and the recovery paths cannot quietly
// disappear again.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const tuner = fs.readFileSync(path.join(root, 'plex-tuner.html'), 'utf8');

let failed = 0;
function check(name, ok, detail) {
  if (ok) { console.log(`  ok   ${name}`); return; }
  failed++;
  console.log(`  FAIL ${name}${detail ? `\n       ${detail}` : ''}`);
}

console.log('web tuner player smoke');

// 1. The video element itself.
const videoTag = /<video\s+id="plex-video"[^>]*>/.exec(tuner);
check('the player video element exists', !!videoTag);
if (videoTag) {
  const tag = videoTag[0];
  check('video carries playsinline', /\bplaysinline\b/.test(tag), tag);
  check('video carries webkit-playsinline', /\bwebkit-playsinline\b/.test(tag), tag);
  check('video stays muted so autoplay is allowed', /\bmuted\b/.test(tag), tag);
  check('video has no controls attribute', !/\bcontrols\b/.test(tag), tag);
}

// 2. Every play() the schedule makes goes through the helper that retries on the
//    next gesture, rather than logging a rejection and leaving a frozen frame.
check('a refused play() is retried on the next gesture',
  /function startVideoPlayback\(/.test(tuner) && /function armPlayRetry\(/.test(tuner));
const barePlays = [...tuner.matchAll(/video\.play\(\)/g)].length;
const helperPlays = [...tuner.matchAll(/startVideoPlayback\(video\)/g)].length;
check('the schedule starts playback through startVideoPlayback',
  helperPlays >= 3, `startVideoPlayback call sites: ${helperPlays}`);
check('no play() site logs the rejection and gives up',
  !/play\(\)\.catch\(e => console\.warn\('Autoplay blocked/.test(tuner),
  `bare video.play() occurrences: ${barePlays}`);

// 3. Leaving the iOS native player must put playback back inline.
check('webkitendfullscreen resumes inline playback',
  /addEventListener\('webkitendfullscreen'/.test(tuner)
  && /webkitendfullscreen'[\s\S]{0,400}startVideoPlayback\(video\)/.test(tuner));

// 4. iPhone has no element fullscreen API, so the tuner's own control must
//    feature-detect instead of throwing a TypeError on every tap.
check('toggleFullscreen feature-detects requestFullscreen',
  /if \(container\.requestFullscreen\)/.test(tuner));
check('toggleFullscreen falls back to webkitEnterFullscreen',
  /video\.webkitEnterFullscreen\(\)/.test(tuner));
check('the G-key overlay guards requestFullscreen',
  /document\.documentElement\.requestFullscreen &&/.test(tuner)
  || /documentElement\.requestFullscreen\)\s*\{/.test(tuner));

if (failed) {
  console.error(`\nweb tuner player smoke: ${failed} failed`);
  process.exit(1);
}
console.log('web tuner player smoke: all passed');
