// Build the static blog.
//
// Reads Markdown posts from content/blog/, renders them into HTML pages that
// share the site's styles and chrome, generates /blog (index) and
// /blog/<slug> (one per post), and rewrites public/sitemap.xml so Vercel
// picks the posts up for SEO.
//
// Why a plain Node script instead of a Vite plugin? vite.config.js already
// has a hand-rolled rollupOptions.input list of HTML entries and a
// closeBundle hook that copies browser scripts into dist/. A sibling plugin
// (`emitBlog`) in that file calls into this module during `closeBundle` so
// posts land in dist/blog/, and `npm run build` also runs this directly to
// keep sitemap.xml fresh in the repo (same way `npm run changelog:render`
// updates index.html before `vite build`).

import { readFile, writeFile, readdir, mkdir, copyFile, stat } from "node:fs/promises";
import { existsSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { Marked } from "marked";
import matter from "gray-matter";
// Head, nav and footer live in scripts/site-chrome.mjs so the blog and the
// channel guide render the same chrome. They used to be private copies in
// this file, and the blog header drifted from the global one once already.
import {
  SITE_ORIGIN,
  DEFAULT_OG_IMAGE,
  DEFAULT_OG_ALT,
  APPLE_TV_URL,
  ORG_ID,
  APP_ID,
  AUTHOR_ID,
  AUTHOR_NODE,
  ORG_NODE,
  escapeHtml,
  escapeAttr,
  renderNav,
  renderFooter,
  renderHead,
  resolveViteAssetHrefs,
} from "./site-chrome.mjs";
import {
  resolveImage,
  resolveClip,
  renderClip,
  markedImageRenderer,
  unwrapFigures,
  isRemote,
} from "./site-media.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const CONTENT_DIR = path.join(ROOT, "content", "blog");
const PUBLIC_DIR = path.join(ROOT, "public");
const SITEMAP_PATH = path.join(PUBLIC_DIR, "sitemap.xml");

const BLOG_TITLE = "Nostalgex Blog";
const BLOG_DESCRIPTION =
  "Retro TV lineups and setup guides for turning your Plex, Jellyfin or Emby library into live channels with a retro TV guide.";

function formatIsoDate(value) {
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) {
    throw new Error(`Invalid date: ${value}`);
  }
  return d.toISOString().slice(0, 10);
}

function formatHumanDate(value) {
  const d = new Date(`${value}T00:00:00Z`);
  if (Number.isNaN(d.getTime())) return value;
  return d.toLocaleDateString("en-US", {
    year: "numeric",
    month: "long",
    day: "numeric",
    timeZone: "UTC",
  });
}

function requireField(frontmatter, key, file) {
  const value = frontmatter[key];
  if (value == null || value === "") {
    throw new Error(`${file}: missing required frontmatter field "${key}"`);
  }
  return value;
}

function sanitizeSlug(slug, file) {
  if (!/^[a-z0-9][a-z0-9-]*$/.test(slug)) {
    throw new Error(
      `${file}: slug "${slug}" must be lowercase a-z, 0-9 and -`,
    );
  }
  return slug;
}

