# Web tuner feature reference

Entry point: `plex-tuner.html`. All features here are **web tuner only** unless noted.

---

## Backend support matrix

| Feature | Plex | Jellyfin | Emby |
|---------|------|----------|------|
| Channel guide + schedules | Yes | Yes | Yes |
| Video playback | Yes | Yes | Yes |
| Subtitles | No | Yes | No |
| Audio language selection | No | Yes | No |
| Playback scrobbling (mark watched) | Yes | Yes | Yes |
| Bookmark / saved auth | Yes | Yes | Yes |

Plex and Jellyfin/Emby have parity on most things. Subtitles and audio language are Jellyfin-only because they rely on Jellyfin's `MediaStreams` API and `AudioStreamIndex` parameter. Plex handles these natively in its own player.

---

## Subtitles (Jellyfin, fullscreen only)

Toggle with the **C** key while in fullscreen. Off by default.

Subtitle track selection uses language preference (see Language settings below). The tuner:
1. Fetches the subtitle stream from Jellyfin as WebVTT (server transcodes any format)
2. Wraps it in a blob URL and attaches as an HTML `<track>` element
3. Clears on fullscreen exit

**Why fullscreen-only:** mirrors the tvOS behavior; subtitles in windowed mode are distracting at guide scale.

**Language matching:** Jellyfin stores track language as ISO 639-2/B 3-letter codes (`spa`, `eng`, `fra`). The tuner maps these from the ISO 639-1 2-letter user preference (`es`, `en`, `fr`) via a built-in lookup table. All Spanish regional variants (`spa`, `spa-419`, etc.) match the `es` preference.

---

## Audio language (Jellyfin only)

Set in **Settings → General → Language → Audio language**. Default is Auto (server picks the default track).

When a preferred language is set:
- The matching audio stream index is passed to Jellyfin's `PlaybackInfo` endpoint for transcoded content
- For direct-play streams, `AudioStreamIndex` is appended to the stream URL
- Changing the language while watching restarts the current item with the new track

Uses the same ISO 639-1/639-2 mapping as subtitle matching.

---

## Language settings UI

Settings → General tab → LANGUAGE section.

| Setting | Key | Default |
|---------|-----|---------|
| Audio language | `plex90_audio_language` | `__system__` (Auto) |
| Subtitle language | `plex90_subtitle_language` | `__system__` (browser locale) |

Both are stored in `localStorage` and persist across sessions.

---

## Saved auth / bookmark support

Auth is persisted to `localStorage` under `plex90_saved_auth` (set on first connect, cleared on sign out). This lets users:
- Bookmark `plex-tuner.html` directly and land straight in the guide
- Close and reopen the tab without reconnecting

`web-tuner.html` (the connect/landing page) auto-redirects to `plex-tuner.html` if valid saved auth is found.

Saved auth shape:
- **Plex**: `{ backend, token, userToken, serverUrl, serverName }`
- **Jellyfin**: `{ backend, token, serverUrl, serverName, jellyfinUserId, jfUrl, jfUser }`

---

## Keyboard shortcuts

| Key | Action |
|-----|--------|
| Up / Down | Browse the guide. Down on the last channel wraps to channel one, Up on channel one wraps to the last |
| Enter | Tune the highlighted channel |
| M | Mute / unmute |
| F | Fullscreen |
| B | Toggle retro mode (4:3 + CRT scanlines) |
| C | Toggle subtitles (Jellyfin, fullscreen only) |
| G | Fullscreen + guide overlay |
| H | Open settings |
| Left / Right | Change channel (wraps at both ends). In Settings, switch tabs |

---

## Retro mode

Toggle with **B** or Settings → General → Display → Retro mode.

Applies: 4:3 aspect ratio, CRT scanlines, vignette, VHS tracking glitch animation.

Stored in `localStorage` as `plex90_retro_mode`.

---

## Channel bundles

Users can enable/disable individual channel bundles (and individual channels within them) in Settings → Channels. Config persisted in `plex90_channel_config`. A CONFIG_VERSION integer gates migrations — bump it when the default bundle set changes significantly.

---

## Playback scrobbling

Reports "Now Playing" to the server and marks an item watched when the user has:
- Tuned in during the first 15% of the program (entry gate), AND
- Accumulated ≥ 75% of total runtime as active watch time

This keeps real Plex/Jellyfin play counts accurate, which feeds the REWATCHABLES channels (3+ views threshold). Works for both backends.

---

## Promo rows (in-guide)

Two promotional rows appear in the channel guide:
- **~67% down**: Buy Me a Coffee link (solo dev support)
- **~85% down**: Email signup (only shown if 20+ channels enabled, to avoid back-to-back placement)

These are inserted in `renderGrid()` and use `data-promo` attributes so they participate in keyboard navigation without interfering with channel tuning.
