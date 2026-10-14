import { readFile, writeFile } from "node:fs/promises";
import { BUNDLE_STYLE } from "./bundle-style.mjs";

// Renders the channel lineup (bundles + channels) into
// index.html from channels.json, the same config the app + web tuner consume.
// Run after any channel/bundle change so the site never drifts from the app.
//
//   node scripts/render-lineup.mjs
//
// Channel numbers, names, and colors come straight from channels.json.
// Bundle NAMES also come from channels.json (bundle.name) so the site is always
// in sync with the app — there is no separate marketing name. Only the accent
// color and an optional punchier blurb are presentation, and live in
// BUNDLE_STYLE (scripts/bundle-style.mjs, keyed by bundle id, shared with the
// channel guide generator). To rename a bundle everywhere (app + web tuner +
// site), change channels.json, then re-run this script.

const CHANNELS_PATH = new URL("../channels.json", import.meta.url);
const TARGETS = ["index.html"];

function esc(text) {
  return String(text).replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");
}

function replaceBetweenMarkers(html, start, end, body) {
  const s = html.indexOf(start);
  const e = html.indexOf(end);
  if (s === -1 || e === -1 || e < s) throw new Error(`Markers not found: ${start}`);
  return `${html.slice(0, s + start.length)}\n${body}\n    ${html.slice(e)}`;
}

const data = JSON.parse(await readFile(CHANNELS_PATH, "utf8"));
const byId = new Map((data.channels || []).map((c) => [c.id, c]));

// Resolve + sort channels within a bundle. Bundle name comes from channels.json
// (single source of truth); only color + optional blurb are presentation.
// Interstitials injected after specific bundles (keyed by bundle id).
// These are part of the generated output so they survive re-renders.
const LINEUP_INTERSTITIALS = {
  "decades": `    <div class="lineup__interstitial lineup__interstitial--email fade-in" data-newsletter>
      <div class="lineup__interstitial-eyebrow">&#9672; WE INTERRUPT YOUR SCHEDULE</div>
      <div class="lineup__interstitial-body">
        <div class="lineup__interstitial-copy">
          <p class="lineup__interstitial-heading">GET NOTIFIED OF UPDATES</p>
          <p class="lineup__interstitial-sub">New channels and Apple TV features land regularly. Drop your email and we&rsquo;ll let you know.</p>
        </div>
        <div class="lineup__interstitial-form-wrap">
          <form class="newsletter-form newsletter-form--compact" novalidate>
            <input type="email" name="email" required placeholder="you@example.com" autocomplete="email" maxlength="254" aria-label="Email address">
            <button type="submit">NOTIFY ME</button>
          </form>
          <p class="newsletter-msg newsletter-msg--compact" aria-live="polite"></p>
        </div>
      </div>
    </div>`,
  "franchises": `    <div class="lineup__interstitial lineup__interstitial--support fade-in">
      <div class="lineup__interstitial-eyebrow">&#9672; A WORD FROM OUR SPONSOR</div>
      <div class="lineup__interstitial-body">
        <div class="lineup__interstitial-copy">
          <p class="lineup__interstitial-heading">ENJOY THE LINEUP?</p>
          <p class="lineup__interstitial-sub">Nostalgex is free and built by one person. If it brings back the feeling of flipping through channels, a coffee goes a long way.</p>
        </div>
        <a class="lineup__interstitial-cta" href="https://buymeacoffee.com/chadmueller" target="_blank" rel="noopener">BUY ME A COFFEE &rarr;</a>
      </div>
    </div>`,
};

const bundles = (data.bundles || [])
  .map((b) => {
    const style = BUNDLE_STYLE[b.id] || {};
    const meta = {
      label: b.name,
      desc: style.desc || b.description || "",
      color: style.color || "#FFE500",
    };
    const chans = (b.channelIDs || [])
      .map((id) => byId.get(id))
      .filter(Boolean)
      .sort((a, z) => a.number - z.number);
    return { id: b.id, meta, chans };
  })
  .filter((b) => b.chans.length > 0)
  // Order bundles by their lowest channel number so the showcase reads like a
  // real channel guide (True Crime sits at 85-89, not by channels.json order).
  .sort((a, z) => a.chans[0].number - z.chans[0].number);

const totalChannels = bundles.reduce((n, b) => n + b.chans.length, 0);

const lineup = bundles
  .map((b) => {
    const items = b.chans
      .map((ch) => {
        const col = ch.colorHex || b.meta.color;
        return `        <div class="lineup__item" style="border-color:${col};"><span class="lineup__num" style="color:${col};">${ch.number}</span><span class="lineup__name">${esc(ch.name)}</span></div>`;
      })
      .join("\n");
    const group = [
      `    <div class="lineup__group fade-in">`,
      `      <div class="lineup__group-head">`,
      // The name links to the bundle's guide page; the rest of the head stays
      // the collapse toggle that app.js wires up. Anchor text is the bundle
      // name on purpose, so the internal link says what it points at.
      `        <a class="lineup__group-name lineup__group-link" href="/channels/${b.id}">${esc(b.meta.label)}</a>`,
      `        <span class="lineup__group-count">${b.chans.length} CHANNELS</span>`,
      `      </div>`,
      `      <div class="lineup__grid">`,
      items,
      `      </div>`,
      `    </div>`,
    ].join("\n");
    // The lineup renders as one uninterrupted guide. CTAs live above and
    // below the section in index.html, not spliced between bundles.
    return group;
  })
  .join("\n");

for (const file of TARGETS) {
  const fileUrl = new URL(`../${file}`, import.meta.url);
  let html = await readFile(fileUrl, "utf8");
  html = replaceBetweenMarkers(html, "<!-- LINEUP:START (auto-generated from channels.json — run scripts/render-lineup.mjs) -->", "<!-- LINEUP:END (auto-generated) -->", lineup);
  await writeFile(fileUrl, html, "utf8");
}

console.log(`Rendered ${bundles.length} bundles / ${totalChannels} channels into ${TARGETS.join(", ")}`);
