// Presentation for the bundles in channels.json: an accent color and an
// optional punchier blurb, keyed by bundle id.
//
// Bundle NAMES are not here. They come from channels.json (bundle.name) so the
// site, the app and the web tuner can never disagree about what a bundle is
// called. Only the colour and the blurb are marketing, and they live here.
//
// This file exists on its own because two generators want the same table:
// scripts/render-lineup.mjs (the lineup on the home page) and
// scripts/build-bundles.mjs (the channel guide). render-lineup.mjs does its
// work at module top level, so build-bundles.mjs cannot import it; a shared
// data module is the way to use one table in both places.

export const BUNDLE_STYLE = {
  "nostalgex":      { color: "#FFE500", desc: "The 80s and 90s. All retro, all the time." },
  "kids":           { color: "#00C4FF", desc: "Disney, Nick, Pixar, and the whole crew." },
  "truecrime":      { color: "#B0392E", desc: "Docs, thrillers, and whodunits." },
  "essentials":     { color: "#9B59B6", desc: "Everyday favorites and feel-good picks." },
  "premium":        { color: "#FF3D6E", desc: "The curated stuff. Anime, musicals, the greats." },
  "adventureland":  { color: "#D4A017", desc: "Epic quests, disasters, and adrenaline." },
  "sports":         { color: "#1DB954", desc: "Movies, shows, and docs." },
  "decades":        { color: "#C0392B", desc: "Sorted by era, the 60s through today." },
  "franchises":     { color: "#FFE81F", desc: "Movie franchise marathons." },
  "streamers":      { color: "#8B5CF6", desc: "By streaming service and studio." },
  "seasonal":       { color: "#C41E3A", desc: "Halloween and holiday, in season." },
  // TIS THE SEASON split out of the seasonal bundle in channels.json v37 and
  // had no entry here, so it fell back to the default yellow. Sports already
  // owns #1DB954, so the Christmas row gets a deeper green of its own.
  "tis-the-season": { color: "#2E8B57", desc: "Christmas and holiday channels, in season." },
  "high-rotation":  { color: "#FF2DB4", desc: "Music videos by genre." },
  "arthouse":       { color: "#F5E6C8", desc: "Criterion, foreign films, midnight movies, and cult classics." },
};

// A bundle id that is in channels.json but not in the table above still has to
// render. Callers use this instead of indexing BUNDLE_STYLE directly so a new
// bundle gets the house yellow and a blank blurb rather than crashing a build.
export const DEFAULT_BUNDLE_COLOR = "#FFE500";

export function bundleStyle(id) {
  const style = BUNDLE_STYLE[id] || {};
  return { color: style.color || DEFAULT_BUNDLE_COLOR, desc: style.desc || "" };
}
