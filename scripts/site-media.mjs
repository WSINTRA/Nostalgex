// Images and clips for the generated pages (blog posts, the channel guide).
//
// Two rules hold everything else up:
//
//   1. Every image carries width and height, so nothing on the page moves while
//      it loads. For a file in this repo the size is read off the file itself.
//      For a remote file (the media bucket) the content file has to say, since
//      the build cannot look.
//   2. Every image carries real alt text. A decorative duplicate of a caption is
//      worse than nothing, so the build fails on an empty alt rather than
//      quietly shipping alt="".
//
// Clips are muted, looping, poster backed video. They never autoplay from the
// markup: app.js starts them after load, and leaves them paused under reduced
// motion or Save Data.

import { readFileSync, existsSync } from "node:fs";
import path from "node:path";

import { escapeAttr, escapeHtml } from "./site-chrome.mjs";

// ---------------------------------------------------------------------------
// Intrinsic size, read from the file
// ---------------------------------------------------------------------------

function readPngSize(buf) {
  // 8 byte signature, then an IHDR chunk whose width and height are big endian.
  if (buf.length < 24) return null;
  if (buf.readUInt32BE(12) !== 0x49484452) return null; // "IHDR"
  return { width: buf.readUInt32BE(16), height: buf.readUInt32BE(20) };
}

function readJpegSize(buf) {
  // Walk the segments to the first start of frame, which carries the size.
  let i = 2;
  while (i + 9 < buf.length) {
    if (buf[i] !== 0xff) return null;
    const marker = buf[i + 1];
    const len = buf.readUInt16BE(i + 2);
    // SOF0 through SOF15, skipping the four that are not frame headers.
    if (marker >= 0xc0 && marker <= 0xcf && ![0xc4, 0xc8, 0xcc].includes(marker)) {
      return { height: buf.readUInt16BE(i + 5), width: buf.readUInt16BE(i + 7) };
    }
    i += 2 + len;
  }
  return null;
}

function readWebpSize(buf) {
  // RIFF container; the size lives in a different place in each of the three
  // WebP flavours (lossy, lossless, extended).
  if (buf.length < 30) return null;
  if (buf.toString("ascii", 0, 4) !== "RIFF" || buf.toString("ascii", 8, 12) !== "WEBP") {
    return null;
  }
  const fourcc = buf.toString("ascii", 12, 16);
  if (fourcc === "VP8 ") {
    return { width: buf.readUInt16LE(26) & 0x3fff, height: buf.readUInt16LE(28) & 0x3fff };
  }
  if (fourcc === "VP8L") {
    const bits = buf.readUInt32LE(21);
    return { width: (bits & 0x3fff) + 1, height: ((bits >> 14) & 0x3fff) + 1 };
  }
  if (fourcc === "VP8X") {
    const w = buf[24] | (buf[25] << 8) | (buf[26] << 16);
    const h = buf[27] | (buf[28] << 8) | (buf[29] << 16);
    return { width: w + 1, height: h + 1 };
  }
  return null;
}

// Returns {width, height} from the leading bytes of an image, or null for a
// format this cannot read. The header is all that is needed, so a range request
// is enough for a remote file.
export function imageSizeFromBuffer(buf, ext) {
  const e = String(ext).toLowerCase();
  if (e === ".png") return readPngSize(buf);
  if (e === ".jpg" || e === ".jpeg") return readJpegSize(buf);
  if (e === ".webp") return readWebpSize(buf);
  return null;
}

// Returns {width, height} for a local image, or null when the file is missing
// or in a format this cannot read.
export function readImageSize(filePath) {
  if (!existsSync(filePath)) return null;
  return imageSizeFromBuffer(readFileSync(filePath), path.extname(filePath));
}

// Sizes for remote images, measured once by scripts/measure-media.mjs and
// committed. The build stays offline and deterministic: it never reaches for
// the network, and a new remote image fails the build until it is measured,
// rather than shipping without width and height.
const SIZE_CACHE_PATH = new URL("./media-sizes.json", import.meta.url);

let sizeCache = null;
function remoteSize(src) {
  if (sizeCache === null) {
    try {
      sizeCache = JSON.parse(readFileSync(SIZE_CACHE_PATH, "utf8"));
    } catch {
      sizeCache = {};
    }
  }
  const hit = sizeCache[src];
  return hit && hit.width && hit.height ? { width: hit.width, height: hit.height } : null;
}

export function isRemote(src) {
  return /^https?:\/\//i.test(String(src));
}

// ---------------------------------------------------------------------------
// Front matter to a resolved image
// ---------------------------------------------------------------------------

