# Dev log

Why things changed, and what state they were left in. Newest first.
Commits carry the detail of *what*; this carries the *why*.

## 2026-10-13 (web tuner: controls behind one menu on touch)

**Shipped.** Nothing. The work is on the branch `web-tuner-drawer`, not merged.

**Changed.** Testing the new touch layout on a phone, the owner's verdict was
that the guide and the video are the two things that matter and the controls are
not: in landscape the vertical rail ate a column of the screen and left about
two guide rows visible, and in portrait the controls cost a row from the bottom.
So on touch there is no control surface on screen at all. One MENU button sits
in the top right, and every control lives behind it.

- The drawer is a sheet from the right, `min(300px, 84vw)` wide, full height,
  over a scrim. Right rather than bottom because the same sheet then works in
  both orientations: at 393px wide it covers three quarters of the screen, and
  at 393px tall all seven boxes still fit without scrolling. It holds SOUND,
  FULL SCREEN, RETRO, SETTINGS, INSTAGRAM and BUY ME A COFFEE. SETTINGS opens
  the config screen that already existed. The coffee box is the only warm one;
  everything else is the toolbar's cyan.
- It dismisses by the close box, by a tap anywhere outside it, and by Escape,
  traps Tab inside while open, and returns focus to the MENU button on close.
  Opening it only moves a panel: `pause()` and `load()` call counts and the
  video's `currentSrc` are unchanged across an open, so playback carries on
  behind it.
- Every other key falls through, so M, F, B and H still work with the drawer
  open as well as on desktop.
- Landscape phones get no top bar either. A bar would cost 48px of the 393
  available, so the MENU button floats in the top right corner over the
  letterboxed black beside the video and takes no layout height. The video row
  gives up 62% to 55% of the height, which is the only place extra guide rows
  can come from in landscape: the 84px the rail held was horizontal, and the
  video there is height-limited, so it could not use the width anyway.
- Tablet landscape: the guide cap went from 44% to 50%, so the 56px the bottom
  bar gave up goes to the guide rather than to the video row, which is already
  as tall as the panel beside it allows.
- Portrait phones under 560px: guide rows go 34px to 32px. The screen is all
  guide now and one more channel fits.
- The closed drawer is parked off the right edge, which widens the document and
  leaves the page scrollable sideways. `body` already clips; `html` does not, so
  it gets `overflow-x: hidden` in the touch blocks.

**Measured.** Channel rows fully visible in the guide, before and after, driving
the built `dist/` in headless Chromium against a fixture library:

| Viewport | Before | After |
|---|---|---|
| iPhone portrait 393x852 | 10 | 11 |
| iPhone landscape 852x393 | 2 | 3 |
| Android portrait 360x800 | 9 | 10 |
| iPad portrait 834x1194 | 11 | 12 |
| iPad landscape 1194x834 | 8 | 10 |
| Desktop 1440x900 | 8 | 8 |
| Desktop 1280x720 | 6 | 6 |

The guide's scrolling body grew 52px in portrait, 52px on iPad portrait, 28px on
a landscape phone and 25px on iPad landscape. No horizontal scrolling at any
size (300px of it before the `overflow-x` fix). Every control in the drawer is
at least 44px in both dimensions.

**Desktop is untouched**, and that was checked rather than assumed: a dump of
every rendered element's box, display, colour and font size at 1440x900,
1280x720 and 1100x900 is identical before and after, apart from the playback
progress bar's width and the VHS tracking line's position, which both move with
the clock. The new nodes are all `display: none` 0x0 boxes there. The rail, its
keyboard hints and the short-window height tiers are unchanged; the new
landscape rules are gated on `pointer: coarse`, so a short desktop window keeps
the rail it had.

**Half-done.** Branch `web-tuner-drawer`, one commit on top of
`8f74c78`. Not merged, and `main` has moved since it was cut.

**Unverified.** Headless Chromium only. Not tried on a real phone, in Safari, or
with a real `env(safe-area-inset-*)`, so the home indicator clearance in
portrait and the notch clearance for the floating button in landscape are
reasoned from the CSS, not seen. VoiceOver was not run against the drawer.

**Next.** Merge with the two other web tuner branches in flight, then look at it
on a phone.

## 2026-10-13 (web tuner: iPhone had no inline playback)

**Shipped.** Nothing. The work is on the branch `web-tuner-ios-playback`, not
merged.

**Changed.** On iPhone the web tuner never played. Tapping a channel threw
playback into the native fullscreen player, and leaving that player left a
frozen frame with the schedule running on without it. One root cause: the
player element was `<video id="plex-video" autoplay muted>` with no
`playsinline`. iOS does not allow a video without that attribute to run inline
at all, so every `play()` the schedule made was refused and the native player
was the only place the picture could appear. A landscape screenshot from a
phone showed the end state exactly: the video inline but paused, iOS's own
transport overlay on top of it (iOS draws that on a video it will not play
inline, even with no `controls` attribute), the native scrubber reading a real
position and duration, and the tuner's info panel counting on past it.

Measured before the fix, in WebKit under a shim of Apple's two documented
iPhone rules (no inline playback without `playsinline`, and no element
fullscreen API): on one channel tune, `playsInline` false, `paused` true,
`readyState` 4 with the stream loaded and seeked to the schedule offset, one
rejected `play()` and zero successful ones. After the fix, same harness: zero
rejections, `paused` false, `currentTime` advancing, and no fullscreen call
anywhere in the tune path.

Three more things were found that would each have kept the picture dead, and
are fixed in the same change:

- A refused `play()` logged "Autoplay blocked" and gave up, so once the browser
  said no there was no route back short of a reload. Playback now retries on the
  viewer's next tap or key, one armed listener at a time, and disarms when the
  channel moves on.
- Nothing listened for `webkitendfullscreen`. iOS pauses the element when its
  native player closes, so even a viewer who got playback going through that
  player came back to a still. Measured: paused after leaving, `currentTime`
  frozen. It now resumes inline from inside the dismissal gesture, and
  measured after the fix the clock keeps running.
- `toggleFullscreen` called `container.requestFullscreen()` unguarded. That API
  does not exist on iPhone in any spelling, so the FULL SCREEN control threw a
  TypeError on every tap. It now feature-detects and falls back to the video
  element's own `webkitEnterFullscreen`, which is the only fullscreen iOS
  offers. The Jellyfin subtitle gate and the G-key overlay were keyed off
  `document.fullscreenElement`, which is also undefined on iPhone; both go
  through one `isVideoFullscreen()` helper now, so captions work in the native
  player too.

`scripts/web-tuner-player-smoke.mjs` asserts all of it against the source and
runs in `npm test`. It fails on the pre-fix file with 9 failures, so the
attributes and the recovery paths cannot quietly disappear again.

**Half-done.** Branch `web-tuner-ios-playback`. Not verified on a real iPhone:
real iOS was not available to the agent that made the change, and the
forced-fullscreen rule is iOS-only, so desktop WebKit cannot reproduce it. What
was run is desktop WebKit and Chromium at phone viewport with a real H.264/AAC
MP4 served to the direct-play path, plus the shim described above. Someone with
an iPhone should open the tuner, tap a channel, and confirm the picture starts
in the guide with no fullscreen transition, that FULL SCREEN opens and closes
without killing playback, and that playback is still running after closing the
native player.

The Apple TV app is untouched by this. It plays through AVPlayer natively and
shares no code with the web player.

**Next.** The iPhone confirmation above. The branch touches only the player and
fullscreen code, so it should merge cleanly alongside the touch chrome work on
`web-tuner-screens` and `web-tuner-drawer`.

## 2026-10-13 (web tuner: server picker and first-run build screen)

**Shipped.** Nothing. The work is on the branch `web-tuner-screens`, not merged.

**Changed.** The two screens a new phone user meets before the guide ever
appears. Both were reported from a phone on the live site, and both reproduced
in a headless browser at 393x852 against stubbed plex.tv resources and a fixture
library, so the numbers below are measured rather than guessed.

Server picker:

- The column was a hard `width: 500px` inside an unpadded `.plex-connect`, so at
  393px it was 447px wide starting at x -53. The row checkbox sat off the left
  edge of the screen, which is why you could not tell what was selected, and the
  page scrolled sideways. The column is `min(500px, 100%)` now and the connect
  screen has gutters plus safe-area padding, scrolls when a long list does not
  fit, and caps the wordmark, which used to render 560px wide on a 393px screen.
- A row's address is around 80 characters of plex.direct hostname. It was
  ellipsised mid-hash and took most of the row's height for no information. On
  touch a row is now the name, a tick and short badges (SHARED, LOCAL, REMOTE,
  RELAY, OFFLINE), with the addresses behind a SHOW ADDRESSES toggle that wraps
  them in full for anyone diagnosing a connection. OFFLINE comes from the
  `presence` flag plex.tv already returns, which is now carried through
  discovery; before this the picker gave no hint that a server could not be
  reached until after CONNECT.
- Selection reads at a glance: a cyan border, a cyan inset edge down the left
  and a 26px tick. Rows are at least 60px, CONNECT is full width and 52px.
- Pointer screens are untouched. The badges and the toggle are display:none
  outside the touch media queries, and the inline "(shared)" suffix and the
  always-visible address stay exactly as they were on desktop and TV.

First-run build screen:

- The panel is `inset: 0` inside `.video-container`, which the portrait rules
  size to a 16:9 box. Measured at 393x852: a 221px tall box holding 510px of
  content. The coffee block fell off the bottom, the step rail and the progress
  bar were stranded, and the remaining two thirds of the screen was empty black,
  which read as broken rather than as working. While `.building` is set there is
  no video and no guide, so the container now takes the whole screen on touch.
  `position: fixed` was tried first and does not work here: the retro flicker
  animation puts a transform on `.video-container`, which makes it the
  containing block for fixed descendants, so fixed resolved to the same 221px.
- The status content is one bordered card (hint, steps, headline, status line,
  progress) between the wordmark and the coffee ask, rather than five things
  floating in a column. The card wrapper is `display: contents` on pointer
  screens, so the desktop and TV stack is unchanged.
- Step labels no longer truncate. They were equal-width columns at 10px, which
  cut CHANNELS to CHANNE... at 393px and LIBRARY as well at 360px. Each step now
  takes the width its label needs and the connectors take the rest, at 8px.
  Checked with the five-step rail (the music bundle adds a phase) at 360px.
- The progress rail is the width of the card and 10px tall with the count under
  it, so it has a job. The second line was printing the same "Section 2 of 4"
  caption as the bar, and for the scanning phases the same detail as the
  headline; it now shows what the phase is doing instead. That one is in
  `scripts/nostalgex-library-load.js` and so applies on desktop too.
- Retro mode pins the empty video element to 4:3 off its height. With the
  container full screen that was wider than the screen (1137px of page at 393px
  of viewport), so the video is constrained while `.building` is set. No
  playback rule was touched.

**Measured.** Headless Chromium at 393x852, 852x393, 360x800, 834x1194,
1194x834 and 1440x900, on six states each (sign-in, PIN, picker, picker with
addresses, scanning, music enrichment): no horizontal scroll, nothing outside
the viewport on either edge, no truncated text, and every row, toggle and button
at 44px or more. Desktop is byte-for-byte the same layout it was, bar the
status line wording. `npm test` and `npm run build` pass.

**Half-done.** Branch `web-tuner-screens`, not merged. Not tried on a real
phone and not in Safari: Chromium only. The `safe` keyword in
`justify-content: safe center` and `display: contents` both want a look on
iOS Safari. Unrelated and untouched: the picker's Enter handler calls
`selectServer()`, which does not exist in the file, so keyboard selection in the
picker throws. Another branch, `web-tuner-ios-playback`, is editing the video
element and fullscreen in the same file.

**Next.** Look at both screens on a real iPhone before merging, in portrait and
landscape, and in particular check that the build screen fills the screen under
Safari's shrinking toolbar.

## 2026-10-13 (page media, blog images, legal holds lifted)

**Shipped.** The channel guide went live: `/channels` plus 14 bundle pages, the
new hand written titles, and every bundle name in the home page lineup linking
to its page. Sitemap resubmitted to Search Console. The Tunarr and ErsatzTV post
is live, a day later than scheduled.

