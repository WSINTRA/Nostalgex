# Add an Android TV / Fire TV prototype (Jellyfin)

## Why
Nostalgex runs on Apple TV and in the browser. Fire TV and Android TV users with a Jellyfin server
had no native option, and the browser tuner cannot reach plain-http LAN servers.

## What this adds
A self-contained `android/` Gradle project. Nothing outside it changes except docs and one CI job.

- Jellyfin sign-in with the connect-error taxonomy from `docs/FAQ.md`
- Library scan with a snapshot cache, channels built from the repo-root `channels.json`
- tvOS-matching schedule: seeded RNG, interleave, premieres, sequel grouping, day packing
- Live-style playback via Media3, with direct play vs fMP4 HLS transcode decision, retry-as-transcode, then skip
- D-pad channel surfing, info banner, now/next guide
- Tested on a Fire TV Stick 4K (gen 1, Fire OS 6, API 25)

## Design
Pure-Kotlin modules (`core-*`, `data-backend`) hold all logic and run on a plain JVM. Android code
(`app`, `player`, `data-store`) is thin. Clock, stores, backend and player are injected through
constructors; `AppContainer` is the single hand-written composition root. `MediaBackend` mirrors the
Swift protocol, so Plex and Emby can be added by implementing one interface.

## Parity
`ScheduleParityTest` reads the golden vectors straight out of `scripts/nostalgex-schedule-order-smoke.mjs`
(INTER/PROMO/SEQ orderings and `premiereOffset`). The Android CI job runs whenever that file changes.
`DayPacker` is checked against output of the JS `packDay` on the same fixture.

## Testing
`cd android && ./gradlew test` (about 60 JVM tests). The Compose screens and the Media3 adapter are
verified manually on a device and have no automated tests.

## Not in this PR
Plex and Emby; TMDB/OMDb enrichment rules (`keywords`, `networks`, `productionCompanies`,
`imdbRatingMin`, `rtScoreMin`, `wonOscar`, `keywordGatedGenres`, `manifestOnly`), so some channels are
smaller or empty than on tvOS; multi-server; subtitles and audio-language settings; Quick Connect;
music-video title parsing; multi-disc movies; PlaybackInfo handshake and stopping server transcodes
on channel change; the tvOS 6-hour refresh and prime-time premiere logic beyond what `DayPacker` ports.

## Known issues / follow-ups
- Session token stored unencrypted (app-private SharedPreferences). Encrypt before any public release.
- `ratingMin` uses community rating only (no per-user rating field).
- Placeholder launcher banner.
- Name and icon: per the README, the Nostalgex name and icon are not covered by the MIT grant, so the
  maintainer should decide branding for any distributed build.

## Questions for the maintainer
1. Is `android/` in this repo acceptable, or would you prefer a separate repo?
2. Should enrichment-dependent channels be wired through the same TMDB/Supabase cache the tvOS app uses?
3. Appetite for publishing (Amazon Appstore / Play) versus sideload-only?