// Strip the first leading H1 if its text matches the frontmatter title. Posts
// may or may not include an in-body H1; the template always renders one from
// the title, so we drop a duplicate to avoid two H1s on the page.
function stripLeadingH1(markdown, title) {
  const trimmed = markdown.replace(/^\s+/, "");
  const h1Match = trimmed.match(/^#\s+(.+?)\s*\n/);
  if (!h1Match) return trimmed;
  const h1Text = h1Match[1].trim();
  if (h1Text === title.trim()) {
    return trimmed.slice(h1Match[0].length).replace(/^\s+/, "");
  }
  return trimmed;
}

// Remove HTML comment blocks (build notes, link-back reminders) so they never
// reach the rendered page. These are standalone <!-- ... --> blocks in the
// posts; marked otherwise passes them straight through into the HTML source.
function stripHtmlComments(markdown) {
  return markdown.replace(/<!--[\s\S]*?-->/g, "");
}

// Collapse a snippet of Markdown to plain text for use in JSON-LD values.
// Turns [label](url) into label, drops emphasis/backticks, and flattens
// whitespace so FAQ answers are clean strings a validator will accept.
function markdownToText(markdown) {
  return markdown
    .replace(/!\[[^\]]*\]\([^)]*\)/g, "") // images
    .replace(/\[([^\]]+)\]\([^)]*\)/g, "$1") // links -> label
    .replace(/[*_`]/g, "") // emphasis / code marks
    .replace(/\s+/g, " ")
    .trim();
}

// Pull the "## FAQ" section apart into { question, answer } pairs: each "### "
// is a question, and the prose until the next "###" or "##" is its answer.
// Returns [] when the post has no FAQ section, so FAQPage is only emitted for
// posts that actually carry one.
function extractFaq(markdown) {
  const lines = markdown.split("\n");
  let i = lines.findIndex((l) => /^##\s+FAQ\s*$/i.test(l.trim()));
  if (i === -1) return [];

  const items = [];
  i += 1;
  let question = null;
  let answerLines = [];
  const flush = () => {
    if (question) {
      const answer = markdownToText(answerLines.join("\n"));
      if (answer) items.push({ question, answer });
    }
    question = null;
    answerLines = [];
  };

  for (; i < lines.length; i += 1) {
    const line = lines[i];
    if (/^##\s+/.test(line) && !/^###\s+/.test(line)) {
      // next top-level section ends the FAQ
      break;
    }
    const q = line.match(/^###\s+(.+?)\s*$/);
    if (q) {
      flush();
      question = markdownToText(q[1]);
      continue;
    }
    if (question) answerLines.push(line);
  }
  flush();
  return items;
}

// Wrap each rendered <table> in a scroll container so wide comparison tables
// scroll horizontally on phones instead of crushing their columns. marked
// emits bare <table> tags, so a string wrap is simpler and more
// version-proof than overriding the renderer.
function wrapTables(html) {
  return html
    .replace(/<table>/g, '<div class="blog-table-wrap"><table>')
    .replace(/<\/table>/g, "</table></div>");
}

function buildFaqJsonLd(faqItems, id) {
  if (!faqItems.length) return null;
  return {
    "@type": "FAQPage",
    "@id": id,
    mainEntity: faqItems.map((item) => ({
      "@type": "Question",
      name: item.question,
      acceptedAnswer: {
        "@type": "Answer",
        text: item.answer,
      },
    })),
  };
}

function renderPostCta() {
  return `
      <section class="blog-post-cta" aria-labelledby="blog-post-cta-heading">
        <h2 id="blog-post-cta-heading">Try Nostalgex tonight</h2>
        <p>Nostalgex turns your own Plex, Jellyfin or Emby library into live channels with a retro TV guide. It's free and open source.</p>
        <div class="cta-row cta-center">
          <a class="btn btn-ink btn-lg" href="/web-tuner">Try the free web tuner</a>
          <a class="btn btn-paper btn-lg" href="${APPLE_TV_URL}" target="_blank" rel="noopener">Free on Apple TV</a>
        </div>
        <p class="blog-post-cta-guides">Setup guides: <a href="/plex">Nostalgex for Plex</a>, <a href="/jellyfin">Nostalgex for Jellyfin</a>, <a href="/emby">Nostalgex for Emby</a>.</p>
        <p class="blog-post-cta-discord"><a href="https://discord.gg/FgnZcr5bDT" target="_blank" rel="noopener"><svg viewBox="0 0 24 24" aria-hidden="true" fill="currentColor"><path d="M20.317 4.37a19.79 19.79 0 0 0-4.885-1.515.07.07 0 0 0-.075.035c-.21.375-.444.864-.608 1.25a18.27 18.27 0 0 0-5.487 0 12.64 12.64 0 0 0-.617-1.25.077.077 0 0 0-.079-.035A19.736 19.736 0 0 0 3.68 4.37a.07.07 0 0 0-.032.027C.533 9.046-.32 13.58.099 18.058a.082.082 0 0 0 .031.056 19.9 19.9 0 0 0 5.993 3.03.078.078 0 0 0 .084-.028c.462-.63.874-1.295 1.226-1.994a.076.076 0 0 0-.041-.106 13.1 13.1 0 0 1-1.872-.892.077.077 0 0 1-.008-.128c.126-.094.252-.192.372-.291a.074.074 0 0 1 .077-.01c3.927 1.793 8.18 1.793 12.061 0a.073.073 0 0 1 .078.01c.12.099.246.198.373.292a.077.077 0 0 1-.006.127c-.598.35-1.22.645-1.873.893a.076.076 0 0 0-.04.106c.36.698.772 1.362 1.225 1.993a.076.076 0 0 0 .084.029 19.84 19.84 0 0 0 6.002-3.03.077.077 0 0 0 .032-.055c.5-5.177-.838-9.673-3.549-13.662a.06.06 0 0 0-.031-.028zM8.02 15.33c-1.183 0-2.157-1.085-2.157-2.419 0-1.333.955-2.418 2.157-2.418 1.21 0 2.176 1.094 2.157 2.418 0 1.334-.955 2.419-2.157 2.419zm7.975 0c-1.183 0-2.157-1.085-2.157-2.419 0-1.333.955-2.418 2.157-2.418 1.21 0 2.176 1.094 2.157 2.418 0 1.334-.946 2.419-2.157 2.419z"/></svg>Join the Discord</a></p>
      </section>`;
}

function renderPostPage(post, assetHrefs = {}) {
  const canonical = `${SITE_ORIGIN}/blog/${post.slug}`;
  const card = post.ogImageFm || post.cover;
  const ogImage = card
    ? (isRemote(card.src) ? card.src : `${SITE_ORIGIN}${card.src}`)
    : DEFAULT_OG_IMAGE;

  const seoTitle = post.seoTitle || post.title;
  const pageTitle = `${seoTitle} | Nostalgex`;
  const dateModified = post.updatedIso || post.dateIso;

  // Chad writes the posts. A post that names a different author in its front
  // matter gets that person as a plain Person instead of the shared #chad node.
  const authorRef =
    post.author && post.author !== AUTHOR_NODE.name
      ? { "@type": "Person", name: post.author }
      : { "@id": AUTHOR_ID };

  const article = {
    "@type": "Article",
    "@id": `${canonical}#article`,
    headline: post.title,
    description: post.description,
    image: [ogImage],
    datePublished: post.dateIso,
    dateModified,
    author: authorRef,
    publisher: { "@id": ORG_ID },
    about: { "@id": APP_ID },
    mainEntityOfPage: { "@type": "WebPage", "@id": canonical },
    url: canonical,
  };

  const breadcrumb = {
    "@type": "BreadcrumbList",
    "@id": `${canonical}#breadcrumb`,
    itemListElement: [
      { "@type": "ListItem", position: 1, name: "Home", item: `${SITE_ORIGIN}/` },
      { "@type": "ListItem", position: 2, name: "Blog", item: `${SITE_ORIGIN}/blog` },
      { "@type": "ListItem", position: 3, name: post.title, item: canonical },
    ],
  };

  // One @graph per page: Article, breadcrumbs, the shared Person and
  // Organization nodes, the auto-generated FAQPage (when the post has a
  // "## FAQ" section) and any extra `schema` entries from front matter.
  const extraNodes = post.extraSchema.map((node) => {
    if (node && typeof node === "object" && !Array.isArray(node)) {
      const { "@context": _ctx, ...rest } = node;
      return rest;
    }
    return node;
  });
  const jsonLd = {
    "@context": "https://schema.org",
    "@graph": [
      article,
      breadcrumb,
      AUTHOR_NODE,
      ORG_NODE,
      buildFaqJsonLd(post.faq, `${canonical}#faq`),
      ...extraNodes,
    ].filter(Boolean),
  };

  const extraMeta = [
    `<meta property="article:published_time" content="${escapeAttr(post.dateIso)}">`,
    `<meta property="article:modified_time" content="${escapeAttr(dateModified)}">`,
  ].join("\n");

  const coverBlock = post.coverUrl
    ? `
        <img class="blog-post-cover" src="${escapeAttr(post.cover.src)}" alt="${escapeAttr(post.cover.alt)}" width="${post.cover.width}" height="${post.cover.height}" loading="eager" decoding="async" fetchpriority="high">`
    : "";

  // A Marked instance per post: the image renderer closes over the file name,
  // so a missing alt names the post that caused it, and marked.use() on the
  // shared instance would stack one closure per post.
  const md = new Marked({ renderer: markedImageRenderer({ file: post.rel, rootDir: ROOT }) });
  const bodyHtml =
    unwrapFigures(wrapTables(md.parse(stripLeadingH1(post.markdown, post.title)))) +
    (post.clip ? renderClip(post.clip) : "");

  const appScript = assetHrefs.appScriptHref || "/app.js";

  return `${renderHead({
    title: pageTitle,
    description: post.description,
    canonical,
    ogImage,
    ogType: "article",
    ogImageAlt: card ? card.alt || DEFAULT_OG_ALT : DEFAULT_OG_ALT,
    ogImageWidth: card ? card.width : null,
    ogImageHeight: card ? card.height : null,
    jsonLd,
    extraMeta,
    stylesHref: assetHrefs.stylesHref,
    appScriptHref: appScript,
  })}
<body>
${renderNav()}

  <main id="top" class="blog-main">
    <article class="blog-post">
      <div class="container container-narrow">
        <p class="blog-post-eyebrow"><a href="/blog">Nostalgex Blog</a></p>
        <h1 class="blog-post-title">${escapeHtml(post.title)}</h1>
        <p class="blog-post-meta">${post.author ? `By ${escapeHtml(post.author)} &middot; ` : ""}<time datetime="${escapeAttr(post.dateIso)}">${escapeHtml(post.dateHuman)}</time></p>${coverBlock}
        <div class="blog-post-body">
${bodyHtml}
        </div>
${renderPostCta()}
      </div>
    </article>
  </main>

${renderFooter()}

  <script type="module" src="${escapeAttr(appScript)}"></script>
</body>
</html>
`;
}