**Changed.**

- `scripts/site-media.mjs`, shared by the blog and the guide. Every image
  carries width and height so nothing shifts while it loads: a file in this repo
  is measured at build time (png, jpeg and webp headers, no new dependency), and
  a remote file is measured once by `npm run media:measure` into
  `scripts/media-sizes.json`. The build reads that file and never touches the
  network, so a deploy does not depend on the bucket answering, and a new remote
  image fails the build until it has been measured.
- Every image needs real alt text or the build fails. Alt text and a clip's
  aria-label now feed the guide's copy checks, so a dash or a held name in alt
  fails the same way it does in body copy.
- Blog posts take `cover`, `og_image` and inline markdown images, which render
  as lazy loaded figures with the markdown title as the caption. Bundle pages
  take the same fields plus an optional `clip`. Clips are muted, looping and
  poster backed, started by app.js when they scroll into view, left paused under
  reduced motion or Save Data. `og:image:width` and `og:image:height` are now
  emitted for any card, not only the shared default.
- Seventeen images across all seven posts, three live and four drafts, served
  from the media bucket rather than committed: this repo is public and the
  captures are frames from films. Measured sizes matched what the retrofit
  documented (covers 1200x630, grid crops 1280x412, guide crops 1280x565).
- Fixed the markup a standalone image produced. marked wraps it in a paragraph,
  and a figure inside a paragraph makes the browser close the `<p>` early and
  leave an empty one behind.
- **The legal holds are lifted.** Chad cleared the brand and franchise channel
  names for publication, for now. All 14 bundles are indexed, all 131 channel
  names are printed, the sitemap went from 11 URLs to 15, and llms.txt lists
  every bundle. The brand word list moved out of `build-bundles.mjs` into
  `scripts/legal-hold.json`, so that one file decides what is held: bundles,
  channels and words. The former lists are kept in the same file under
  `releasedBundles`, `releasedChannels` and `releasedBrands`, so putting a hold
  back is a copy from one list to another and a rebuild.
- The affiliation disclaimer now renders on every bundle page rather than only
  the held ones. A page that prints a studio or franchise channel name is the
  page that needs it.

**Half-done.** The four bundles that were held (Kidz Zone, Franchises, Networks,
Arthouse) still carry the deliberately generic intros written while they were
noindex: they never name their own channels. They are accurate and they are safe
if the holds go back on, but they read vaguely for pages that are now indexed
and could name what is on them. Rewriting them is the obvious next copy job.
Bundle pages have no images yet beyond the hub, which reuses the home page
lineup screenshot; six bundles have no usable capture at all (sports, true
crime, arthouse, Christmas, music videos) and Christmas wants a November capture
with holiday titles in the guide.

**Next.** Decide whether the four generic intros get rewritten now that the
names are published. Request indexing for `/channels` once Google has refetched
the sitemap: the Indexing API submission failed with "Insufficient Permission",
so that is a service account and API enablement job in Google Cloud before it
can be scripted.

## 2026-10-13 (web tuner: phones and tablets)

**Shipped.** Nothing. The work is on the branch `web-tuner-mobile`, not merged.

**Changed.** The web tuner had no real phone layout. Measured on a 393x852
viewport, the video element rendered 393x0: the side layout put the info panel
and the 140px toolbar in a column, they used the whole 650px video row, and the
picture got nothing. The toolbar also overflowed its row on a 852x393 landscape
phone and on an iPad, so the Instagram link was cut in half.

The touch layouts now follow the shape already shipped on another product of
Chad's: a slim top bar, the video first and edge to edge, the now-playing line
compacted under it, the guide taking the rest, and the controls as a bar across
the foot of the screen.

- Portrait up to 1024px: the video is `order: -1`, full width, `aspect-ratio:
  16 / 9`. The info panel sits under it with the description hidden, the title
  clamped to two lines and the episode line to one. The guide fills what is
  left. Measured on 393x852: video 393x221, info 115, guide 416, bar 56.
- The toolbar becomes a fixed bar, `calc(56px + env(safe-area-inset-bottom))`
  tall, six equal columns divided by hairlines, with
  `padding-bottom: env(safe-area-inset-bottom)` so it clears the home
  indicator. `.player-screen` gains matching padding so the guide is never
  underneath it.
- Six controls, not seven. The App Store link is dropped on touch rather than
  moved: it points at a tvOS app, and nobody installs one of those from a
  phone (owner's call). The top bar carries the wordmark and nothing else. The
  coffee box keeps its warmth as a yellow wash and yellow type rather than a
  solid slab, and loses the desktop glow, which is far too much at this size.
- Desktop, short windows: the rail is centred, so once Instagram joined it the
  content outgrew the video row and clipped SOUND at the top and Instagram at
  the bottom. Measured 20px over at 1280x800 and 30px at 1440x760. Three
  height tiers tighten the padding and gaps, and the rail scrolls from the top
  (`justify-content: safe center`) rather than clipping if it ever does not
  fit. Re-measured at 1280x650 through 1920x1080: nothing clipped anywhere.
- Keyboard hints are gone from touch labels. `[M]` and `[F]` mean nothing on a
  phone, so each button carries a second short label that the touch layouts
  swap in. Desktop keeps the hints.
- Landscape phones (`max-height: 500px`) keep a vertical rail, because height
  is the scarce dimension there and a bottom bar would cost 56px of 393. The
  rail is now pinned to the left edge over the full height instead of being
  confined to the video row: inside the row its six controls were 35px tall,
  under the 44px a thumb needs, and the last one was clipped. Pinned, they
  measure 71x60.
- Tablet landscape keeps the side layout, since it is a good use of the width,
  but loses the 140px toolbar column to the bottom bar and has its type
  compacted. On 1194x834 the video went from 636 to 788 wide.
- Two text bugs that were visible at tablet width: the fixed corner wordmark
  printed on top of the channel tag (the top bar carries the mark now, and the
  corner one is hidden on touch), and `.info-channel-tag` had no line-height,
  so a tag wrapping to two lines printed them over each other in the pixel
  font. Grid header times get `white-space: nowrap`; they were wrapping out of
  the fixed 32px header into the rows below.

Nothing outside a media query changed, so desktop and TV are untouched. Checked
by measurement at 1440x900: video, info panel, toolbar and guide boxes are
identical before and after, and the toolbar still shows seven controls with
their keyboard hints.

**Half-done.** Branch `web-tuner-mobile`. Verified only in headless Chromium at
393x852, 852x393, 360x800, 834x1194, 1194x834 and 1440x900, driven against a
synthetic fixture library. Not tried on a real phone or tablet, and not in
Safari, which is where `env(safe-area-inset-*)`, `aspect-ratio` and sticky
`:hover` after a tap actually matter. The hover-after-tap guard is written but
unproven on a real iOS device. The video element was black in every shot
because the fixture has no media, so the 16:9 box is confirmed by measurement
rather than by picture.

**Next.** Chad to open the branch on a phone and an iPad before it merges.

## 2026-10-13 (web tuner: Instagram in the toolbar)

**Shipped.** Nothing yet. On main, goes out with the next deploy.

**Changed.** The player toolbar has an Instagram link under Buy Me a Coffee
(`instagram.com/nostalgex_`). It wears the toolbar's own shape rather than the
coffee box's, so the yellow one stays the only button that asks for something.
Checked in a headless browser: the link opens in a new tab with
`rel="noopener noreferrer"`, and nothing else in the toolbar moved.

**Next.** The loading screen's coffee call to action has no Instagram link. Leave
it or match it, owner's call.

## 2026-10-13 (collections that hold shows, on a branch)

**Shipped.** Nothing yet. Branch `collections-with-shows`, merged into main for the next build.

**Changed (on the branch).**

- A server collection of TV shows now becomes a channel, on the Apple TV and the web
  tuner. A Plex collection, or a Jellyfin or Emby BoxSet, can hold shows, and the scan
  threw them away in three places: it read collections from movie libraries only (a Plex
  collection of shows lives in the TV library, so it was never listed), Jellyfin and
  Emby asked the BoxSet for `Movie` only, and the children were matched against an index
  of films only. A collection with fewer than 3 films was then skipped, so a collection
  of shows always read as empty.
- The fix leans on what the library load already holds: every episode of every show.
  Episodes now carry their show's id (`showKey`: Plex `grandparentRatingKey`, Jellyfin and
  Emby `SeriesId`), and a show in a collection expands to its episodes. No extra request.
  A films-only collection is matched, classified, numbered and labelled exactly as before.
- The three servers answer differently, measured: Plex lists the shows (a Plex
  collection is all films or all shows; Plex refuses a film in a TV collection with a
  400). Jellyfin 12.2 lists the series for `IncludeItemTypes=Movie,Series`. Emby 4.10
  answers the same query with the series' episodes. The matcher takes a film id, an
  episode id or a show id, so all three work, and Emby works even on items restored from
  an older snapshot.
- The channel is built and scheduled by the existing code. Episodes are shuffled within
  each show and shows are interleaved two at a time, the same `interleaveByShow` the TV
  channels use. A mixed collection airs its films and its shows' episodes together.
- A collection of shows always lands in OTHER COLLECTIONS. Every episode carries its
  show's title, so the repeated-word rule would have called one show with 30 episodes a
  franchise. A mixed collection is classified on its films alone, which is what the
  films-only scan did. A collection holding shows folds into a franchise only when that
  franchise already airs an episode of each of its shows, so folding never hides episodes.
- No snapshot format bump. `showKey` is an optional field; collection members were
  already stored as indexes into the item list, episodes included. Items restored from a
  snapshot written before this have no `showKey`, so a Plex or Jellyfin collection of shows
  appears after the next library scan rather than at once.

Measured on a real Plex server with a temporary three-show collection (since deleted):
every episode came back with its show key, the old matcher found 0 films and skipped the
collection, and the new scan built it at CH 500 with every episode of the three shows and
a full 24 hour schedule, on the Apple TV code (`LiveCollectionShowsHarness`) and on the
web tuner driven headless, in the same order on both. On the same server every films-only
collection came out identical to the old scan: same members, same fold, same channel
numbers, checked against the old matcher on the Apple TV side and against main's
`nostalgex-collections.js` on the web side. Jellyfin 12.2 and Emby 4.10 lab servers with
synthetic media: a shows-only BoxSet and a mixed one, both skipped before, both built
after (web tuner on the Jellyfin lab only; it has no Emby path).

NostalgexTests: 684 passed, 0 failed, 9 skipped (668 before, plus 16 in
`CollectionShowsTests`; the new live harness skips without a server). `npm test` and
`npm run build` green; collections smoke went from 38 to 55 checks.

**Half-done.** Not on hardware. Not measured against a Jellyfin older than 12.2, which
may answer the BoxSet query like Emby (episodes); the matcher accepts both. The web tuner
has no Emby path, so Emby collections are Apple TV only, as before. A Plex or Jellyfin
collection holding seasons or single episodes rather than whole shows is not handled:
a season key matches nothing.

**Next.** Chad to decide whether to merge. Before release, check one real collection of
shows on an Apple TV, and decide whether a collection dominated by one long show should
interleave differently: once the shorter shows run out, `interleaveByShow` plays the long
one back to back, which is what a TV channel with the same pool does today.

## 2026-10-13 (Jellyfin and Emby: the stall retry replayed the file that stalled)

**Shipped.** Nothing yet. Branch `jellyfin-stall-transcode`, merged into main for the next build.

**Changed.**

- The question left open in the entry below is answered: it was real. When direct play
  gave no picture (watchdog) or starved (starvation ladder), Apple TV asked Jellyfin or
  Emby's PlaybackInfo the same question as the first attempt. For a file the server can
  direct play, the answer is the file. Measured on an 8-bit H.264 MP4 against a local
  Jellyfin 12.2.0 and an Emby 4.10.1.0 server: `SupportsDirectPlay=true`, no
  TranscodingUrl, so `JellyfinPlaybackResolver.resolve` returned `stream.mp4?Static=true`
  and the ladder played the same file again (206, `video/mp4`) under the transcode label.
