#!/usr/bin/env node
/**
 * PLAYBACK INFORMATION model for the web tuner (scripts/nostalgex-playback-info.js), held to
 * the Apple TV app's NostalgexTests/PlaybackInformationTests.swift: the rows and their order,
 * Loading until the current attempt is ready, the late-callback guard on generation and
 * attempt, size bounds, and that nothing private can reach the panel through it.
 *
 * The same guard inside the tuner's real playback code (old programme's events, a replaced
 * attempt, the direct play retry) is in web-tune-ownership-smoke.mjs.
 *
 * Run: `npm run test:playback-info`
 */
import assert from "node:assert/strict";
import "./nostalgex-playback-info.js";

const PI = globalThis.NostalgexPlaybackInfo;
let passed = 0;
const failures = [];
function check(label, fn) {
  try { fn(); passed += 1; } catch (e) { failures.push(`${label}: ${e.stack || e.message}`); }
}
const info = (o = {}) => PI.create({ generation: 1, backend: "plex", qualityAtTune: "Server default", videoCodec: "hevc", audioCodec: "dts", ...o });
// Size defaults to 1920 x 1080 only when no size is passed at all, so an explicit
// undefined reaches the model as undefined.
const value = (i, id, ...size) => {
  const [w, h] = size.length ? size : [1920, 1080];
  return (i.rows(w, h).find((r) => r.id === id) || {}).value;
};

