// The web tuner's version, for both builds.
//
// One committed source: "tunerVersion" in package.json. The hosted build on
// Vercel uses it as is (Vercel's clone is shallow and has no tags to read). The
// Docker build uses it too, unless the image's NOSTALGEX_TUNER_VERSION build arg
// says otherwise. The release workflow passes the tag's version as that arg and
// fails before pushing when the tag and "tunerVersion" differ, so the two cannot
// drift. RELEASING.md has the release step.
//
// Not package.json "version": package-lock.json repeats that one, and
// `npm version` would tag v1.0.x, which in this repo means an Apple TV release.
//
// The build writes the version into both tuner pages as
//   <meta name="nostalgex-tuner-version" content="1.0.3">
// for support, and plex-tuner.html reads it for the line at the bottom of
// Settings (see "WEB TUNER VERSION" in that page). The Docker build also writes
// it into the default config.json, which docker/40-config.sh reads at start.

import { readFileSync } from 'fs'
import { resolve, basename } from 'path'

/** What the page accepts and shows: 1.0.3, or a prerelease such as 1.0.3-rc1. */
export const RELEASE_VERSION = /^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/

// A build arg can be anything; this is what can sit in an HTML attribute and a
// shell-written JSON string as is (docker/40-config.sh allows the same characters).
const SAFE_VALUE = /^[A-Za-z0-9._-]{1,64}$/

const TUNER_PAGES = new Set(['plex-tuner.html', 'web-tuner.html'])

/** package.json "tunerVersion". Throws when it is missing or not a release number. */
export function committedTunerVersion(root) {
  const pkg = JSON.parse(readFileSync(resolve(root, 'package.json'), 'utf8'))
  const v = pkg.tunerVersion
  if (typeof v !== 'string' || !RELEASE_VERSION.test(v)) {
    throw new Error(`package.json "tunerVersion" must be a release number like 1.0.3, got ${JSON.stringify(v)}`)
  }
  return v
}

/**
 * The version a build carries: NOSTALGEX_TUNER_VERSION when it is set and not
 * empty (the Docker release passes the tag's version), else package.json.
 */
export function resolveTunerVersion(env, root) {
  const fromEnv = (env.NOSTALGEX_TUNER_VERSION || '').trim()
  if (fromEnv) {
    if (!SAFE_VALUE.test(fromEnv)) {
      throw new Error(`NOSTALGEX_TUNER_VERSION may only hold letters, digits, dots, dashes and underscores, got ${JSON.stringify(fromEnv)}`)
    }
    return fromEnv
  }
  return committedTunerVersion(root)
}

/** Insert the version meta after <meta charset> on the two tuner pages. Throws if there is none. */
export function addTunerVersionMeta(html, version, file = 'page') {
  if (!TUNER_PAGES.has(basename(file))) return html
  if (!SAFE_VALUE.test(version)) throw new Error(`${file}: unsafe tuner version ${JSON.stringify(version)}`)
  let done = false
  const out = html.replace(/<meta charset="UTF-8">/i, (m) => {
    done = true
    return `${m}\n<meta name="nostalgex-tuner-version" content="${version}">`
  })
  if (!done) throw new Error(`${file}: no <meta charset> to put the tuner version after`)
  return out
}

/** Vite plugin, used by the hosted and the self-host build alike. */
export function tunerVersionPlugin(version) {
  return {
    name: 'nostalgex-tuner-version',
    transformIndexHtml: {
      order: 'post',
      handler(html, ctx) {
        return addTunerVersionMeta(html, version, ctx.filename)
      },
    },
  }
}