- What that cost: not a dead end, a wasted rung. By the watchdog's own deadlines, the
  replay got the transcode deadline (20s, 40s for 4K) or a second stall window before
  the 1080p capped rung, so a black picture lasted 15s plus 20 to 40s more, and a
  starving film had to starve twice.
  An MKV was never affected: it does not direct play, so PlaybackInfo always handed back
  HLS. Plex was never affected: its transcode request is always HLS.
- Fix: the retry goes through a new `resolveServerStream`. It sends PlaybackInfo with
  `EnableDirectPlay=false` and `EnableDirectStream=false`, and the resolver never returns
  the static file on a retry (it returns nil, and the service falls back to its
  hand-built HLS stream). Both flags are needed. With only `EnableDirectPlay=false`,
  Jellyfin returns a TranscodingUrl but Emby reports `SupportsDirectStream=true` and
  still none.
- After, with the branch's own body builder and resolver: the retry gets a `master.m3u8`
  TranscodingUrl on both servers (reason `DirectPlayError`), and master, variant, init
  and segments 0 to 2 all answer 200, for the MP4 and the MKV. For the MP4 it is a remux:
  video and audio copied into HLS (Jellyfin's ffmpeg log `codec:v:0 copy`, Emby's session
  `IsVideoDirect` and `IsAudioDirect` true). The first attempt sends exactly the three keys it sent before and still
  direct plays the MP4.
- Web tuner: not affected and unchanged. Its only retry is after a direct play errors,
  and for an MP4 it gets no TranscodingUrl and uses the hand-built HLS fallback, which
  walked 200 on both servers. It has no stall ladder: a stall skips after 8s.
- Tests: `StallRetryServerStreamTests` (10): request body on first attempt and retry,
  both services' requests, the resolver on each measured answer, the offline fallback,
  and Plex unchanged.

NostalgexTests: 682 passed (672 on the branch point plus the 10 new), 0 failed, 8 live
harnesses skipped. `npm test` and `npm run build` green.

**Half-done.** Proven at the HTTP level, not watched on an Apple TV: no forced
no-picture or starvation has been run through the ladder on a device. The forced server
stream is a remux at the same bitrate: it changes the container, not the video or the
bitrate. A file whose video the device cannot decode, or a link too slow for the file,
still depends on the 1080p rung after it, which was not re-measured here.

**Next.** On an Apple TV against Jellyfin or Emby, force a direct-play stall on an MP4
and check the diagnostics line reads "server stream" then plays HLS, not the file.

## 2026-10-13 (Emby fallback stream: every segment refused for want of a PlaySessionId)

**Shipped.** Nothing yet. Branch `emby-playsessionid`, merged into main for the next build.

**Changed.**

- On Emby, the HLS stream Nostalgex builds by hand after a failed direct play never
  played, on Apple TV or in the web tuner. Measured against a test Emby 4.10.1 server on
  8-bit H.264 MKV and MP4 files: master and variant playlists 200, then the init segment
  and segments 0 to 2 all HTTP 400 "Value cannot be null. (Parameter 'key')". Emby writes
  each segment URL as `hls1/main/0.mp4?PlaySessionId=<id>` and nothing else, taking the
  id from the master request. The hand-built master had none, so every segment asked for
  `PlaySessionId=` with no value. Jellyfin copies the whole query string onto segments,
  which is why the same URL plays there.
- Where it bites: a direct play that fails. The web tuner's retry asks PlaybackInfo,
  which returns no TranscodingUrl for a file Emby thinks the browser can play (measured),
  so it falls back to the hand-built URL. Apple TV's `.failed` fallback uses the
  hand-built URL directly, as does any PlaybackInfo request that errors. PlaybackInfo's
  own TranscodingUrl and the 1080p capped rung already carried an id and played.
- Fix: the hand-built URL carries a client-made `PlaySessionId`. Apple TV:
  `EmbyAPIService.buildTranscodeURL(for:sessionID:)`, and the id is tracked so a channel
  change stops that encode, as it does a PlaybackInfo session. Web:
  `NostalgexJellyfinUrls.fallbackHlsUrl`, a UUID where the browser has
  `crypto.randomUUID`, else 32 hex characters (a self-hosted tuner over plain http has
  no secure context). Leaving the parameter off is not an option: it already was off,
  and Emby writes the empty one itself.
- After: master, variant, init and segments 0 to 2 all 200 on the same Emby server, for
  the URLs the Apple TV code builds (both fallback paths, both files) and the URLs the
  built web tuner builds (both id shapes).
- Jellyfin: the Apple TV Jellyfin code is unchanged. The web tuner signs in to Emby as
  Jellyfin and shares one fallback, so that change reaches Jellyfin too. On a local
  Jellyfin 12.2.0 the hand-built URL was all 200 before and is all 200 with the id.
- Tests: `EmbyPlaySessionTests` (4) and 8 new checks in `test:jellyfin-urls`.

NostalgexTests: 672 passed (668 on main plus the 4 new), 0 failed, 8 live harnesses
skipped. `npm test` and `npm run build` green.

**Half-done.** Proven at the HTTP level (playlist and segment statuses), not watched on
an Apple TV or in a browser. The web tuner still never stops a Jellyfin or Emby encode
on channel change (`stopActiveTranscode` returns early for them), so the web id is not
yet used for cleanup.

**Next.** Watch one forced direct-play failure on an Apple TV against Emby. Worth a
measured look: when direct play gives no picture or starves, Apple TV asks PlaybackInfo
for the server stream, and for a file the server calls direct-playable
`JellyfinPlaybackResolver.resolve` returns the same static file rather than an HLS
stream. Seen in the PlaybackInfo responses above, not yet on a device.

## 2026-10-13 (membership generator keeps the cleanup)

**Shipped.** Nothing. Branch `membership-generator-rules`, merged into main.
`channels-memberships.json` on main is untouched.

**Changed.**

- The 2026-10-12 memberships cleanup (5,154 to 4,898 entries) was applied to
  the shipped file by hand, and the keyword tuner only knew the first of its
  three rules. The next regeneration would have put 22 horror-only titles back
  on SCI-FI and dropped 20 real musicals. The tuner now carries all three:
  - Genre gate (cherry-picked from `membership-genre-gate`): recommendation,
    similar and collection claims must match the channel's `genres.include`.
  - `genres.requireAll` from channels.json gates the same claims. SCI-FI's
    Science Fiction is the one that bites. ROM COMS and GIRLS NIGHT opt out
    with `gateRequireAll: false` in exemplars.json, as decided on 2026-10-12;
    applying it there would take 83 and 19 titles off. DATE NIGHT and TRUE
    CRIME also carry requireAll and lose nothing extra to it today.
  - MUSICALS `genreRescueKeywords`: musical, song and dance, broadway. Not
    "based on play or musical", which would add 10 plays (Roxanne, Cyrano de
    Bergerac, On Golden Pond), and not "singing".
- The rule data lives in exemplars.json, the generator's input. channels.json,
  the Swift app and the web filter are unchanged: a manifest claim bypasses
  include and requireAll at runtime, so gating is the generator's job alone.
- `--cache <file>` keeps every TMDB response on disk and `--out <dir>` writes
  somewhere other than the shipped files. A rerun from the cache with no
  network gave the same file apart from the timestamp.
- `npm run test:tuner-gate` (24 checks, in `npm test`) runs the rule function
  against the real rule data. Removing the rescue list, adding the plays
  keyword, dropping the ROM COMS opt-out or ignoring requireAll each fail it.

How it was checked:

- Replaying the cleanup over the pre-cleanup file with the generator's rule
  function gives the shipped content exactly: 4,898 items, 5,593 title and
  channel pairs, every field equal. Not byte-identical, because 5 items list
  their channels in another order and the rescued musicals sit at the end of
  the file, both left by the two-step hand edit. TMDB genres had not changed
  on any of 2,830 titles between 10-12 and today.
- A full live regeneration today gives 3,737 items: 2,146 pairs only in it,
  3,057 only in the shipped file. A control run with the gate off, on the same
  cached TMDB data, accounts for all but one pair:
  - 1,320 STAND-UP claims come from `discover-standup.mjs`, not from the
    tuner, so a full regeneration has to rerun it afterwards.
  - The rest is the candidate set moving: TMDB recommendations, similar lists
    and search matches, and exemplar lists edited since a channel was last
    generated (MIDNIGHT, CULT CLASSICS and BIOPICS each gain 110 to 150). The
    gate-off control differs from the pre-cleanup file by 2,542 and 3,598
    pairs on its own.
  - The one rule difference is Heat on MYSTERY. The hand cleanup gated by each
    entry's single source label, and Heat's says exemplar (it is one on
    another channel), so its MYSTERY claim was never checked. The tuner gates
    per claim, and Heat (Crime, Drama, Action) misses MYSTERY's Mystery rule.
  - No pair the cleanup removed comes back.

**Half-done.** The regenerated file is not committed: it would change about
5,200 title and channel pairs for reasons that have nothing to do with these
rules. Swift tests were not run, since nothing the app reads changed.

**Next.** Chad reviews and merges `membership-generator-rules`; it supersedes
`membership-genre-gate`. Whether to regenerate the shipped memberships at all
is a separate call, and if so, `discover-standup.mjs` runs after the tuner.

## 2026-10-13 (channel guide pages)

**Shipped.** Nothing. Branch `seo/bundle-pages`, draft PR, waiting on Chad's
review of the copy and a legal answer on the brand names.

**Changed.**

- New `/channels` hub and 14 `/channels/<bundle-id>` pages, generated by
  `scripts/build-bundles.mjs` from `channels.json` at build time, so counts and
  channel names cannot drift from the app. Intros (300 to 600 words) and 5 FAQs
  per bundle are hand written in `content/bundles/<id>.md`.
- `scripts/legal-hold.json` holds the four bundles whose channels are all brand
  names (franchises, streamers, kids, arthouse) plus 31 individual channels.
  A held bundle still builds, at `noindex, follow` with an affiliation
  disclaimer, and stays out of the sitemap and llms.txt. A held channel name is
  omitted from every indexed page, including JSON-LD, and the list ends "plus
  {n} more channels in the app". Counts stay true: 131 channels, 14 bundles.
  Deleting an entry from that file releases it on the next build.
- Build checks that fail the build: a dash of any kind in visible copy, a held
  brand name on an indexed page, an intro outside 300 to 600 words, a duplicate
  or over length title or meta description, "Emby" anywhere in the generated
  pages, a banned marketing phrase, and the hard coded 131 in plex.html
  drifting from channels.json. Each one was proved to fire against a scratch
  copy of the tree.
- Page chrome (nav, footer, head, theme boot) moved out of `build-blog.mjs`
  into `scripts/site-chrome.mjs`, imported by both generators. The blog header
  drifted from the global header once before; one copy now. Blog output is
  unchanged apart from the new footer link.
- Channel names on these pages render upper case, as on the homepage lineup and
  in the app. The only presentation change is dropping hyphens (SCI FI, STAND
  UP), because the dash check forbids them in visible copy. `channels.json` is
  untouched.
- `BUNDLE_STYLE` moved to `scripts/bundle-style.mjs`, shared with
  render-lineup.mjs, and gained the missing `tis-the-season` entry.
- Footers across the site link to the channel guide; /plex and /jellyfin each
  got one sentence pointing at it.

**Half-done.** Not measured in Rich Results Test or Lighthouse yet, and not
seen on a Vercel preview. The guide pages drop the Emby footer link to satisfy
the no Emby rule, which leaves /emby live but unlinked from them: that
inconsistency is Chad's call, along with whether /emby stays in llms.txt and
the sitemap at all. Channel pages (`/channels/<number>-<slug>`) are not built;
the channel list markup already carries `data-channel-number` for when they
are. The homepage lineup still does not link to the bundle pages.

**Next.** Chad reads the 14 intros and the legal flags. After merge, request
indexing for /channels in Search Console.
## 2026-10-13 (1.0.26 (48) cut)

**Shipped.** main pushed, which deploys the site and web tuner. Build 1.0.26 (48) archived
and uploaded to App Store Connect, not yet given to any tester group. Build 47 was uploaded
earlier today and will not be distributed; 48 carries everything 47 had plus the franchise
line, iCloud sync, Report Playback v2 and PRs #18 and #21. The 1.0.26 changelog entry stays
`"released": false` until the App Store has it.