check("server stream: fields, order and the evidence note", () => {
  const i = info();
  const a = i.beginAttempt(1, "serverStream", "serverStreamSelected");
  assert.equal(i.markReady(1, a), true);
  assert.equal(value(i, "delivery"), "Server stream");
  assert.equal(value(i, "source"), "Video: HEVC · Audio: DTS");
  assert.equal(value(i, "reason"), "Server streaming was selected for this source.");
  assert.deepEqual(i.rows(1, 1).map((r) => r.id), ["backend", "delivery", "quality", "presentation", "source", "reason"]);
  assert.deepEqual(i.rows(1, 1).map((r) => r.label), ["BACKEND", "PLAYBACK", "QUALITY AT TUNE", "PLAYER SIZE", "SOURCE METADATA", "FALLBACK"]);
  assert.match(i.evidenceNote, /copy or convert/);
  assert.match(i.evidenceNote, /not a measured output/);
});
check("direct play shows Loading and Unknown size until its attempt is ready", () => {
  const i = info();
  const a = i.beginAttempt(1, "directPlay");
  assert.equal(value(i, "delivery"), "Loading");
  assert.equal(value(i, "presentation"), "Unknown");
  assert.equal(value(i, "reason"), "No fallback used.");
  assert.equal(i.markReady(1, a), true);
  assert.equal(value(i, "delivery"), "Direct Play");
  assert.equal(value(i, "presentation"), "1920 × 1080");
});
check("late callback: a replaced attempt cannot mark the replacement ready", () => {
  const i = info();
  const first = i.beginAttempt(1, "directPlay");
  const replacement = i.beginAttempt(1, "serverStream", "directPlayFailed");
  assert.equal(i.markReady(1, first), false);
  assert.equal(i.isReady, false);
  assert.equal(value(i, "delivery"), "Loading");
  assert.equal(value(i, "reason"), "Direct Play failed. Trying a server stream.");
  assert.equal(i.markReady(1, replacement), true);
  assert.equal(value(i, "delivery"), "Server stream");
});
check("late callback: a superseded generation cannot touch the new programme", () => {
  const i = info({ generation: 2, videoCodec: "h264", audioCodec: "aac" });
  assert.equal(i.beginAttempt(1, "directPlay", "playerRetry"), null);
  assert.equal(i.markReady(1, 12345), false);
  assert.equal(i.attemptId, null);
  assert.equal(value(i, "delivery"), "Loading");
  assert.equal(value(i, "reason"), "No fallback used.");
  assert.equal(value(i, "source"), "Video: H.264 · Audio: AAC");
});
check("late callback: an attempt id from another programme is refused", () => {
  const a = info({ generation: 1 }); const b = info({ generation: 2 });
  const fromA = a.beginAttempt(1, "directPlay");
  b.beginAttempt(2, "serverStream");
  assert.equal(b.markReady(2, fromA), false);
  assert.equal(b.isReady, false);
});
check("retiring an attempt drops readiness until its replacement is ready", () => {
  const i = info();
  const old = i.beginAttempt(1, "serverStream", "serverStreamSelected");
  assert.equal(i.markReady(1, old), true);
  i.invalidateAttempt();
  assert.equal(i.attemptId, null);
  assert.equal(i.markReady(1, old), false);
  assert.equal(value(i, "delivery"), "Loading");
  assert.equal(value(i, "presentation"), "Unknown");
  const retry = i.beginAttempt(1, "serverStream", "playerRetry");
  assert.equal(i.markReady(1, retry), true);
  assert.equal(value(i, "reason"), "The player could not open the stream. Retrying it once.");
});
check("recovery request row appears only when one was made, and stays", () => {
  const i = info();
  i.beginAttempt(1, "serverStream", "startupNoPicture", "compatibility1080p");
  assert.equal(value(i, "recovery"), "Compatibility retry, up to 1080p");
  assert.deepEqual(i.rows().map((r) => r.id), ["backend", "delivery", "quality", "recovery", "presentation", "source", "reason"]);
  i.beginAttempt(1, "serverStream", "playerRetry");
  assert.equal(value(i, "recovery"), "Compatibility retry, up to 1080p");
  assert.equal(value(info(), "recovery"), undefined);
});
check("player size outside sane bounds is Unknown", () => {
  const i = info();
  i.markReady(1, i.beginAttempt(1, "serverStream"));
  for (const w of [NaN, Infinity, -1, 0, 65537, undefined, null]) assert.equal(value(i, "presentation", w, 1080), "Unknown", String(w));
  assert.equal(value(i, "presentation", 1920, undefined), "Unknown");
  assert.equal(value(i, "presentation", 854.4, 479.6), "854 × 480");
});
check("backend names, including Emby and Demo; anything else is Unknown", () => {
  assert.equal(value(info({ backend: "plex" }), "backend"), "Plex");
  assert.equal(value(info({ backend: "jellyfin" }), "backend"), "Jellyfin");
  assert.equal(value(info({ backend: "emby" }), "backend"), "Emby");
  assert.equal(value(info({ backend: "demo" }), "backend"), "Demo");
  assert.equal(value(info({ backend: "https://example.invalid" }), "backend"), "Unknown");
});
check("quality at tune is what this browser asked for", () => {
  assert.equal(PI.webQualityLabel("plex"), "Server default");
  assert.equal(PI.webQualityLabel("jellyfin"), "Up to 120 Mbps");
  assert.equal(PI.webQualityLabel("emby"), "Up to 120 Mbps");
  assert.equal(PI.webQualityLabel("demo"), "Unknown");
  assert.equal(value(info({ qualityAtTune: PI.webQualityLabel("emby") }), "quality"), "Up to 120 Mbps");
  assert.equal(value(info({ qualityAtTune: "secret token" }), "quality"), "Unknown");
});
check("codec allowlist matches tvOS", () => {
  const cases = { h264: "H.264", AVC1: "H.264", " hevc ": "HEVC", hvc1: "HEVC", mpeg2video: "MPEG-2", av1: "AV1", vc1: "VC-1", vp8: "Unknown" };
  for (const [k, v] of Object.entries(cases)) assert.equal(PI.codecLabel(k, true), v, k);
  const audio = { aac: "AAC", ac3: "AC-3", eac3: "E-AC-3", dca: "DTS", truehd: "TrueHD", opus: "Opus", pcm_s16le: "Unknown" };
  for (const [k, v] of Object.entries(audio)) assert.equal(PI.codecLabel(k, false), v, k);
  assert.equal(PI.codecLabel(null, true), "Unknown");
  assert.equal(PI.codecLabel("constructor", true), "Unknown", "no prototype keys");
});
check("unknown reasons and deliveries fall back to the plain ones", () => {
  const i = info();
  i.beginAttempt(1, "teleport", "because the server said so");
  assert.equal(value(i, "reason"), "No fallback used.");
  i.markReady(1, i.attemptId);
  assert.equal(value(i, "delivery"), "Unknown");
});
check("arbitrary metadata cannot carry addresses, tokens or ids into the panel", () => {
  const privateText = "https://example.invalid/private?X-Plex-Token=FAKE_PRIVATE_MARKER&api_key=FAKE_PRIVATE_MARKER";
  const i = PI.create({
    generation: 1, backend: "emby", qualityAtTune: privateText,
    videoCodec: privateText, audioCodec: "Authorization: MediaBrowser Token=FAKE_PRIVATE_MARKER",
    // Extra fields a careless caller might pass: the model ignores them.
    serverUrl: "https://example.invalid", token: "FAKE_PRIVATE_MARKER", ratingKey: "item-FAKE_PRIVATE_MARKER",
  });
  i.markReady(1, i.beginAttempt(1, "serverStream", "directPlayFailed"));
  const text = JSON.stringify(i.rows(1920, 1080)) + i.evidenceNote + JSON.stringify(i);
  for (const forbidden of ["example.invalid", "https://", "FAKE_PRIVATE_MARKER", "Authorization", "X-Plex-Token", "api_key", "item-"]) {
    assert.equal(text.includes(forbidden), false, forbidden);
  }
  assert.equal(value(i, "source"), "Video: Unknown · Audio: Unknown");
});
check("copy: plain words, no em dashes", () => {
  const all = Object.values(PI.REASONS).join(" ") + PI.EVIDENCE_NOTE + Object.values(PI.RECOVERY_REQUESTS).join(" ");
  assert.equal(/—/.test(all), false);
});

if (failures.length) {
  console.error(`playback-info: ${failures.length} failed, ${passed} passed`);
  for (const f of failures) console.error("  " + f);
  process.exit(1);
}
console.log(`playback-info: ${passed} passed`);
