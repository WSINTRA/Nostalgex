# Nostalgex

Retro cable TV experience powered by your own media server. Nostalgex is a client for **Plex, Jellyfin, and Emby** -- it does not host or supply any media. Channels auto-populate from your library based on configurable rules (genre, studio, watch history, content ratings, etc.) and play on a deterministic daily schedule, so tuning in feels like live TV.

**Source of truth:** this repository (`chadMueller/Nostalgex`) contains the **public site**, **web tuner**, and **tvOS app** together. Read **[docs/REPOSITORY-LAYOUT.md](docs/REPOSITORY-LAYOUT.md)** for boundaries, deploy split, and how to avoid duplicating Nostalgex inside unrelated monorepos.

## Apps

### Web tuner (`web-tuner.html` + `plex-tuner.html`)
Browser app. `web-tuner.html` (routed as `/web-tuner`) is the connect screen; after sign-in it navigates to `plex-tuner.html`, which is the tuner itself: channel guide, surfing, playback.

- **Stack:** Vanilla HTML/JS, Vite, Vercel
- **Backends:** Plex, plus Jellyfin and Emby (Emby connects through the Jellyfin option).

**Browser limitation, by design of the web, not ours:** the tuner is served over HTTPS, so browsers block mixed content and it cannot reach a server on plain `http://` or on a raw LAN IP. Plex works because plex.direct issues real certificates for local addresses. Jellyfin and Emby need an HTTPS URL with a valid certificate (reverse proxy or tunnel). A local-only server with no HTTPS is reachable from the Apple TV app but not from the browser.

### tvOS (`Nostalgex/`)
Native Apple TV app, free on the App Store, open source. Same channel logic and config, built for the big screen with Siri Remote navigation. Connects to Plex, Jellyfin, and Emby, including more than one server at a time. No mixed-content limitation here -- a plain-http local server works fine.

- **Stack:** SwiftUI, AVPlayer, Xcode 26+
- **Target:** tvOS 18+
- **Key files:**
  - `App/AppState.swift` -- playback engine, channel selection, filtering
  - `Models/ChannelSchedule.swift` -- deterministic daily schedule builder
  - `Models/Channel.swift` -- channel config and rules
  - `Services/MediaBackend.swift` -- the backend protocol the three servers implement
  - `Services/PlexAPIService.swift`, `Services/JellyfinAPIService.swift`, `Services/EmbyAPIService.swift` -- server clients
  - `Views/` -- TunerView, PlayerView, ChannelGuideView, etc.
 
### Android TV / Fire TV (`android/`)
Prototype Kotlin client for Jellyfin, built to run on a Fire TV Stick (Fire OS 6+, API 25+) and sideloaded with `adb`. Same `channels.json`, same deterministic schedule: its tests read the golden vectors from `scripts/nostalgex-schedule-order-smoke.mjs`, so it airs the same program as tvOS and the web tuner. See `android/README.md` for the module layout, sideload steps and what is not yet supported (Plex, Emby, TMDB/OMDb enrichment rules).

- **Stack:** Kotlin, Compose for TV, Media3 (ExoPlayer), OkHttp, Gradle

### Public site (`index.html`)
Marketing page and the path into the tuner and the App Store. Served at `/` on Vercel.

## Shared Config

### `channels.json`
Both apps read the same channel configuration (113 channels across 13 bundles). The tvOS app bundles a copy and can also fetch an updated one at runtime.

See `CHANNELS.md` for a human-readable breakdown of each channel's rules and behavior.

### Schedule Logic
Both apps use a deterministic daily-seeded shuffle. The item pool for each channel is shuffled once per day (seeded by date + channel ID), then laid out end-to-end in a loop. The current position in the loop is derived from unix time, so tuning in at 2:15 PM always lands at the same spot in the schedule for that day.

When a video ends naturally on tvOS, the next video starts from the beginning (no mid-stream seek on auto-advance). On initial tune-in, you join mid-stream like real TV.

**The two schedules have diverged.** tvOS adds premiere priority, sequel adjacency, prime-time premieres for new additions, and a 6-hour refresh. The web tuner has none of those, so the same server on the same day will not show the same lineup in both places.