**Changed.**

- iCloud sync, tested on two Apple TVs (a 4K 3rd gen and a 4K 1st gen) on one Apple ID.
  Two bugs found that way. Turning sync on used to push that TV's lineup up, so the second
  TV to join overwrote the first; now the first TV seeds iCloud and later ones take what is
  there. And each TV's launch wrote its own bundle list to iCloud (snapshot restore,
  collection categories), so whichever loaded last won; now only a toggle the viewer makes
  is sent. After both fixes: changes crossed in both directions in about a minute with no
  echo back, and both TVs relaunched with identical values.
- Every Settings choice syncs: Stream Quality and Report Playback joined the list. Server
  addresses, sign-ins and the sync switch itself stay on each TV.
- Settings: a package switched on shows BUILDING and "Finding N channels in your library"
  until its channels are in. Before, it read "Not enough content" and dimmed for the
  length of the build, which looked frozen.
- Two quick package toggles ran two builds at once and the second overwrote the first
  package's channels with its stale copy (`BundleBuildTests`: all 6 of the first package's
  channels lost). Builds now queue.
- Web tuner: guide footer drops the "[V] HIDE GUIDE" hint (no key ever handled it).

NostalgexTests: 668 passed, 0 failed. `npm test` green.

**Half-done.** Docker self-host stays on branch `docker-selfhost`, unpublished. It waits
for the web tuner to work well on a phone, since the container serves the same page.

**Next.** Decide TestFlight or straight to App Store review for 48. Attach the three tip
in-app purchases to the 1.0.26 App Store submission. Update the App Store listing copy and
screenshots for this version. Widen the privacy page's Continue Watching wording to cover
the Apple TV app once 1.0.26 is live.

## 2026-10-13 (Web tuner: guide wraps, Blacklist tab gone)

**Changed.** Branch `web-tuner-guide-wrap`, merged into main and live with the 1.0.26 (48)
push below.

- The web guide wraps at both ends. Down on the last channel goes to channel one, Up on
  channel one goes to the last. A wrap centers the landed row, which scrolls the guide to
  that end, so the seasonal invite above channel one shows again. Apple TV is not the
  same: Down on the last channel wraps, but Up on channel one goes to the seasonal row
  and then SETTINGS, on purpose (see `ChannelGuideView.swift`). Left/Right on the web
  and channel up/down on Apple TV already wrapped.
- Settings → Blacklist is removed, and the saved list with it. `plex90_blacklist` is no
  longer read, because titles hidden through a tab nobody can open would stay missing
  for good. The key is left in place in browsers that have one. The tab also trapped the
  keyboard: arriving on it focused its search box, and the tuner ignores keys while an
  input has focus, so Left, Right and Escape stopped working there.

**Verified.** Built site in headless Chromium, with a synthetic 5,000 item library seeded
into the tuner's own library cache (plex.tv and the server stubbed), so the real load path
built a 16 channel guide taller than its pane. Before: Down on the last row and Up on the
first did nothing. After: both wrap in both guide layouts, 35 presses with no pause land
on the right row, Enter after a wrap tunes it. With 300 saved blacklist entries, 0 of
those titles were in any pool before and 278 after, the same 278 a browser with no list
pools. `npm test` green. Not tried with a real server or on a TV browser.

Settings → Help said Up/Down change channel; Left/Right is what does, so Help now says so.

**Next.** Found while measuring, left alone. In fullscreen (F), Up/Down move the hidden
guide cursor and the channel does not change. The guide footer's [V] HIDE GUIDE hint is
gone; no key ever handled V, and the guide has no reason to hide.

## 2026-10-13 (Report Playback rebuilt on PR #18)

**Changed.** w6trp's #18 merged with their commit kept, then folded into the one REPORT
PLAYBACK switch. The owner's rule: report watching, never fill Continue Watching.

