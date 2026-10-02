# Nostalgex for Fire TV (Android TV prototype)

A Kotlin client that turns your **Jellyfin** library into retro cable TV channels, using the same
`channels.json` rules and the same deterministic daily schedule as the tvOS app and the web tuner.
It does not host or supply media.

**Status: prototype.** Jellyfin only. Tested on a Fire TV Stick 4K (1st gen, Fire OS 6 / API 25).

## What works

- Sign in with server address, username and password (plain `http` LAN addresses work)
- Library scan (cached for 6 hours), channels built from the bundled `channels.json`
- Live-style playback: tune in mid-program, auto-advance, retry as transcode, then skip
- D-pad Up/Down (or Channel +/-) to change channel, OK for the info banner
- Menu or Left for a now/next guide

Not yet: Plex and Emby, TMDB/OMDb enrichment rules (keyword/network/rating-service channels
are smaller or empty), multi-server, subtitles and audio-language settings, Quick Connect,
music-video title parsing, multi-disc movies, stopping server transcode sessions on channel change.

## Layout

| Module | Kind | Role |
|---|---|---|
| `core-model` | Kotlin | `MediaItem`, `Channel`, `ScheduleBlock` |
| `core-config` | Kotlin | `channels.json` parser (the repo-root file is copied in at build time) |
| `core-filter` | Kotlin | channel rules: library to channel pool |
| `core-schedule` | Kotlin | seeded RNG, pool ordering, `DayPacker`, `ScheduleResolver` |
| `data-backend` | Kotlin | `MediaBackend` interface, Jellyfin client, stream planner |
| `core-store` | Kotlin | session, snapshot and manifest storage behind interfaces |
| `core-playback` | Kotlin | `PlayerEngine` seam and `PlaybackController` |
| `core-presentation` | Kotlin | connect, load, OSD and guide models |
| `data-store`, `player`, `app` | Android | SharedPreferences, Media3 adapter, Compose for TV UI |

Everything except the last row is plain JVM Kotlin. Collaborators (clock, store, backend, player)
are injected through constructors; `app/.../AppContainer.kt` is the one hand-written composition root.

## Tests

```
cd android
./gradlew test
```

The schedule modules are checked against golden vectors generated from the real Swift algorithm
(see "Parity" below).

## Sideloading to a Fire TV

1. On the stick: Settings > My Fire TV > Developer Options > turn on **ADB debugging**
   (if Developer Options is missing: Settings > My Fire TV > About, click the device name 7 times).
2. Build: `./gradlew :app:assembleDebug`
   (or `:app:assembleRelease`; see signing below). Output: `app/build/outputs/apk/<type>/`.
3. Connect, either way:
   - USB: `adb devices` should list the stick as `device` (accept the prompt on the TV if `unauthorized`).
   - Wi-Fi: find the stick's IP in Settings > My Fire TV > About > Network, then `adb connect <ip>:5555`.
4. Install: `adb install -r app/build/outputs/apk/debug/app-debug.apk`
5. Launch from Apps > "See all" (sideloaded apps are at the bottom), or
   `adb shell am start -n app.nostalgex.tv/.MainActivity`.

Logs: `adb logcat -b crash`, or Logcat filtered on `package:app.nostalgex.tv`.

The stick must reach your Jellyfin server. Enter the address as you would in a browser, for example
`192.168.1.20`; `:8096` is added for bare http addresses. https addresses need a certificate the
device trusts (Fire OS 6 / Android 7.1 may reject newer Let's Encrypt chains).

## Release signing (optional)

Without configuration, `assembleRelease` signs with the debug key, which is fine for your own device.
For a stable key, create a keystore and pass it as Gradle properties (for example in
`~/.gradle/gradle.properties`, never in the repo):

```
NOSTALGEX_KEYSTORE=/path/to/nostalgex.jks
NOSTALGEX_KEYSTORE_PASSWORD=...
NOSTALGEX_KEY_ALIAS=...
NOSTALGEX_KEY_PASSWORD=...
```

## Parity with tvOS and web

`core-schedule`'s `ScheduleParityTest` reads the golden vectors straight out of
`scripts/nostalgex-schedule-order-smoke.mjs`. If someone changes the schedule algorithm there and
not here, the Android build fails, so all three surfaces keep airing the same program at the same time.

## Known limitations

- Session token is stored unencrypted in app-private storage. Encrypt it before a public release.
- `minSdk` is 25 (Fire OS 6); `java.time` is desugared.
- Cleartext http is enabled for LAN servers.
- The Compose UI and Media3 adapter have no automated tests; the logic behind them does.