function renderIndexPage(posts, assetHrefs = {}) {
  const canonical = `${SITE_ORIGIN}/blog`;
  const pageTitle = "Nostalgex Blog: Retro TV Lineups and Setup Guides";

  const jsonLd = {
    "@context": "https://schema.org",
    "@graph": [
      {
        "@type": "Blog",
        "@id": `${canonical}#blog`,
        name: BLOG_TITLE,
        description: BLOG_DESCRIPTION,
        url: canonical,
        publisher: { "@id": ORG_ID },
        blogPost: posts.map((post) => ({
          "@type": "BlogPosting",
          headline: post.title,
          description: post.description,
          datePublished: post.dateIso,
          dateModified: post.updatedIso || post.dateIso,
          author: { "@id": AUTHOR_ID },
          url: `${SITE_ORIGIN}/blog/${post.slug}`,
        })),
      },
      {
        "@type": "BreadcrumbList",
        "@id": `${canonical}#breadcrumb`,
        itemListElement: [
          { "@type": "ListItem", position: 1, name: "Home", item: `${SITE_ORIGIN}/` },
          { "@type": "ListItem", position: 2, name: "Blog", item: canonical },
        ],
      },
      AUTHOR_NODE,
      ORG_NODE,
    ],
  };

  const cardsHtml = posts
    .map((post) => {
      const href = `/blog/${post.slug}`;
      const cover = post.coverUrl
        ? `<img class="blog-card-cover" src="${escapeAttr(post.cover.src)}" alt="" width="${post.cover.width}" height="${post.cover.height}" loading="lazy" decoding="async">`
        : "";
      return `          <li class="blog-card">
            <a class="blog-card-link" href="${escapeAttr(href)}">
              ${cover}
              <div class="blog-card-body">
                <p class="blog-card-meta"><time datetime="${escapeAttr(post.dateIso)}">${escapeHtml(post.dateHuman)}</time></p>
                <h2 class="blog-card-title">${escapeHtml(post.title)}</h2>
                <p class="blog-card-dek">${escapeHtml(post.description)}</p>
                <span class="blog-card-cta">Read &rarr;</span>
              </div>
            </a>
          </li>`;
    })
    .join("\n");

  const emptyState = `          <li class="blog-card blog-card--empty">
            <p>No posts yet. New nostalgia lists are on the way.</p>
          </li>`;

  const appScript = assetHrefs.appScriptHref || "/app.js";

  return `${renderHead({
    title: pageTitle,
    description: BLOG_DESCRIPTION,
    canonical,
    ogImage: DEFAULT_OG_IMAGE,
    ogType: "website",
    jsonLd,
    stylesHref: assetHrefs.stylesHref,
    appScriptHref: appScript,
  })}
<body>
${renderNav()}

  <main id="top" class="blog-main">
    <section class="blog-index">
      <div class="container container-narrow">
        <header class="blog-index-head">
          <p class="blog-post-eyebrow">${escapeHtml(BLOG_TITLE)}</p>
          <h1>Retro TV lineups and setup guides.</h1>
          <p class="blog-index-dek">${escapeHtml(BLOG_DESCRIPTION)}</p>
        </header>
        <ul class="blog-list">
${posts.length ? cardsHtml : emptyState}
        </ul>
      </div>
    </section>
  </main>

${renderFooter()}

  <script type="module" src="${escapeAttr(appScript)}"></script>
</body>
</html>
`;
}