- Plex sends position-free timeline reports (#18's idea, PUT, no `time`/`duration`): Now
  Playing shows the title and its playing/paused/buffering state, Plex stores nothing.
  A qualifying watch scrobbles with the bare key; a counted episode's next-up entry is
  removed unless its show was already in Continue Watching. The Plex unscrobble and
  `/:/progress` restore and the film prior-state read are gone.
- Jellyfin/Emby keep the restore. Measured on Emby 4.10.1: position-free start bumps
  PlayCount, and a stop without `PositionTicks` marks the item played.
- From #18 also kept: AVPlayer state feed, background grace for the final stop, the
  `backgrounded` guard, the request-shape and pulse tests. Dropped: the second toggle
  and the reporter that switched the setting off after one failed request. Failures now
  skip pulses (1, 2, 4 ... 30) and never touch the setting.
- Same on the web tuner. Settings copy unchanged on both surfaces.

**Verified.** Live Plex, real tracker code: a 2 minute real-time surf on an unwatched film
showed in Now Playing at offset 0 throughout, cleared on stop, metadata and Continue
Watching (17) unchanged. A counted episode: viewCount 1, no resume point, no next-up
(checked again 5 s on; a control scrobble shows Plex adds one), then unscrobbled back.
Emby surf + counted watch: UserData and Resume back exact. NostalgexTests 662: 654
passed, 8 skipped (live harnesses), 0 failed. `npm test`, `npm run build` green. Not
tested on hardware.

## 2026-10-13 (PR #21 merged for the next build)

**Changed.** `land-pr-21` merged into `ship-franchises` with w6trp's commit kept: the
selected Plex media version and multipart offsets survive into playback. On landing it
kept the single-file snapshot at schema 2; main has since moved to the chunked format,
so the same rule now reads "no bump of `formatVersion` 3" for the new item fields.
`LibrarySnapshotCompatibilityTests` strips the #21 keys from a 1.0.26 chunk file and
from a legacy v2 file and proves both still load; it fails with the format set to 4.
`PlaybackTracker` keeps both `onPlaybackPreparing` (#21) and the background restore
(Report Playback); the rating nudge counter still attaches once per tracker.

NostalgexTests 657: 649 passed, 8 skipped (live harnesses), 0 failed. `npm test`,
`npm run build` green. Multi-version and multi-file playback still needs hardware.

## 2026-10-13 (Report Playback restore and OMDb relay merged for the next build)

**Changed.** `omdb-relay` (with `report-no-cw` and `web-enrichment` under it) merged
into `ship-franchises`. App side only in effect: `WatchStateGuard` restores each
program's prior state on leave, Plex scrobble uses the bare rating key, Emby and
Jellyfin UserData restore, `OMDBService` goes through the relay with the IMDb budget
and 429 day stop. Web conflicts (`plex-tuner.html`, `package.json`, `privacy.html`)
took main's live copies; main already carried the web side.

`privacy.html` still says only the web tuner keeps Continue Watching clean. Update it
to cover the Apple TV app when this build is live, not before.

NostalgexTests 650: 642 passed, 8 skipped (the 3 new `LiveContinueWatchingTests` need a
real server), 0 failed. `npm test`, `npm run build` green. Not tested on hardware.

## 2026-10-13 (franchise line merged for the next build)

**Changed.** `shared-franchises` merged into `ship-franchises` off main 1.0.26 (47).
Conflicts and how they went:

- `LibrarySnapshotStore`: main's chunked v3 format kept. Found franchises ride in
  `meta.json` as rows plus item indexes (`foundFranchiseRows`, `foundFranchiseMovieItems`,
  `foundFranchiseTVItems`), all optional so a 1.0.26 snapshot restores as nothing found
  yet with no rescan. `foldedIntoFranchise` travels on the collection row. Two new
  `LibrarySnapshotChunkedTests` cover both.
- `AppState+Library`: main's background save and index lookup kept, franchises passed
  through. `BundleManagerView` merged clean (RATE "thanks" copy kept).
- Web: main's `api/tmdb.js` (TMDB + OMDb relay, CORS) and smoke test kept; main already
  had the franchise builder, golden file and `franchises.json`.
- Siri stays removed.

NostalgexTests 616: 611 passed, 5 skipped, 0 failed. `npm test`, `npm run build` green.
Simulator smoke with `-uiTestFranchiseFixture`: FRANCHISES and FOUND IN YOUR LIBRARY
render, no NOTABLE STARS. Not tested on hardware.

**Watch.** The iCloud KVS entitlement comes in with this merge (sync is off by default).
The 10-10 entry showed a Release archive signs with it; still no two-TV hardware pass.

## 2026-10-12 (community PRs)

**Changed.** Two fixes from @w6trp landed on main with their commits kept, thanks:

- #19: watchdog verdicts strip URLs and credentials before they reach the system log or
  Settings, so a support screenshot can no longer carry a server token. Kept main's
  verdict line format (no em dashes) with the redaction applied to it.
- #20: music enrichment and channel pools key on the server-qualified item id, so two
  servers that reuse a rating key no longer swap each other's music metadata.

NostalgexTests 495 passed, 2 skipped, 0 failed; web tests green. Not tested on hardware.

**Half-done.** #21 (keep the chosen Plex media version and multipart offsets) is on
`land-pr-21`, not main. It touches playback, so it waits for a hardware pass on a
multi-version title and a three-part film. On landing we dropped its snapshot schema bump
(2 to 3); `LibrarySnapshotCompatibilityTests` proves a pre-#21 snapshot still loads.

## 2026-10-13 (app, build 47)

**Shipped.** 1.0.26 (47) uploaded to TestFlight for beta review. 1.0.25 (46) is still in
Apple's beta review since Oct 9; 47 is reviewed on its own.

**Changed.**

- Tip jar: three StoreKit 2 consumables (Popcorn, TV Dinner, Pizza Night), quantity 1 to
  5, unlocking nothing. Settings shows them as four pixel-art tiles with RATE.
- Rating banner after the third 10+ minute watch, once per version. On hardware the first
  version never received focus; it now uses default focus plus retries after the slide-in
  and lands on RATE. A RATE press stops it for good. tvOS offers no in-app review API.
- Large libraries: the library snapshot was JSON-encoded in one piece on the main thread,
  peaking at 2.6 GB for 400k items, so tvOS killed the app right after the guide appeared
  and the atomic write left no snapshot. It is now saved in 10k-item chunks off the main
  thread with a manifest swapped in last. Measured on an Apple TV 4K (3rd gen): killed at
  400k before, survives after (+26 MB over steady while saving).
- Plex film titles: `parseMovieItem` ran the music-video "Artist - Song" parser on every
  film, so titles with " - " lost their first half and "Spider-Man" became "Man". It now
  runs only for music videos, as the Jellyfin and Emby paths already did.
- Jellyfin direct play requests `stream.mp4`: Jellyfin labels `/stream` by the file name,
  so an MP4 saved as `.mkv` came back as Matroska and the player refused it. The fallback
  HLS URLs also carry `ApiKey`, which Jellyfin 12.2 requires when legacy authorization is
  off. Reproduced and verified on a local Jellyfin 12.2.
- Collection classifier: a collection whose name appears in 2+ of its film titles is a
  franchise.
- Community PRs #19 and #20 by @w6trp merged with their commits.
- Siri channel tuning was built and tested on hardware: tvOS 26 Siri does not hand App
  Shortcut phrases to the app. Removed from this build; parked on `siri-intents`.

**Half-done.** PR #21 waits on a hardware test. The 1.0.27 line (franchise bundle,
iCloud opt-in, enrichment in the app, Report Playback rebuilt on PR #18) is on branches.
Emby's fallback HLS still fails on an empty `PlaySessionId`.

**Next.** Watch 47 through beta review; hardware-test PR #21; start 1.0.27.

## 2026-10-11 (web tuner)

**Shipped.** nostalgex.app: the web tuner now reads the shared metadata cache, fills
misses through the TMDB relay, and builds server collections as channels. Report
Playback on the web no longer fills Continue Watching. No app release.

**Changed.**

- The web tuner never attached enrichment to items, so every enrichment-gated channel
  was empty or thin on the web. It now batch-reads the shared Supabase cache by TMDB id,
  looks up misses through `api/tmdb.js`, and writes them back. On a test library of about
  11,600 items: SPY GAMES 0 to 59, TOON TOWN 0 to 44, MUSICALS 43 to 57, TEEN MOVIES 14
  to 21, BIOPICS 13 to 18, MIDNIGHT 1 to 6, TRUE CRIME 0 to 1.
- Plex items on the web had no TMDB id at all (the scan never asked Plex for guids, and
  episodes did not inherit the show's id). Now about 90% carry one. Old library caches
  are refused once so browsers rescan.
- The relay accepts `X-Nostalgex-Client: web`, answers CORS preflight, and echoes the
  origin only for nostalgex.app, www and localhost:5173. Other origins are blocked.
- Server collections air on CH 500-699; ones that duplicate a stock franchise channel
  fold out.
- Report Playback: Plex never counted a Nostalgex watch, because `/:/scrobble` with
  `key=/library/metadata/{id}` returns 404; it now sends the bare rating key. On leaving a
  program the tuner puts it back the way the server had it (Plex: unscrobble, progress
  restore, or remove from Continue Watching; Jellyfin/Emby: PlayedItems and UserData
  restore). Verified live on Plex and Emby, Jellyfin against a local server.
- Privacy page: the web tuner's metadata lookups and the Continue Watching promise.

**Half-done.** The same enrichment, collections, franchise bundle and Continue Watching
fix are on the app's 1.0.27 line, not released. FOREIGN FILMS and CULT CLASSICS stay
thin on both surfaces: they gate on IMDb ratings and OMDb is not relayed yet. The
franchise Found list is not wired into the web tuner's settings yet.

**Next.** OMDb through the relay; a generated membership file places the Pirates of the
Caribbean films on MARVEL, fix in the generator.

## 2026-10-11 (playback diagnostic credential redaction)

**Changed.** Watchdog verdicts now remove complete URLs and credential assignments before unified logging or UserDefaults persistence. Error-log URL tails are no longer copied because truncation can remove a token's identifying key while leaving its secret value. Legacy verdict rows are discarded instead of migrated. Diagnostic status codes and playback measurements remain readable.

**Validation.** Regression fixtures cover URL userinfo/query credentials, relative URLs, quoted headers and JSON keys, bearer authorization, percent-encoded forms, direct persistence inspection, and legacy row cleanup. Xcode 27 / tvOS 27 native suite passed 437 tests, with 2 optional live tests skipped and no failures.

**Half-done.** This is scoped to playback verdicts; it does not claim that every unrelated log producer has been audited. No server, account or credential settings changed.

**Next.** Upstream review. The change is isolated on `fix/redact-playback-diagnostics`; no merge or deployment is included.

## 2026-10-11 (server-qualified music cache identity)

**Changed.** Music enrichment and channel-pool refresh now use the existing server-qualified item identity instead of a server-local rating key. A new disk-cache filename avoids assigning ambiguous legacy rows to a server. Music display copies preserve server routing and playback compatibility fields, and non-music items do not receive cached music metadata.

**Validation.** Regression fixtures exercise two servers with the same rating key in both orders, disk reload, legacy cache isolation, non-music collision, and routing/codec fields through both music-copy paths. Xcode 27 / tvOS 27 native suite passed 441 tests, with 2 optional live tests skipped and no failures.

**Half-done.** This branch covers native music enrichment and pool identity. It does not include unrelated guide, metadata-provider or playback recovery changes.

**Next.** Upstream review on `fix/server-qualified-music-cache`. No merge or deployment is included.

## 2026-10-11 (OMDb through the relay, branch only)

**Shipped.** Nothing. Branch `omdb-relay`, cut from `report-no-cw` with
`web-enrichment` merged in, not merged, not deployed.

**Changed.** Nothing on `main`.

**Half-done.** On `omdb-relay`, both surfaces:

- FOREIGN FILMS (imdbRatingMin 6.5, imdbVotesMin 5000) and CULT CLASSICS
  (imdbVotesMin 30000) need IMDb values, and the shared Supabase cache had
  `imdb_rating` / `imdb_votes` empty on every row: the App Store build carries
  no OMDb key, so it never asked. `api/tmdb.js` now also answers
  `path=omdb/{imdbID}` (`tt` plus 7 to 9 digits only) with `OMDB_API_KEY`, same
  client header rule, CORS allowlist and Vary. Edge cache 7 days, stale for 30.
  OMDb's daily-limit answer (HTTP 401 "Request limit reached!") becomes a clean
  429; "Response: False" answers pass through uncached. No ids are logged.
- `OMDBService` works like `TMDBService`: direct with a key, else the relay.
  `EnrichmentService` now fetches TMDB first and decides OMDb afterwards.
- Quota. OMDb free is 1,000 a day for every device together, so a title is only
  looked up when it could land on an IMDb-gated channel: same media type plus a
  keyword or genre from that channel's rules (gates derived from channels.json,
  `OMDBGate`). At most 50 lookups per library load, random order, so repeat
  loads walk through different titles. After a 429 the device stops asking until
  the next UTC midnight (`OMDBBackoff`, UserDefaults; localStorage on the web).
- Web (`scripts/nostalgex-enrichment.js`): same gates, cap and backoff, 4 in
  flight, upsert back with the OMDb columns only. The IMDb id comes from the
  shared row or the TMDB movie document (`imdb_id`), never the server, so IMDb
  ids now leave the browser alongside TMDB ids.
- Tests: `OMDBRelayTests` (17), relay smoke and enrichment smoke extended.
  A local relay call for tt0133093 with the real key returned 200, rating 8.7.

**Next.** Set `OMDB_API_KEY` on Vercel before deploying the relay. A one-off
backfill of the gated candidates would fill the cache faster than 50 per load.

## 2026-10-11 (Report Playback never fills Continue Watching, branch only)

**Shipped.** Nothing. Branch `report-no-cw`, cut from `shared-franchises` at
`db9b26b`, not merged, not deployed.

**Changed.** Nothing on `main`.

**Half-done.** On `report-no-cw`, both surfaces, all three servers:

- Turning on Report Playback is meant to mean "my server sees what's playing and
  a real watch counts", not "every channel I surf past lands in Continue
  Watching". The tracker now reads the item's state before its first report and
  puts it back when the session ends: unscrobble for a never-watched item,
  `/:/progress` back to the user's own resume point, `removeFromContinueWatching`
  for a watched one; on Jellyfin/Emby a mark-unplayed or a `UserData` write of
  the prior values. Details and the measured server behaviour are in
  `Nostalgex/docs/plex-session-reporting.md`.
- Every report and cleanup goes through one serial queue, because Plex writes a
  resume point on every timeline report (measured: the first `playing` report
  puts the item in Continue Watching), so ordering decides whether the cleanup
  sticks.
- Plex scrobbles never counted: `/:/scrobble?key=/library/metadata/{rk}` is a
  404; only the bare rating key works. Fixed on both surfaces. After a scrobble
  the tracker reports position 0, since any real position re-creates a resume
  point on the item Plex just marked watched.
- Jellyfin and Emby count a play on the *start* report, so a 30 second surf
  used to add a play (and feed the rewatch channels). The restore puts the prior
  PlayCount back; a counted watch ends as prior + 1.
- Settings copy on both surfaces: "Off by default. When on, your server sees
  what's playing and a film you watch most of counts as watched. Channel
  surfing never fills your Continue Watching." The warning line is gone.
  Privacy page wording updated, effective date moved to October 11.
- The decision table is shared through `scripts/watch-cleanup-golden.json`
  (16 cases), read by `WatchStateGuardTests` and `npm run test:watch-state`.
- Verified against a real Plex server, an Emby 4.10.1 server and a local
  Jellyfin 12.2 test server by running the real tracker on a fake clock
  (`LiveContinueWatchingTests`, skipped unless `TEST_RUNNER_NOSTALGEX_LIVE_*`
  is set): Continue Watching / Resume identical before and after, item state
  restored exactly. The web module was run against the same three servers from
  node. The web tuner itself was not driven in a browser.
- Not verified: Jellyfin/Emby Next Up after a counted episode (no TV library on
  either test server). Left alone on purpose: it is a separate row there, and a
  counted episode is a real watch. Closing the web tab mid-program cleans up with
  `keepalive` requests that are not ordered; best effort.

**Next.** Review and merge `report-no-cw`. Then an on-device check with
reporting on: surf ten channels, open Plex, Continue Watching unchanged.

## 2026-10-11 (shared franchise dictionary, web port, branch only)

**Shipped.** Nothing. Branch `shared-franchises`, cut from `franchise-polish`
at `188d60d`, not merged.

**Changed.** Nothing on `main`.

**Half-done.** On `shared-franchises`:

- The 18 franchise definitions moved out of `FranchiseDictionary.swift` into
  `franchises.json` at the repo root, next to `channels.json`, so the web tuner
  can use the same editorial list instead of a copy that drifts. It is bundled
  the way `channels.json` is: a symlink in `Nostalgex/Nostalgex/` excluded from
  the synced group, copied by the "Sync channel config" build phase, and
  `public/franchises.json` for the Vite build. A Swift harness compared the
  decoded file with the old hard-coded table field by field: identical. The
  ids carry a `verified: 2026-10-11` header and a per-entry `note`.
  `FranchiseDictionary` keeps its API (`all`, `byCollectionID`,
  `defaultOnIDs`, `isOn`, `cleanFranchiseName`); a missing or broken file logs
  a CONFIG line and leaves the dictionary empty rather than crashing.
- `scripts/nostalgex-franchise-builder.js` is a port of
  `FranchiseChannelBuilder` (same module style as the daily manifest, works as a
  plain browser script and in node). It is standalone: `plex-tuner.html` does
  not load it yet, because that file was being changed on another branch.
- `scripts/franchise-golden.json` holds 13 library cases plus title-key,
  film-match and server-collection vectors (36 checks). The Swift
  `FranchiseGoldenTests` and the node `npm run test:franchises` both read it,
  so a rule changed in one engine fails the other's test.
- Three spots in the Swift builder depended on dictionary iteration order, which
  Swift does not keep stable, so the web port could not match them: which found
  franchise a TV show joins when two names match (now the lower collection id),
  the order of two dynamic channels with the same name (now by stable id), and
  which stock channel a server collection maps to when two qualify (now the
  lower channel). None changes a library where only one answer was possible.

7 new Swift tests; full `NostalgexTests` 598 passed, 0 failed, 2 skipped (the
two live harnesses). `npm test` and `npm run build` pass, and
`dist/franchises.json` and the built `Nostalgex.app/franchises.json` are both
present. Not run on a device or against a real library.

**Next.** Wire the builder into `plex-tuner.html` once the enrichment work there
lands: fetch `/franchises.json`, call `NostalgexFranchiseBuilder.build` with
items carrying `enrichment.franchiseID` and `franchiseName`. Then merge
`franchise-polish` and this branch together.

## 2026-10-11 (web tuner: TMDB enrichment and server collections, branch only)

**Shipped.** Nothing. Branch `web-enrichment`, cut from `franchise-polish` at
`188d60d`, not merged, not deployed.

**Changed.** Nothing on `main`.

**Half-done.** On `web-enrichment`:

- The web tuner had no enrichment, so every keyword, network and production
  company rule only matched through the membership manifest. It now does what
  EnrichmentService.swift does: dedupe to TMDB ids, read the shared Supabase
  cache in chunks of 200, fetch the misses through `api/tmdb.js` six at a time,
  parse exactly as `TMDBService.parseResponse`, upsert back with
  `resolution=merge-duplicates`. Only TMDB ids leave the browser; the upsert
  names its TMDB columns so it never touches OMDb columns an Apple TV wrote. A
  per-browser IndexedDB copy (7 days, TMDB 404s for 1 day) means a reload asks
  nothing. The guide is built first and rebuilt when enrichment lands.
- Plex items on the web carried no TMDB id for libraries on Plex's current
  agents: the section scan never asked for `includeGuids=1`, and episodes read
  their own guid instead of the show's. Both now match tvOS. The library cache
  is versioned so an old id-less cache is refused once.
- The relay accepts `X-Nostalgex-Client: web`, answers preflights, and echoes
  `Access-Control-Allow-Origin` only for nostalgex.app, www.nostalgex.app and
  localhost:5173.
- Server collections become channels: Plex section collections, Jellyfin and
  Emby BoxSets, 3+ movies, alphabetical, CH 500-699 capped at 200, switched on
  under Settings, BUNDLES, MY COLLECTIONS. Stock-duplicate warnings match the
  app. Collections that duplicate a stock franchise channel fold out using the
  app's name, manifest and pool-overlap signals; the franchise-dictionary
  signals and the FRANCHISES / OTHER COLLECTIONS split are not ported.
- Measured on a test Plex library of 11,656 items (10,488 with a TMDB id,
  1,926 unique): 1,926 Supabase hits on a warm cache, 132 relay fetches on a
  colder one, 36 channel pools changed, about 10s after the guide was up. A
  reload made no Supabase or relay requests. Pool sizes without and with
  enrichment: TEEN MOVIES 14 to 21, MUSICALS 43 to 57, BIOPICS 13 to 18,
  MIDNIGHT 1 to 6, TOON TOWN 0 to 44, SPY GAMES 0 to 59, TRUE CRIME 0 to 1,
  FOREIGN FILMS 2 and CULT CLASSICS 4 unchanged. The last two need OMDb values
  and the shared cache holds none (0 of about 2,100 rows), so they stay as thin
  on Apple TV.
- Not checked against Emby or Jellyfin servers with real credentials; the
  BoxSet calls are unit-tested only. The 9-channel parity with the app is a
  rule-by-rule read of `AppState+Channels.swift`, not a side-by-side run.

**Next.** Set `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` on Vercel before
merging, and deploy the relay with the tuner. `channels-memberships.json`
claims all five Pirates of the Caribbean films for CH101 MARVEL and X-Men for
CH65 BIOPICS; both surfaces read it, so the web folds a Pirates collection into
MARVEL just as the app would. The privacy page does not yet say the web tuner
talks to Supabase and the TMDB relay.

## 2026-10-11 (franchise numbers, Marvel TV, default-on franchises, branch only)

**Shipped.** Nothing. Branch `franchise-polish`, cut from `stock-fold` at
`be67d61`, not merged.

**Changed.** Nothing on `main`.

**Half-done.** Three changes on `franchise-polish`:

- Runtime channel numbers collided. Found franchises numbered from 220 and
  OTHER COLLECTIONS from 260, so a library with 86 three-film franchises under
  ADD ALL ran franchise numbers to 305 and two rows shared a number,
  interleaved in the guide (it sorts by number). Ids were never the problem
  (they live at 1,000,000+). Franchises now take CH 300-499 and collections
  CH 500-699, each a hard cap of 200: enabled items past the end are not built,
  the log says how many, and Settings shows one quiet line under FOUND IN YOUR
  LIBRARY only when the franchise range is full. Saved choices are ids, never
  numbers, so nothing a viewer switched on is lost; a stale row from an old
  snapshot is rebuilt on the new number. channels.json is untouched (1-140,
  music videos 200-213). The web tuner builds no collection or franchise
  channels at all, so it needed nothing.
- MARVEL (CH101) now carries TV. Its films stay with the `studios` rule; shows
  join by exact title only (case and punctuation ignored, so "What If...?",
  "What If…?" and "S.H.I.E.L.D" without the last dot all match, and "Echo"
  cannot take "Echo Park"). The list covers the Disney+ MCU shows, the Netflix
  era and the ABC era, plus the "Marvel's ..." spellings older agents use. It
  is editorial and can be trimmed in `FranchiseDictionary.swift`.
- STAR TREK and FAST & FURIOUS start switched on (`defaultOn`). An explicit
  off is kept in `nostalgex_disabled_franchises`, which iCloud sync carries
  next to the enabled list, so a viewer who removed one does not get it back
  on the next rescan, relaunch or other Apple TV. No films, no channel, same
  three-film gate as before.

16 new tests; full `NostalgexTests` 591 passed, 0 failed, 2 skipped (the two
live harnesses). Not run on a device or against a real library.

## 2026-10-11 (stock franchise channels mix movies and shows, branch only)

**Shipped.** Nothing. Branch `stock-fold`, cut from `enrichment-proxy` at
`3c1a2ed`, not merged.

**Changed.** Nothing on `main`.

**Half-done.** CH100-106 built their pools from the channels.json rule alone,
and six of the seven rules say `type: movie`. The franchise builder already
placed The Mandalorian and Andor under STAR WARS and Rings of Power under LORD
OF THE RINGS, but Settings only showed that as a greyed "ON CH 100" label; the
episodes never aired. On `stock-fold` a stock channel's pool is its rule's pool
plus the covered franchise's movies and shows, deduped by item id, while the
FRANCHISES package is on. Manifest locks and exclusive rules still win, so an
item another channel owns is not taken. The covered row now reads "3 movies,
2 shows on CH 100". Swift only: the web tuner has no franchise dictionary and
keeps the rule-only pool. 4 new tests, full `NostalgexTests` 575 passed,
0 failed. Not run on a device or against a real library.

Known limit: a classic whose rule matches fewer than `minItems` (3) films is
never built, so two Star Wars films plus The Mandalorian still give no CH100.

## 2026-10-11 (TMDB proxy and Supabase key plumbing, branch only)

**Shipped.** Nothing. Branch `enrichment-proxy`, cut from `icloud-opt-in` at
`42320a5`, not merged.

**Changed.** Nothing on `main`.

**Half-done.** No build has ever carried the TMDB, Supabase or OMDb values, so
every install logs `[Enrichment] Skipping: API keys not configured` and the
channels that lean on enrichment stay empty. `enrichment-proxy` turns the layer
on without shipping the TMDB key:

- `api/tmdb.js`, a Vercel function next to `subscribe.js`. GET with `?path=`
  restricted to `movie/{id}`, `tv/{id}`, `collection/{id}` and
  `search/collection` (numeric ids only, anything else is a 400). It adds the
  key from the `TMDB_API_KEY` env var, adds `append_to_response=keywords` for
  movie and tv, and returns TMDB's JSON and status. A 200 carries
  `Cache-Control: public, s-maxage=86400, stale-while-revalidate=604800` so
  Vercel's edge cache absorbs repeats; anything else is `no-store`. It requires
  `X-Nostalgex-Client: tvos` (403 without it), a cheap filter, not security, and
  logs nothing. `npm run test:tmdb` covers the allowlist and the handler with a
  stubbed fetch (48 checks) and is part of `npm test`.
- `TMDBService` gains a proxy mode. With an empty key it calls
  `https://www.nostalgex.app/api/tmdb?path=movie/{id}` with the client header
  and no key in the URL; with a key it keeps calling TMDB directly, for dev
  builds. `TMDBConfig.tmdbProxyURL` holds the base. The document is the same
  either way, so `parseResponse`, franchise fields included, is untouched.
- `EnrichmentService` proceeds when a key or the proxy is available but still
  requires the Supabase URL and anon key, since the shared cache is the point.
  The skip log names what is missing:
  `[Enrichment] Skipping: missing supabase url, anon key`.
- Supabase values arrive through an xcconfig. `Nostalgex/Config.xcconfig`
  (committed) is the app target's base configuration for Debug and Release; it
  defaults both values to empty and does `#include? "Secrets.xcconfig"`.
  `Nostalgex/Secrets.example.xcconfig` is the template, `Secrets.xcconfig` is
  gitignored, and `Info.plist` maps `SUPABASE_URL` and `SUPABASE_ANON_KEY` to
  `SupabaseURL` and `SupabaseAnonKey`. A missing base configuration file is a
  hard xcodebuild error (measured: exit 65, "Unable to open base configuration
  reference file"), which is why the committed file sits in between.

Verified: `NostalgexTests` passes with no `Secrets.xcconfig` on disk (573 tests,
571 passed, 2 skipped live harnesses, 13 new in `TMDBProxyTests`) and the built
Info.plist carries empty Supabase strings. With a dummy `Secrets.xcconfig` using
`https:/$()/host`, the built plist reads `https://host` with both slashes. The
function called locally against real TMDB returns `movie/603` with
`belongs_to_collection` and 18 keywords, `tv/1399` with keywords and networks,
and rejects `person/1` with 400 and a missing header with 403. `npm run build`
passes. Not run on a device or simulator against the live function: nothing is
deployed yet.

**Next.** Set `TMDB_API_KEY` on the Vercel project and deploy so `/api/tmdb`
exists. Put the real Supabase URL and anon key in a local `Secrets.xcconfig`
before the next archive. Then rescan on a device and watch for
`[Enrichment] TMDB via site proxy` followed by the cache and save counts. The
README's "What leaves your network" now names the proxy hop; the privacy page
covers TMDB lookups in general terms but does not name nostalgex.app as a hop,
worth a line before that build ships.

## 2026-10-10 (iCloud sync, now opt-in, branch only)

**Shipped.** Nothing. Branch `icloud-opt-in`, stacked on `franchise-ui`, not merged.

**Changed.** Nothing on `main`.

**Half-done.** `icloud-sync` mirrored lineup and display preferences through
iCloud key-value storage from the first launch, and whichever Apple TV launched
first seeded the household. That is the wrong default for a household where one
TV has a curated lineup and another is a fresh install, so `icloud-opt-in`
carries the same two commits on top of the franchise work and adds a switch:

- SYNC WITH MY OTHER APPLE TVS, under DISPLAY in Settings. Off by default. The
  flag (`nostalgex_icloud_sync_enabled`) is per TV and is never itself synced.
- While off, nothing reads or writes the ubiquitous store: launch neither pulls
  nor seeds, Settings changes stay local, and incoming change notifications are
  ignored. A fake store in the tests counts reads, writes and synchronize calls
  and asserts all three stay at zero.
- Turning it on pushes this TV's current preferences first (this TV wins),
  adopts cloud values only for keys this TV has never set, then starts
  listening. Turning it off stops listening and leaves iCloud and the local
  values as they are. A TV that turns it on later follows the same rule.
- The found-franchise switches (`nostalgex_enabled_franchises`) join the synced
  set. The never-sync list in the tests now also names the switch itself, the
  rating nudge counters and the tip ledger, next to credentials, server
  address, stream quality and playback reporting.

Cherry-picking onto `franchise-ui` conflicted only in `AppState+Channels.swift`
(the franchise branch had renamed `materializeCollectionChannels` to
`materializeDynamicChannels`); the sync code now calls the new name.

Verified: the full `NostalgexTests` run passes (557 tests, 37 of them for the
sync service and its merge rules). A Release archive signed through the App
Store Connect key carries `com.apple.developer.ubiquity-kvstore-identifier`,
and a local App Store export with automatic signing produces an IPA whose
distribution profile includes it; nothing was uploaded. Not yet tried on
hardware: two real Apple TVs on one Apple ID flipping the switch.

**Next.** Hardware round trip with two TVs: switch on with different lineups,
confirm the first TV to switch on wins, then flip one off and confirm nothing
moves. Then merge order: `franchise-data`, `franchise-channels`, `franchise-ui`,
`icloud-opt-in`.

## 2026-10-10 (franchise bundle, branch only)

**Shipped.** Nothing. Everything below is on branches off `main`, not merged.

**Changed.** Nothing on `main`.

**Half-done.** The FRANCHISES package is being rebuilt in three phases, each on
its own branch stacked on the last:

- `franchise-data` (Phase 0): enrichment rows gain `franchise_id` and
  `franchise_name`, parsed from TMDB `belongs_to_collection` with no extra
  request. The two columns are added by `Nostalgex/docs/franchise-migration.sql`,
  which has NOT been applied to the shared table yet, so live enrichment still
  carries no franchise fields. Rows without the columns decode fine.
- `franchise-channels` (Phase 1): `FranchiseChannelBuilder` turns a library plus
  its enrichment into a franchise list. Three or more owned films sharing a
  TMDB collection make a channel; `FranchiseDictionary` merges split
  collections (Star Trek is three on TMDB), folds known franchises into the
  stock classics CH100-106, and adds TV by title (The Mandalorian under STAR
  WARS). Films TMDB leaves outside any collection (Rogue One, Solo, Bumblebee,
  Rise of the Beasts, all checked against the live API) join dictionary
  franchises by title. Marvel stays studio-ruled, never grouped by collection.
  Every dictionary id was verified live on 2026-10-10.
- `franchise-ui` (Phase 2, this entry): the Settings half. Under the FRANCHISES
  package row, when it is on, FOUND IN YOUR LIBRARY lists each found franchise
  with a switch, ADD ALL and REMOVE ALL, and the ones a classic already covers
  greyed as "ON CH 100". Found franchises default off so a big library does not
  flood the guide. Switches persist as a plain string array under
  `nostalgex_enabled_franchises`, keyed by dictionary name or TMDB collection
  id, so a later iCloud sync can carry it unchanged. A switched-on franchise is
  a dynamic channel (`rules == nil`) in the collection range (numbers from
  220), shown while the package is on; the schedule engine and playback are
  untouched. A server collection that is really one of these franchises is
  folded: credited under the franchise, hidden from MY COLLECTIONS, never
  materialised twice (`FranchiseCollectionFold`, reusing the scan's name and
  manifest signals plus a 60% item overlap). NOTABLE STARS is gone; actor and
  director sets classify as OTHER COLLECTIONS, a persisted `collections-actors`
  id migrates, and older snapshot rows resolve. Full `NostalgexTests`: 521
  passed, 2 skipped (pre-existing), 0 failed.

  Verified on the tvOS 26.1 simulator through a test-only launch argument,
  `-uiTestFranchiseFixture`, which layers an enriched sample library over demo
  mode (six franchises, two sample collections) because the shared table has
  no franchise columns yet. Not verified: the real enrichment path end to end,
  which needs the migration applied; a relaunch from a snapshot that carries
  found franchises; the fold against a real server's collections.

**Next.** Apply the migration, then load a real library and compare the found
list against what the library actually holds before merging. Decide whether
STAR TREK and FAST & FURIOUS become stock classics or stay found-only. Merge
order: `franchise-data`, `franchise-channels`, `franchise-ui`.

## 2026-10-11 (selected Plex version and multipart position)

**Changed.** Plex items retain the selected media index, complete part descriptors and exact duration. Decision/start/recovery requests use that media and part instead of always requesting index zero. Later parts keep the remaining stack and their own codec facts. A whole-film tune offset maps to the correct part and local offset when every part duration is available. Part changes keep one tracker and pause its clock during loading. Library snapshots keep schema 2 (changed on landing): an older snapshot decodes the new fields as version 0, part 0 and no part lengths, which is the previous behaviour, until the next full library scan fills them in. That avoids forcing every user to rescan.

**Validation.** Regression coverage checks whole-film offsets, third-part continuity, per-part SDR/codec facts, persistence and transcode query identities. Xcode 27 / tvOS 27 native suite passed 440 tests, with 2 optional live tests skipped and no failures.

**Half-done.** Unknown part lengths retain the existing offset fallback; this does not infer missing server metadata. Real multi-version and multi-file direct/HLS playback still needs hardware acceptance. Codec policy, heartbeat reporting and unrelated recovery fixes are excluded.

**Next.** Upstream review on `fix/preserve-plex-media-parts`; verify recognizable multi-version and three-part files on hardware before treating playback acceptance as complete.
## 2026-10-11 (Plex heartbeat-only activity)

**Shipped.** Prepared on `feature/plex-heartbeat-only` against upstream `c2f32e6`. No release, store upload or upstream merge.

**Changed.** Added a separate opt-in Plex Heartbeat Only setting, mutually exclusive with History & Resume. Existing history preferences and reporting endpoints remain intact. Heartbeat POSTs carry the item key, playback state and exact session header, with no time, duration or watched/scrobble operation. AVPlayer state feeds heartbeat updates. Reporting continues until disabled or a request fails; there is no elapsed-time cutoff or title-count limit.

Each server's heartbeat queue preserves playing/stopped order and tracks only the sessions it opened. Channel changes, disable and disconnect close those exact sessions. Reactivation waits for earlier cleanup and uses a fresh identity. Normal backgrounding requests bounded OS time for stop delivery; it cannot promise delivery after force-quit, network loss or OS expiration. A failed request stops further activity updates and makes one bounded cleanup attempt without stopping the stream. No account permissions, tokens, telemetry, app identifiers, artwork or branding are changed.

**Validation.** Xcode 27 / tvOS 27 simulator suite: 447 passed, 2 optional live harnesses skipped. Eleven new tests cover exact request fields, ordering, disable during an in-flight request, background/foreground, tracker release, rapid reactivation, failure cleanup, exclusive settings, and 100 consecutive pulses without an artificial count cutoff. Pulsed tests are not a real-time sustained playback measurement.

Earlier short hardware experiments using the same position-free timeline approach observed unchanged watch count, resume offset, last-viewed time and history digest, plus stopped-session cleanup. Those experiments used separate instrumentation and do not certify this exact upstream branch or general server behavior.

**Half-done.** Sustained playback beyond ten minutes, completion, delayed persistence, network failure and force-quit remain unverified on this branch. A draft PR should remain explicit about that gap. No claim of guaranteed history suppression is made.

**Next.** With an owner-approved hardware window, capture baseline stored fields/history for selected titles, watch one title at least eleven minutes, switch twice, disable heartbeat while leaving playback running, then re-enable and exit to Home. Verify activity remains present past minute ten, outgoing sessions clear, and stored fields/history match the baseline after stopping and a later read. Keep History & Resume off and never reset history.

## 2026-10-09 (app)

**Shipped.** Nothing to Apple. 1.0.24 (45) is still in TestFlight beta review.
`main` now carries 1.0.25 (46), not archived or uploaded.

**Changed.**

- Jellyfin and Emby connect forms have a FIND SERVERS ON MY NETWORK button
  (`LANServerDiscovery.swift`). UDP 7359, `who is JellyfinServer?` and
  `who is EmbyServer?`, three second listen, deduped by server id, kind taken
  from which probe the server answered. Measured before writing it: the Emby
  under test answered the subnet directed broadcast and ignored
  255.255.255.255, so the app sends to both, computing the directed broadcast
  from every live IPv4 interface. Network.framework could not receive the reply
  (a connected UDP socket drops datagrams from the server's unicast address),
  so it is a BSD socket with SO_BROADCAST. No system prompt seen in the tvOS 26
  simulator; `NSLocalNetworkUsageDescription` now names all three servers in
  case hardware asks. Jellyfin side verified only as far as the parser, no
  Jellyfin server was on the test network. Plex skipped on purpose: that form
  has no address field.
- The Plex to Emby switch bug from the 2026-10-08 entry is fixed, and the cause
  was not either suspect named there. It was a race: a stale snapshot starts a
  background Plex refresh at launch, which on a large library runs for minutes;
  the user disconnects and signs into Emby meanwhile; Emby's scan finishes
  first; then the Plex scan returns and, with nothing checking that its sign-in
  still exists, rebuilt every pool from Plex items and saved the snapshot under
  the Emby identity. That poisoned snapshot is why it survived relaunch. The
  harness (`BackendSwitchScheduleTests.swift`) showed the clean switch passing
  on the old code and the race failing with "CH 7 VHS VAULT schedule would send
  18 Plex key(s) to Emby". Fix: a session generation bumped on Disconnect or a
  server change, checked before every commit in `loadLibrary` and used to abort
  the remaining requests; items from servers not signed in are dropped at load;
  a snapshot holding such items is refused on launch and rescanned; playback
  skips a foreign item with the failure card instead of sending the server a
  request it will answer 500. Disconnect now also clears today's manifests and
  the collection scan. Behaviour change: disconnect and re-sign-in to the same
  server reshuffles today's guide.
- Settings: Connection moved above Display and took in the report-playback
  switch (it had its own section). The two subtitle switches became one
  SUBTITLES row cycling Off, Foreign audio, Always: the fullscreen switch only
  ever overrode the foreign-audio one, so they were one three-way setting.
  Subtitle language only shows when subtitles are not Off. The Buy Me a Coffee
  and update-email QR codes are gone from Settings, with their analytics event.
  The in-player panel still has separate CC and auto buttons.
- `NostalgexTests`: 436 passed, 0 failed, 2 skipped on the merged tree
  (417 before, 9 discovery, 9 backend switch, 1 moved).

**Verified on hardware** (Apple TV 4K, first generation): RESCAN LIBRARY on a
Plex library of about 11,600 items, Disconnect mid scan, then Emby found via FIND
SERVERS. The log read "sign-in changed while the scan was running, discarding its
results", the Emby library loaded, and five programmes played with no HTTP 500s.
The automatic background refresh that started the original report was not
reproduced (the snapshot was only hours old) but runs through the same check. No
local network prompt appeared; a clean install is still the true first press.
A 4K HEVC title with EAC3 audio that stalled in the simulator played cleanly.

**Next.** 46 to TestFlight. App Store
listing for the next submission: "131 themed channels across 14 bundles" and
new screenshots. Discussion #2 (Fire TV fork): ordering and DayPacker ports match
the JS reference byte for byte; the channel filter does not (22 channels
diverge), asked the contributor for filter golden vectors in `scripts/` before
deciding where it lives. Discussions #8 (Roku) and #14 (languages) are
unanswered.

## 2026-10-09

**Shipped.** nostalgex.app: the four SEO blog drafts and table styling (#15),
then site wide SEO and speed work (#16). The buddy cop post went live a day
early; the other drafts each moved up a day (Oct 12, 14, 16, 19, 21) and still
need their `draft: true` removed on the day. No app change.

**Changed.**

- Hero text no longer waits for JavaScript. `.hero-copy` (and `.hero-shot`) on
  `/`, `/plex`, `/jellyfin` and `/emby` lost the `reveal` class, which kept them
  at opacity 0 until `app.js` ran. That was most of the mobile LCP.
- Hero media is lighter and off the critical path. New poster
  `guide-hero-1280.webp` (54 KB, was 511 KB) is preloaded; the video is
  `preload="none"` and `app.js` starts it after `load`, never under reduced
  motion or Save Data. New encodes: 480p mp4 412 KB (phones), 1600 webm 1.46 MB
  and 1280 mp4 1.37 MB (desktop). Old files stay for one release so cached
  pages don't 404. Screenshots below the hero get 1280 and 1920 `srcset` sizes.
- Lighthouse mobile, local static build, same machine before and after: `/`
  went 71 to 96 (LCP 6.3 s to 2.4 s, 1,068 to 745 KiB), `/jellyfin` 74 to 94
  (LCP 8.1 s to 2.3 s). Not yet measured on the Vercel preview.
- `/plex`, `/jellyfin` and `/emby` were near copies, and two of them sat outside
  Google's index. Each now has its own H1, direct answer, setup steps, tips and
  gotchas, and six server specific FAQs.
- Every page has new titles and descriptions, a 1200x630 card image
  (`og-image-1200.png`, letterboxed because a center crop clipped the logo), a
  48px favicon, an apple-touch-icon, and one JSON-LD `@graph` linking the app,
  Chad and Muell Haus by `@id`. Visible FAQs and FAQPage text are generated from
  the same strings.
- Blog: titles end in " | Nostalgex", Article author is the Person `#chad`,
  posts get a BreadcrumbList, and new optional front matter `cover_alt`. FAQPage
  and table wrapping from #15 are kept, folded into the single graph.
- Sitemap entries carry `lastmod` only (Google ignores changefreq and priority).
  Added `public/llms.txt`.
- Support page CORS configs said `https://nostalgex.app`, but the tuner runs on
  `https://www.nostalgex.app`, so the documented config could not work. Fixed.
- Removed the Data Haus analytics script from every page, the blog template and
  the CSP. statsngraphs stays. The privacy page, README and the support FAQ
  now describe one analytics script; the support FAQ no longer says there are
  no analytics on the tuner pages, because the connect page loads one.
- "Over a hundred" is now 131 everywhere it appeared.
- `Nostalgex/PRIVACY_POLICY.md` matches the privacy page: statsngraphs only,
  effective October 9. `docs/FAQ.md` named 1.0.22 for the Tailscale/VPN http fix,
  which shipped in 1.0.23 (support page was already right).

**Half-done.** Rich Results Test and a Lighthouse run against production still
need doing.

**Next.** Merge #15 first, then this. After deploy, resubmit the sitemap and
request indexing for /plex, /jellyfin, /support and the blog post.

## 2026-10-08

**Shipped.** 1.0.23 reached the App Store (build 44). It carries the Jellyfin
channel-change fix, the Plex playback fixes, the SCREAM and TIS THE SEASON
packages, eleven new channels and the Y2K renames. The web tuner on
nostalgex.app shipped separately the same day.

**Changed.**

- Merged #5 and #7 from @Gorbataras, who found the tune-in bug independently and
  traced it further than we had, through Jellyfin's `DynamicHlsController` across
  10.10.7, 10.11.0, 10.11.11 and 12.1. #5 routes **Emby** through the same
  client-side seek Jellyfin already used, and deletes `addingStartTime`, which no
  longer had a caller. #7 stops Jellyfin and Emby direct-playing the two things
  AVPlayer will not render: HEVC in MP4 tagged `hev1` (it renders only
  `hvc1`/`dvh1`) and 10-bit H.264. Both guards already existed on the Plex path
  and had never been ported.
- Closed #3. The symptom was the tune-in bug, fixed in 1.0.23 and verified by
  @Gorbataras on an Apple TV 4K against Jellyfin 12.1.
- **Plex adaptive mode is no longer requested.** With `autoAdjustQuality=1`, any
  film where the server re-encodes both video and audio came back as 3-second
  segments: the first eight arrived at full speed, then one every 6.1 seconds for
  the rest of the film. tvOS 26 abandons a segment that slow (CoreMedia -15628)
  and the picture died at 24 seconds, at 4K and at the 1080p retry alike. With it
  off, the same request returns 1-second segments and keeps pace. Audio-copied
  streams were never affected, which is why some channels played and others did
  not.
- **Dolby Vision profile 5 plays on Plex.** Plex refuses to re-encode DV5
  (decision 2003), but it will remux it for a client it resolves as Generic,
  which is what Plex's own Apple TV app gets: `container=mp4, video=copy hevc
  DOVI 5`. On a DoVi refusal the app now re-asks once that way. Measured on
  device: picture in 1.8s, 61.6s of playhead across a 60s hold, zero stalls, zero
  dropped frames.
- **A starving stream steps down instead of freezing.** When a server cannot keep
  up, the same film is re-requested from the current position capped at 1080p,
  and only a starving capped stream advances. Previously it froze or jumped to
  the next programme.
- **An offset HLS transcode reports the remainder as its duration**, not the full
  runtime. The end-of-item fallback was adding the offset back, so `remaining`
  went negative on every tuned-in transcode and the first rate-0 moment skipped
  to the next film.
- **Web tuner: a failed stream retried forever.** The hls.js error handler
  guarded its one recovery with a flag written onto the error payload, and hls.js
  builds a fresh payload per event, so the guard never held. Measured against a
  playlist of 404s: **14,612 requests in 8 seconds**, roughly 1,800/s aimed at
  the user's own server; the same handler with the flag held outside the event
  made 14. A real session was caught making 2,239 requests for one dead segment
  while an unrelated channel played normally.
- **Web tuner: each playback now mints its own Plex transcode session** and
  releases it on the way out. Without one, Plex keyed the transcode off the
  client id alone, so every channel change quietly repurposed the previous
  session, which is what left the old loader requesting segments that 404.
- **Web tuner: a manifest that will not load now skips.** `start.m3u8` answering
  400 produces exactly one fatal `manifestLoadError` and nothing after it, so
  `startLoad()` had nothing to retry and the channel sat on black indefinitely.
  It now says so and moves to the next programme, stopping after three failures
  in a row because that points at the server rather than the file.
- **Music video genres come from Deezer** when the server reports none. On a test
  library of 1,131 music videos only 148 carried a genre, and MusicBrainz tags
  filled almost none of the rest, which is why CALIENTE and HEADBANGERS sat
  empty. Deezer resolved 47 of a random 60, and a filename cleaner (underscores,
  scene tags, `ft.`/`feat.`) recovered 10 of the 13 misses.
- **Music video years** are read from the filename first, then MusicBrainz, then
  the server only when plausible. Servers commonly report 1970 or the date the
  file was added, and Deezer's year is the album's, wrong on 15 of 15 sampled, so
  the decade channels were sorting by the wrong year.

**Changed, evening session (real hardware).** Build 1.0.24 (45) ran on an Apple TV HD
(tvOS 26.6) and an Apple TV 4K simulator against an Emby 4.10.1.0 server. Everything below
was measured there, not inferred.

- **Issue #6 confirmed fixed on hardware, with a controlled before/after.** The shipped
  1.0.23 (44) from TestFlight on the same device: `HTTP 404. The file '/UserViews' could
  not be found.` Build 45 ten minutes later: `[Emby] LIBRARY: 1541 items`, 69 channels,
  playback at a 57-minute mid-schedule join. Gorbataras's #5 Emby seek is confirmed by the
  same run.
- **The guide wrap works on tvOS 26.6**, the reporter's exact version, which the 26.1
  simulator could never reproduce. Down wraps, Up reaches SETTINGS.
- **The failure card now says why, accurately.** Three classifier corrections from
  watching it misfire: the probe walks master to variant to first segment, because the
  master answers 200 while every segment beneath it is refused; CoreMedia -12889 (no
  response in 3s) and -15628 (segment abandoned) classify as the server being too slow,
  not the device failing to decode; and a decoded frame vetoes "Apple TV couldn't play
  this file" outright. Verified verdicts on hardware: `Emby HTTP 500, refused before
  video` and `Emby below real time on the capped stream`.
- **Audio track selection.** Jellyfin and Emby hand back the file's default track, and
  Joe Dirt's default is Spanish 2ch with English 5.1 unflagged, so it played in Spanish
  on a channel with no picker. The resolver now reads MediaStreams from PlaybackInfo,
  prefers a track in the viewer's language with the most channels, then the default,
  then the first, and pins `AudioStreamIndex` on the transcode URL. Verified against the
  server: Emby's own URL pinned index 1 (spa); ours pins 2 (eng); Emby accepts it. 7 tests.
- **The starvation ladder's Emby rung fired for real** (The Wedding Singer, 13 Going on
  30): starve, cap to 1080p, `TRANSCODE READY`. It recovers what it can.

**Found, not fixed.**

- **Switching backend keeps the old day schedule.** A device signed into Plex, then
  Disconnected and connected to Emby for the first time, kept playing the Plex running
  order: Plex rating keys sent to Emby resolve to Person records and 500, every channel,
  looping between two titles indefinitely. A fresh install is flawless, so it is the
  transition that leaks. `DailyManifestStore.clearAll` on Disconnect uses the fingerprint
  current at that moment, and `apiForServer` never checks an item's `serverID` belongs to
  the connected backend. Workaround: delete and reinstall. Worth fixing before a wide push.
- **Two test rigs invent failures.** The tvOS simulator has no EAC3/AC3 decoder, so ~25%
  of a typical library stalls 3s in and looks like starvation; the Apple TV HD has no HEVC
  decoder, so every HEVC title forces a server re-encode that held 1.07x here against
  CoreMedia's 3s first-segment patience. The same file for an HEVC-capable client is a
  17.3x remux. Playback claims need the 4K unit.
- **On this Emby, 10-bit sources cannot transcode at all.** `VideoFilters.format..ctor()`
  throws "An item with the same key has already been added. Key: threads" before ffmpeg
  starts; 190 of 1541 movies affected. Ruled out by measurement with the server restored
  afterwards: codec, resolution, bitrate, subtitles, audio stream, thread count, hardware
  acceleration. A server bug, reported by the card as a refusal, nothing for the app to do.

**Half-done.**

- `fix/emby-userviews-404` — **Emby library scans fail immediately.**
  `loadSections` asked for `/UserViews?userId=`, which is Jellyfin's spelling.
  Measured against Emby Server 4.10.1.0: `/UserViews` answers 404,
  `/Users/{id}/Views` answers 200. It is the first request after sign-in, so it
  fails whatever the libraries are named and however large they are. Fixed with
  three tests on the branch, not yet merged. This is issue #6, and it is present
  in the released 1.0.23. **Now verified end to end against an Emby server**
  (see below).
- `feat/playback-failure-card` — **a programme that will not play now says why,
  instead of being swapped for the next one in silence.** Only three of about eight
  failure paths showed any UI at all; the startup watchdog, the starvation verdict and an
  AVPlayer item reaching `.failed` all advanced with nothing on screen, which reads as a
  broken app and hides whether the person should look at their server or at the file.
  `PlaybackState.error` now carries a `PlaybackFailure` rather than a sentence, and every
  failure path funnels through one place that records the verdict, emits the matching
  analytics code and shows a card for five seconds before advancing. Amber when the server
  is the thing to go and look at, red when the file or the device is.
  Getting the reason right needed a new source of truth: tvOS has no `httpStatusCode` on
  `AVPlayerItemErrorLogEvent`, so the status of a refused segment cannot be read out of the
  player, and that status is the difference between "your server refused this" and "this
  file will not decode". `StreamFailureProbe` asks the server instead, with one ranged GET
  on the URL that just failed. 14 tests, classification being a pure function over what was
  observed. Not merged.
- The startup watchdog's capped retry had the same missing client-side seek the starvation
  ladder got, so a watchdog retry on Jellyfin or Emby would have restarted the film from
  frame one. Fixed on the same branch as the ladder.
- `fix/starvation-ladder-all-backends` — **the starvation ladder had no rung on
  Jellyfin or Emby, so one stall skipped the programme.** `handleStarvation` steps
  a starving stream down to 1080p and only advances once there is nothing smaller
  to ask for, but `cappedTranscodeURL` was implemented on Plex alone and the
  `MediaBackend` default returns nil. Measured on Emby Server 4.10.1.0: each
  6-second segment took 3.4s to produce before its first byte, at 128 Mbps once
  flowing, so the server and not the network was the limit; a film jumped out
  mid-scene to the next scheduled title at its first frame. Both backends now
  build the rung at 1920 wide and 8 Mbps under their own `PlaySessionId`, with no
  start time on the URL, because the segment handler refuses one. A new
  `cappedStreamStartsAtOffset` says which backends seek client-side. 4 tests.
  Not merged.
- `fix/backend-error-copy` — error messages name the server the user actually
  connected to. `PlexAPIService.APIError` is the shared error type for all three
  backends, but every message hung off it was written for Plex, so an Emby user
  whose scan 404s was told "Plex (or your network path) returned HTTP 404" and
  sent to check Plex's Remote Access setting. Plex keeps its own copy, including
  the `/library` and `/identity` paths only Plex serves. One test asserts no
  Jellyfin or Emby message contains the word "Plex", across every error case.
  Not merged.
- `fix/guide-wrap-scrolling` — the guide's vertical wrap now runs off a focusable
  sentinel row just outside the last channel rather than a 150ms staleness timer,
  so "ran off the end" is proven by the focus engine instead of inferred from a
  clock. Up out of channel one deliberately still leaves for SETTINGS and does
  not wrap. 9 UI tests. Not merged. The report that prompted it came from tvOS
  26.6 and never reproduced on the 26.1 simulator at any list length or cadence,
  so treat this as hardening fragile timing rather than a confirmed fix.
- The web tuner still appends `StartTimeTicks` to its Jellyfin fallback URL in
  `getJellyfinTranscodeUrl` (`plex-tuner.html`). Same defect #5 fixed on tvOS.
  hls.js already seeks via `startPosition`, so the parameter only breaks segment
  requests. Spotted by @Gorbataras. In progress.
- **Emby, measured.** The Emby halves of #5 and #7 were reasoned from Jellyfin's
  HLS controller being forked from Emby's, and from Emby's own web client seeking
  client-side. Both now ran against Emby Server 4.10.1.0: sign-in, library scan,
  guide build, and a mid-programme join that started Heat at 47 minutes into a
  2:50:00 film and advanced 25s of playhead across 25s of wall clock with no
  stall. The scan only ever touches `/Users/{id}/Views` and `/Items`, and series
  and episodes go through that same `/Items` call with a different
  `IncludeItemTypes`, so a movies-only test library still exercises every HTTP
  path the scan makes. What remains untested on Emby is episode *parsing*, not
  whether an endpoint answers.

**Next.**

- Merge the three branches above.
- Port the web tuner's `StartTimeTicks` removal.
- Exercise an Emby library that contains TV series, to cover episode parsing and
  the per-show grouping the movies-only run could not reach.