// Reads an image out of front matter and resolves what the page needs to render
// it without layout shift. `keys` lets a caller use its own field names, so the
// blog keeps `cover` / `cover_alt` and the guide uses `image` / `image_alt`.
//
// Throws, with the content file named, when the shape is wrong: that is a build
// failure rather than a page that ships broken.
export function resolveImage(frontmatter, { file, rootDir, keys, required = false } = {}) {
  const k = {
    src: "image",
    alt: "image_alt",
    width: "image_width",
    height: "image_height",
    ...keys,
  };
  const rawSrc = frontmatter[k.src];
  if (rawSrc == null || rawSrc === "") {
    if (required) throw new Error(`${file}: "${k.src}" is required`);
    return null;
  }

  const src = String(rawSrc).trim();
  const alt = frontmatter[k.alt] == null ? "" : String(frontmatter[k.alt]).trim();
  if (!alt) {
    throw new Error(
      `${file}: "${k.src}" needs "${k.alt}". Describe what is on screen, not the file.`,
    );
  }

  let width = frontmatter[k.width] ? Number(frontmatter[k.width]) : null;
  let height = frontmatter[k.height] ? Number(frontmatter[k.height]) : null;

  if (!width || !height) {
    const measured = isRemote(src)
      ? // Measured earlier and committed: see scripts/media-sizes.json.
        remoteSize(src)
      : // Site relative path: the file is in public/ or at the project root.
        (() => {
          const rel = src.replace(/^\//, "");
          return (
            readImageSize(path.join(rootDir, "public", rel)) ||
            readImageSize(path.join(rootDir, rel))
          );
        })();
    if (measured) {
      width = measured.width;
      height = measured.height;
    }
  }

  if (!width || !height) {
    throw new Error(
      isRemote(src)
        ? `${file}: no size on record for "${src}". Run "npm run media:measure" to fetch it, or set "${k.width}" and "${k.height}".`
        : `${file}: could not measure "${src}". Check the path, or set "${k.width}" and "${k.height}".`,
    );
  }

  return { src, alt, width, height };
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

// A page's leading image. Eager and high priority: it is usually the LCP
// element, so it must not wait behind lazy loading.
export function renderCover(image, { className = "page-cover", sizes = "" } = {}) {
  if (!image) return "";
  return `<img class="${escapeAttr(className)}" src="${escapeAttr(image.src)}" alt="${escapeAttr(
    image.alt,
  )}" width="${image.width}" height="${image.height}"${
    sizes ? ` sizes="${escapeAttr(sizes)}"` : ""
  } loading="eager" decoding="async" fetchpriority="high">`;
}

// A looping clip. `preload="none"` and no `autoplay`: app.js decides, so a
// visitor on reduced motion or Save Data gets the poster and nothing else.
export function renderClip(clip) {
  if (!clip) return "";
  const sources = [
    clip.webm ? `<source src="${escapeAttr(clip.webm)}" type="video/webm">` : "",
    `<source src="${escapeAttr(clip.src)}" type="video/mp4">`,
  ]
    .filter(Boolean)
    .join("\n          ");
  return `
      <figure class="page-clip">
        <video class="page-clip-video" data-clip muted loop playsinline preload="none"${
          clip.poster ? ` poster="${escapeAttr(clip.poster)}"` : ""
        } width="${clip.width}" height="${clip.height}" aria-label="${escapeAttr(clip.alt)}">
          ${sources}
        </video>${
          clip.caption
            ? `\n        <figcaption>${escapeHtml(clip.caption)}</figcaption>`
            : ""
        }
      </figure>`;
}

// Reads a `clip:` block out of front matter. Remote clips need their size for
// the same reason images do.
export function resolveClip(frontmatter, { file, key = "clip" } = {}) {
  const raw = frontmatter[key];
  if (!raw) return null;
  if (typeof raw !== "object") {
    throw new Error(`${file}: "${key}" should be a block with src, alt, width and height`);
  }
  const src = raw.src ? String(raw.src).trim() : "";
  const alt = raw.alt ? String(raw.alt).trim() : "";
  if (!src) throw new Error(`${file}: "${key}" needs "src"`);
  if (!alt) throw new Error(`${file}: "${key}" needs "alt", describing what plays`);
  const width = Number(raw.width);
  const height = Number(raw.height);
  if (!width || !height) {
    throw new Error(`${file}: "${key}" needs "width" and "height" so the page does not jump`);
  }
  return {
    src,
    webm: raw.webm ? String(raw.webm).trim() : null,
    poster: raw.poster ? String(raw.poster).trim() : null,
    alt,
    caption: raw.caption ? String(raw.caption).trim() : null,
    width,
    height,
  };
}

// ---------------------------------------------------------------------------
// Inline markdown images
// ---------------------------------------------------------------------------

// A `marked` renderer override: inline images become figures, lazy loaded, with
// the markdown title as the caption. Sized the same way as everything else, and
// a missing alt fails the build.
export function markedImageRenderer({ file, rootDir }) {
  return {
    image({ href, title, text }) {
      const src = String(href || "").trim();
      const alt = String(text || "").trim();
      if (!alt) {
        throw new Error(`${file}: the image ${src || "(no src)"} has no alt text`);
      }
      const measured = resolveImage(
        { image: src, image_alt: alt },
        { file, rootDir, required: true },
      );
      const caption = title ? `\n  <figcaption>${escapeHtml(title)}</figcaption>` : "";
      return `<figure class="page-figure">
  <img src="${escapeAttr(measured.src)}" alt="${escapeAttr(measured.alt)}" width="${
    measured.width
  }" height="${measured.height}" loading="lazy" decoding="async">${caption}
</figure>`;
    },
  };
}

// An image on its own line is a paragraph holding one image, so the renderer
// above leaves <p><figure>...</figure></p>. A figure cannot live inside a
// paragraph: the browser closes the <p> early and leaves a stray empty one.
// Unwrap the paragraphs that hold nothing but a figure.
export function unwrapFigures(html) {
  return String(html).replace(
    /<p>\s*(<figure[\s\S]*?<\/figure>)\s*<\/p>/g,
    (_, figure) => figure,
  );
}

// Every image and clip on a page, as plain strings, for the copy checks: alt
// text is visible to a screen reader and to Google, so the held brand and dash
// rules apply to it exactly as they do to body copy.
export function mediaText(...items) {
  return items
    .filter(Boolean)
    .flatMap((item) => [item.alt, item.caption])
    .filter(Boolean)
    .join(" ");
}