export async function loadPosts() {
  if (!existsSync(CONTENT_DIR)) return [];

  const entries = await readdir(CONTENT_DIR, { withFileTypes: true });
  const files = entries
    .filter((entry) => entry.isFile() && entry.name.endsWith(".md"))
    .map((entry) => entry.name)
    .sort();

  const seenSlugs = new Set();
  const posts = [];
  for (const file of files) {
    const fullPath = path.join(CONTENT_DIR, file);
    const raw = await readFile(fullPath, "utf8");
    const parsed = matter(raw);
    const fm = parsed.data || {};

    const title = String(requireField(fm, "title", file));
    const description = String(requireField(fm, "description", file));
    const slug = sanitizeSlug(String(requireField(fm, "slug", file)), file);
    const dateIso = formatIsoDate(requireField(fm, "date", file));
    const dateHuman = formatHumanDate(dateIso);
    const rel = path.relative(ROOT, file);
    // cover is the post's lead image; og_image is the social card when it needs
    // to differ (1200x630 crops differently from a 16 by 9 hero). Both resolve
    // their real dimensions now so the page never shifts as they load.
    const cover = resolveImage(fm, {
      file: rel,
      rootDir: ROOT,
      keys: { src: "cover", alt: "cover_alt", width: "cover_width", height: "cover_height" },
    });
    const ogImageFm = resolveImage(fm, {
      file: rel,
      rootDir: ROOT,
      keys: {
        src: "og_image",
        alt: "og_image_alt",
        width: "og_image_width",
        height: "og_image_height",
      },
    });
    const clip = resolveClip(fm, { file: rel });
    const coverUrl = cover ? cover.src : null;
    const seoTitle = fm.seo_title ? String(fm.seo_title) : null;
    const draft = fm.draft === true;
    const author = fm.author ? String(fm.author) : null;
    const updatedIso = fm.updated ? formatIsoDate(fm.updated) : null;
    const coverAlt = cover ? cover.alt : "";

    // Optional extra JSON-LD: a `schema` list in frontmatter. Each entry is
    // emitted verbatim as its own <script type="application/ld+json"> next to
    // the Article and auto-generated FAQPage tags. None of today's posts use
    // it; it's here so a future post can carry HowTo, ItemList, etc.
    let extraSchema = [];
    if (fm.schema != null) {
      extraSchema = Array.isArray(fm.schema) ? fm.schema : [fm.schema];
    }

    if (seenSlugs.has(slug)) {
      throw new Error(`${file}: duplicate slug "${slug}"`);
    }
    seenSlugs.add(slug);

    const markdown = stripHtmlComments(parsed.content);
    const faq = extractFaq(markdown);

    posts.push({
      file,
      title,
      description,
      slug,
      dateIso,
      dateHuman,
      coverUrl,
      seoTitle,
      draft,
      author,
      updatedIso,
      coverAlt,
      cover,
      ogImageFm,
      clip,
      rel,
      extraSchema,
      faq,
      markdown,
    });
  }

  posts.sort((a, b) => (a.dateIso < b.dateIso ? 1 : a.dateIso > b.dateIso ? -1 : a.slug.localeCompare(b.slug)));
  // A draft stays in content/blog/ (so it's still validated above) but gets no
  // dist page, index card, or sitemap URL until its `draft: true` is removed.
  return posts.filter((post) => !post.draft);
}