## Channel Rules

Channels filter your library (Plex, Jellyfin, or Emby, normalised to one internal model) using combinations of:
- **type** -- movie or episode
- **genres** -- include, exclude, requireAll
- **studios** -- Disney, HBO, etc.
- **yearRange** -- min/max year
- **contentRatings** -- whitelist (TV-Y, PG, R, etc.)
- **durationRange** -- min/max minutes
- **watchedOnly / unwatchedOnly / rewatched** -- watch history filters
- **timeRestrictions** -- block mature content before a set hour

## Development

### Web
```
npm install
npm run dev
```

### tvOS
Open `Nostalgex/Nostalgex.xcodeproj` in Xcode. Build target is Nostalgex (tvOS).

To run on a physical Apple TV: Xcode > Window > Devices and Simulators > pair your Apple TV, then select it as the run destination.

### Debug Logging (tvOS)
All playback logs are prefixed with `[Plex90]`. Filter the Xcode console to see channel selection, item loading, AVPlayer status changes, retries, and auto-advance events.

## Build it yourself (tvOS)

You need Xcode 26 or newer and an Apple TV or the tvOS simulator. Open `Nostalgex/Nostalgex.xcodeproj`, pick your own team under Signing, and run the `Nostalgex` scheme. No API keys are required. The app connects to your server, builds channels from your library's own metadata, and plays.

Two optional extras, both off unless you turn them on:

| What | How to enable | What it adds |
|---|---|---|
| TMDB / OMDb / Supabase metadata | Set `TMDB_API_KEY`, `OMDB_API_KEY`, `SUPABASE_URL`, `SUPABASE_ANON_KEY` as environment variables in the Xcode scheme, or as `TMDBApiKey`, `OMDBApiKey`, `SupabaseURL`, `SupabaseAnonKey` in `Nostalgex/Info.plist`. Read in `Services/TMDBConfig.swift`. | Keyword and collection data for finer channel rules. Supabase is a cache keyed on TMDB ids; you can point it at your own project. |
| TelemetryDeck | `TelemetryDeckAppID` in `Nostalgex/Info.plist`. Delete the key to turn it off. | Anonymous launch and playback counts. The App Store build has it on; your own build does not have to. |

Never commit real keys. `.gitignore` already covers `.env`, `Secrets.plist` and `*.xcconfig` secrets.

## What leaves your network

The whole point of running your own server is knowing where your data goes, so here is the full list for the tvOS app:

- **Your media server.** Direct from the Apple TV to your Plex, Jellyfin or Emby. Sign-in goes straight to the server. Nothing of mine sits in between, and no credentials are ever sent anywhere else.
- **plex.tv** (Plex only). The PIN sign-in flow and server discovery. This is how every Plex client works.
- **MusicBrainz.** Public metadata for the music video channels. No key, no account.
- **TMDB, OMDb, Supabase.** Only if you build with keys, see above.
- **TelemetryDeck.** Anonymous usage signals in the App Store build. No identifiers, no library contents, no server addresses. Off in your own build unless you keep the key.

The website and web tuner at nostalgex.app load two page analytics scripts (Data Haus and statsngraphs). The privacy policy at `/privacy` covers all of this in plain language.

## Contributing

Issues and pull requests are welcome. A few things that make them land faster:

- The easiest first PR is a rule change in `channels.json` (a title on the wrong channel, a channel that is always empty). `CHANNELS.md` explains every rule field.
- Keep PRs small and about one thing.
- Web changes: `npm test` must pass. tvOS changes: build for a real Apple TV, not just the simulator, because the simulator keychain and storage behave differently.
- One person maintains this in their spare time. You will get a reply, but not always the same day.

## License

MIT, see `LICENSE`. Bundled fonts and packages are listed in `THIRD-PARTY-LICENSES.md`.

The Nostalgex name, icon and the nostalgex.app site are not part of the MIT grant. Fork the code all you like, but please ship it under your own name.

## Deployment

Web app deploys to Vercel automatically on push to `main`.

