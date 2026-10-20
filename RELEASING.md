# Releasing Nostalgex

Three things ship out of this repo and they ship independently:

- **The site** (`index.html`, `web-tuner.html`, `support.html`, `plex-tuner.html`) on Vercel.
- **The tvOS app** (`Nostalgex/`) through App Store Connect.
- **The Docker web tuner** (`ghcr.io/chadmueller/nostalgex`) from a `tuner-v*` tag.

---

## Where the version numbers actually live

Both in `Nostalgex/Nostalgex.xcodeproj/project.pbxproj`, and both appear **twice**
(Debug and Release config blocks). Change all four values or the two configs drift.

| Key | Meaning | Today |
|---|---|---|
| `MARKETING_VERSION` | The version users see, e.g. `1.0.11` | 1.0.11 |
| `CURRENT_PROJECT_VERSION` | The build number, e.g. `26` | 26 |

```
grep -n "MARKETING_VERSION\|CURRENT_PROJECT_VERSION" Nostalgex/Nostalgex.xcodeproj/project.pbxproj
```

`TVOS_DEPLOYMENT_TARGET` is in the same file. It is currently **18.0**. If you raise it,
the JSON-LD `operatingSystem` string in `index.html` and the App Store listing both have
to move with it.

**The web tuner** has its own number: `"tunerVersion"` in `package.json`, the same number as
the `tuner-v*` tag cut from that commit. Settings shows it at the bottom, `WEB TUNER 1.0.3` on
nostalgex.app and `WEB TUNER 1.0.3 · DOCKER` in the container, and both tuner pages carry it
as `<meta name="nostalgex-tuner-version">`. package.json `"version"` is something else and
nothing reads it.

---

## The one rule that keeps getting broken

**Read the real latest build number from App Store Connect or TestFlight before you bump it.
Never from memory, and never from the last release commit.**

The last four release commits went 27, then 26, then 27, then 26, because the number was
being guessed from git instead of read from Apple. The repo now says build 26 while
TestFlight's latest is build 25.

The check takes ten seconds:

1. App Store Connect → Nostalgex → TestFlight → note the highest build number Apple has.
2. New build number = that number + 1. Apple rejects a build number it has already seen,
   so it only ever goes up.
3. Then edit `project.pbxproj`.

Uploading is what makes a build number real. A number that was committed but never
uploaded is still free to reuse, but confirm that in TestFlight rather than assuming.

---

## Web release

1. Add the release to `content/changelog.json` (newest entry first).
2. Regenerate the auto-built regions. Neither region is safe to hand-edit:
   ```
   npm run changelog:render         # CHANGELOG:START/END in index.html
   node scripts/render-lineup.mjs   # LINEUP:START/END, from channels.json
   ```
   Note `npm run build` runs the changelog render but **not** the lineup render.
3. Channel counts: `render-lineup.mjs` also writes the exact numbers into the
   no-JS fallbacks near the lineup header (`data-lineup-channels`,
   `data-lineup-bundles`), and `app.js` recounts at runtime. Prose on the site
   says "130+ channels" so it does not go stale; `npm run bundles:render:strict`
   fails if a static page claims more channels than `channels.json` has, or
   names an exact count that is not the real one.
4. Push to `main`. Vercel builds and deploys production on its own. No CLI step.
5. Load nostalgex.app and the web tuner once and confirm nothing 404s.

## Docker image release (web tuner)

The container ships from a `tuner-vX.Y.Z` tag (`.github/workflows/docker.yml`), apart from
the site and the app. Tag when a batch of tuner changes is worth shipping to self-hosters.

1. **Bump `"tunerVersion"` in `package.json` to `X.Y.Z` in the commit you are about to tag.**
   nostalgex.app shows the new number as soon as that commit is on `main`.
2. `npm test`, `npm run build`, `npm run build:selfhost`, then
   `npm run test:tuner-version:builds` (both builds carry `X.Y.Z`).
3. Tag that commit and push the tag:
   ```
   git tag tuner-vX.Y.Z && git push origin tuner-vX.Y.Z
   ```
4. The workflow checks that the tag and `tunerVersion` agree and stops before pushing an
   image if they don't. To recover: delete the tag (`git tag -d tuner-vX.Y.Z` and
   `git push origin :refs/tags/tuner-vX.Y.Z`), commit the bump, tag again.
5. Pull the image, open Settings, and check the bottom line reads `WEB TUNER X.Y.Z · DOCKER`.

## tvOS release

1. Do the build-number check above, then bump `MARKETING_VERSION` /
   `CURRENT_PROJECT_VERSION` in both config blocks.
2. Update `Nostalgex/APP_STORE_METADATA.md` with the release notes for this version.
3. Re-read `Nostalgex/PRIVACY_POLICY.md` and `privacy.html`. If the release changed what
   data the app touches, both have to say so before submission.
4. Xcode → Product → Archive → Distribute App → App Store Connect.
5. Wait for processing, confirm the build shows up in TestFlight, then submit for review.

---

## Pre-release checklist

- [ ] Latest build number read from App Store Connect / TestFlight, not from memory
- [ ] `MARKETING_VERSION` + `CURRENT_PROJECT_VERSION` updated in **both** config blocks
- [ ] `content/changelog.json` entry added
- [ ] `npm run changelog:render` and `node scripts/render-lineup.mjs` both run
- [ ] `Nostalgex/APP_STORE_METADATA.md` updated
- [ ] Privacy policy still matches what the app does
- [ ] Site deployed and loading
- [ ] Archive uploaded and visible in TestFlight
- [ ] Tagged

---

## Tags

Releases have not been tagged, which is a big part of why the build numbers got confused.
Tag every uploaded build, right after the upload succeeds:

```
git tag -a v1.0.11-build27 -m "Nostalgex 1.0.11 (build 27)"
git push origin v1.0.11-build27
```

Format: `v<MARKETING_VERSION>-build<CURRENT_PROJECT_VERSION>`.

One tag per build that actually reached Apple. A build that was committed but never
uploaded does not get a tag, so `git tag --list 'v*-build*'` stays an honest record of
what Apple has. Web-only deploys do not get tagged.