export function renderBlogAssets(posts, assetHrefs = {}) {
  const assets = new Map();
  // Emit the index as /blog.html (served at /blog by Vercel's cleanUrls)
  // instead of /blog/index.html. Both work on Vercel, but the file-level
  // variant also behaves correctly under `vite preview`, which otherwise
  // falls through to a SPA-style index when a bare /blog is requested.
  assets.set("blog.html", renderIndexPage(posts, assetHrefs));
  for (const post of posts) {
    assets.set(`blog/${post.slug}.html`, renderPostPage(post, assetHrefs));
  }
  return assets;
}

async function writeAssets(assets, outDir) {
  for (const [relPath, html] of assets) {
    const target = path.join(outDir, relPath);
    await mkdir(path.dirname(target), { recursive: true });
    await writeFile(target, html, "utf8");
  }
}

async function updateSitemap(posts) {
  const raw = await readFile(SITEMAP_PATH, "utf8");

  // Rip out any previously generated blog block (idempotent), then re-insert.
  const START = "<!-- BLOG:START (generated) -->";
  const END = "<!-- BLOG:END (generated) -->";
  const escapeRegex = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  let cleaned = raw.replace(
    new RegExp(`\\s*${escapeRegex(START)}[\\s\\S]*?${escapeRegex(END)}`, "g"),
    "",
  );

  // Google ignores changefreq and priority, so entries carry loc + lastmod
  // only, matching the static block above the marker. /blog's lastmod is the
  // newest post date (published or updated).
  const postDates = posts.map((post) => post.updatedIso || post.dateIso);
  const newest = postDates.length ? postDates.slice().sort().at(-1) : null;
  const urls = [
    { loc: `${SITE_ORIGIN}/blog`, lastmod: newest },
    ...posts.map((post, i) => ({
      loc: `${SITE_ORIGIN}/blog/${post.slug}`,
      lastmod: postDates[i],
    })),
  ];

  const urlXml = urls
    .map((entry) =>
      entry.lastmod
        ? `  <url><loc>${entry.loc}</loc><lastmod>${entry.lastmod}</lastmod></url>`
        : `  <url><loc>${entry.loc}</loc></url>`,
    )
    .join("\n");

  const block = `${START}\n${urlXml}\n  ${END}`;

  const insertion = cleaned.replace(
    /\n?<\/urlset>\s*$/,
    `\n${block}\n</urlset>\n`,
  );

  if (insertion === cleaned) {
    throw new Error("sitemap.xml: could not find </urlset> to insert into");
  }

  await writeFile(SITEMAP_PATH, insertion, "utf8");
}

