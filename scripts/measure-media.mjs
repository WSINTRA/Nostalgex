// Measures every remote image the content references and records its size in
// scripts/media-sizes.json.
//
//   npm run media:measure
//
// The build itself never touches the network: it reads this file, and fails on
// a remote image that is not in it. That keeps width and height on every image
// (so pages do not shift as they load) without making a deploy depend on a
// bucket being reachable at that moment.
//
// Re-running is cheap and idempotent. It asks for the first 64 KB of each file,
// which is enough for a PNG, JPEG or WebP header.

import { readFile, writeFile } from "node:fs/promises";
import { readdir } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import matter from "gray-matter";

import { imageSizeFromBuffer, isRemote } from "./site-media.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const CACHE_PATH = path.join(ROOT, "scripts", "media-sizes.json");
const CONTENT_DIRS = [path.join(ROOT, "content", "blog"), path.join(ROOT, "content", "bundles")];

// Front matter keys that can hold an image, plus any inline markdown image.
const IMAGE_KEYS = ["cover", "og_image", "image"];

async function collectUrls() {
  const urls = new Set();
  for (const dir of CONTENT_DIRS) {
    let files = [];
    try {
      files = (await readdir(dir)).filter((f) => f.endsWith(".md"));
    } catch {
      continue;
    }
    for (const name of files) {
      const raw = await readFile(path.join(dir, name), "utf8");
      const parsed = matter(raw);
      const fm = parsed.data || {};
      for (const key of IMAGE_KEYS) {
        if (fm[key] && isRemote(fm[key])) urls.add(String(fm[key]).trim());
      }
      if (fm.clip && fm.clip.poster && isRemote(fm.clip.poster)) {
        urls.add(String(fm.clip.poster).trim());
      }
      for (const match of parsed.content.matchAll(/!\[[^\]]*\]\(([^)\s]+)/g)) {
        if (isRemote(match[1])) urls.add(match[1]);
      }
    }
  }
  return [...urls].sort();
}

async function measure(url) {
  const res = await fetch(url, { headers: { Range: "bytes=0-65535" } });
  if (!res.ok && res.status !== 206) {
    throw new Error(`HTTP ${res.status}`);
  }
  const buf = Buffer.from(await res.arrayBuffer());
  const ext = path.extname(new URL(url).pathname);
  const size = imageSizeFromBuffer(buf, ext);
  if (!size) throw new Error(`could not read a ${ext || "(no extension)"} header`);
  return size;
}

async function main() {
  const force = process.argv.includes("--force");
  let cache = {};
  try {
    cache = JSON.parse(await readFile(CACHE_PATH, "utf8"));
  } catch {
    cache = {};
  }

  const urls = await collectUrls();
  let added = 0;
  let failed = 0;
  for (const url of urls) {
    if (cache[url] && !force) continue;
    try {
      const size = await measure(url);
      cache[url] = size;
      added += 1;
      console.log(`media: ${size.width}x${size.height}  ${url}`);
    } catch (err) {
      failed += 1;
      console.error(`media: FAILED ${url}: ${err.message}`);
    }
  }

  // Drop anything the content no longer references, so the file does not grow
  // a tail of dead URLs.
  const referenced = new Set(urls);
  const pruned = Object.keys(cache).filter((url) => !referenced.has(url));
  for (const url of pruned) delete cache[url];

  const sorted = Object.fromEntries(Object.keys(cache).sort().map((k) => [k, cache[k]]));
  await writeFile(CACHE_PATH, `${JSON.stringify(sorted, null, 2)}\n`, "utf8");
  console.log(
    `media: ${urls.length} remote image${urls.length === 1 ? "" : "s"} referenced, ${added} measured, ${pruned.length} pruned${failed ? `, ${failed} failed` : ""}`,
  );
  if (failed) process.exitCode = 1;
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