export async function writeBlogToDist(distDir) {
  const posts = await loadPosts();
  const assetHrefs = await resolveViteAssetHrefs(distDir);
  const assets = renderBlogAssets(posts, assetHrefs);
  await writeAssets(assets, distDir);

  // Also copy any public/blog/<slug>/ images into dist/. Vite copies the
  // public/ tree on its own, but this plugin runs in closeBundle alongside
  // copyBrowserScripts, so belt-and-braces: make sure the blog images survive
  // even if someone adds a `public/blog/` directory after the public copy pass.
  const srcBlogAssets = path.join(PUBLIC_DIR, "blog");
  if (existsSync(srcBlogAssets)) {
    await copyTree(srcBlogAssets, path.join(distDir, "blog"));
  }

  // Mirror the project-root logo/ directory into dist/logo/. The marketing
  // pages reference logo images with a relative path (./logo/...), so Vite
  // inlines them as data URLs during HTML processing. Blog pages are generated
  // after Vite finishes, so they reference /logo/... absolutely and need the
  // raw files present at that path on disk.
  const srcLogo = path.join(path.dirname(PUBLIC_DIR), "logo");
  if (existsSync(srcLogo)) {
    await copyTree(srcLogo, path.join(distDir, "logo"));
  }
  return posts;
}

async function copyTree(src, dest) {
  const entries = await readdir(src, { withFileTypes: true });
  await mkdir(dest, { recursive: true });
  for (const entry of entries) {
    const from = path.join(src, entry.name);
    const to = path.join(dest, entry.name);
    if (entry.isDirectory()) {
      await copyTree(from, to);
    } else if (entry.isFile()) {
      // Don't overwrite a generated HTML (blog/index.html) with any
      // index.html that might have snuck into public/blog/ by mistake.
      const existing = await stat(to).catch(() => null);
      if (existing) continue;
      await copyFile(from, to);
    }
  }
}

async function main() {
  const posts = await loadPosts();
  await updateSitemap(posts);
  console.log(
    `blog: rendered ${posts.length} post${posts.length === 1 ? "" : "s"}, sitemap updated`,
  );
}

const entryPath = process.argv[1] ? path.resolve(process.argv[1]) : "";
const selfPath = path.resolve(fileURLToPath(import.meta.url));

if (entryPath === selfPath) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
