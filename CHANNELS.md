# Nostalgex Channel Guide

<!-- GENERATED FILE — do not edit by hand. Run `npm run channels:doc` after any
     channels.json change. Source: scripts/render-channels-doc.mjs -->

Quick reference for every channel and bundle. Source of truth: `channels.json`.

## Read this before editing a channel

**`id` and `number` are NOT the same thing.** A channel's `number` is what
viewers tune to; its `id` is the stable key everything else references. They
drifted apart as channels were renumbered, and today they differ for many
channels — for example `id` 40 is **CH85 TRUE CRIME**, and `id` 211 is
**CH140 CRITERION**. Get it wrong and you edit a different channel than the one
you meant.

Which key does what:

| Uses `id` | Uses `number` |
|---|---|
| `channels-memberships.json` (the TMDB membership manifest) | The on-screen channel number and guide ordering |
| `exclusiveRules.channelID` / `channelIDs` | Nothing else |
| `bundles[].channelIDs` | |
| Daily EPG manifest cache keys | |

Every table below shows both.

**Pool filter logic must stay aligned across three implementations.**
`scripts/nostalgex-channel-filter.cjs` (web tuner + devtools) mirrors
`Nostalgex/Nostalgex/App/AppState+Channels.swift` → `filterItems` (tvOS).
They do not share code, so a rule change has to land in both or the platforms
drift. TMDB membership manifest: `channels-memberships.json`.

**Schedule ordering must stay aligned too.**
`scripts/nostalgex-daily-manifest.js` mirrors
`Nostalgex/Nostalgex/Models/SchedulePoolOrdering.swift` and
`Nostalgex/Nostalgex/Services/DailyManifestScheduler.swift`, bit-for-bit, so
web and Apple TV air the same program at the same time.

**Keyword matches are ADDITIVE.** They broaden what a channel can pull in; they
never gate it. Never gate keywords on a broad genre like Drama — it leaks
unrelated titles. `keywordGatedGenres` is the deliberate exception, and it must
only name the channel's own defining genre.

**`rewatched` means `viewCount >= 3`** in both implementations.

**Config version:** 29 · **125 channels** across **14 bundles** · 42 channels whose `id` differs from their `number`.

---

## Bundles

| Bundle | Bundle ID | Channels | Range | Description |
|---|---|---|---|---|
| NOSTALGEX | `nostalgex` | 18 | CH 1–18 | The 80s and 90s. All retro, all the time |
| SCREAM | `seasonal` | 4 | CH 19–132 | Horror, all year's worth, front and centre every October |
| KIDZ ZONE | `kids` | 16 | CH 20–35 | Disney, Nickelodeon, Pixar, and more |
| PRIME TIME | `essentials` | 15 | CH 40–84 | Everyday favorites and feel-good viewing |
| MARQUEE | `premium` | 11 | CH 59–69 | Premium channels |
| ADVENTURELAND | `adventureland` | 10 | CH 70–79 | Epic quests, disasters, and adrenaline |
| OVERTIME | `sports` | 3 | CH 80–82 | Movies, shows, and docs |
| CASE FILES | `truecrime` | 5 | CH 85–89 | True crime, thrillers & mystery |
| DECADES | `decades` | 7 | CH 90–96 | Movies and shows sorted by decade |
| FRANCHISES | `franchises` | 7 | CH 100–106 | Movie franchise marathons |
| NETWORKS | `streamers` | 11 | CH 119–129 | Channels by streaming service and studio |
| TIS THE SEASON | `tis-the-season` | 1 | CH 130 | Christmas and holiday channels |
| ARTHOUSE | `arthouse` | 4 | CH 140–143 | Criterion, foreign films, midnight movies, and cult classics |
| HIGH ROTATION | `high-rotation` | 14 | CH 150–164 | Music videos by genre |

Bundled channels: 126 of 125.

---

## Channel exclusivity

Exclusive rules block a title from EVERY channel except the listed channel
`id`s. **Only lock a title to a channel when you are 95%+ sure it belongs
nowhere else — default to overlap.** Over-locking hides content: locking Die
Hard into the holiday channel made it vanish from action for eleven months of
the year.

| Locked to | Matches on | Notes |
|---|---|---|
| CH130 HOLIDAZE (id 130) | genres Holiday/Christmas, 19 title keywords, 49 editorial titles | Holiday and Christmas titles belong to HOLIDAZE for the season. Genre match plus a title allowlist plus an editorial allowlist. Die Hard, Die Hard 2 and Lethal Weapon are deliberately NOT on the list — they stay free for year-round action. |
| id 32 (missing)<br>CH60 ANIME (id 60) | genres Anime, TMDB manifest claim (`manifestExclusive`) | Anime is claimed by genre `Anime` OR by a TMDB-manifest claim (`manifestExclusive`), so manifest-claimed anime is blocked from the other animation channels even when Plex only tags it "Animation". The manifest builder gates these channels with `requireGenres: ["Animation"]` + `requireOriginalLanguage: ["ja"]` + `autoSweepCollections: false` so TMDB similar/collection noise cannot be claimed — that blocks live-action (Spy Kids) AND Western animation (An American Tail, Avatar, Castlevania). Strict Japanese anime only. Re-run the keyword tuner to apply changes. |
| CH132 SCREAM ADULTS (id 132) | 2 title keywords, 8 editorial titles | Halloween horror is claimed by a title allowlist plus the manifest, so the seasonal channel owns it rather than the year-round horror channels. |

---

## Channels by bundle

### NOSTALGEX · CH 1–18

_The 80s and 90s. All retro, all the time_

| CH | `id` | Name | Color | Type | Min items | Rules |
|---|---|---|---|---|---|---|
| 1 | `1` | REWATCHABLES MOVIES | `#FFE500` | Movies | 5 | rewatched (viewCount ≥ 3) |
| 2 | `2` | REWATCHABLES TV | `#FFD000` | Episodes | 5 | rewatched (viewCount ≥ 3) |
| 3 | `3` | NOSTALGEX LOL | `#F1C40F` | Movies | 3 | incl Comedy, no Animation/Animated, kw excl (3), 1980-1999 |
| 4 | `4` | SAT MORNING CARTOONS | `#00DD88` | Episodes | 15 | incl Animation/Kids/Children/Cartoon/Animated, 1960-1999, rated TV-Y/TV-Y7/TV-G/G/unrated |
| 5 | `5` | 90S SITCOMS | `#9B59B6` | Episodes | 10 | incl Comedy, no Anime/Animation, 1990-1999 |
| 6 | `6` | AFTER SCHOOL TV | `#F39C12` | Episodes | 5 | incl Comedy/Drama/Family, no Animation/Anime/Cartoon, 1980-1999, rated TV-G/TV-PG/TV-14/unrated |
| 7 | `7` | VHS VAULT | `#E67E22` | Movies | 5 | 1980-1999 · _time: blocks R/NC-17 before 21:00_ |
| 8 | `8` | CLASSIC FAM JAMS | `#E05A32` | Movies | 3 | needs ALL Family, no Animation/Anime, 1960-1999 |
| 9 | `9` | GIRLS NIGHT | `#FF85A1` | Movies | 3 | needs ALL Romance, no Family/Children/Kids/Action/Adventure/Horror/Thriller/Crime +4 more, kw excl (10), 1960-2004 |
| 10 | `10` | TEEN MOVIES | `#FF5E8A` | Movies | 5 | incl Comedy/Drama/Romance, no Animation/Horror/Family, title blocklist (1), kw +20, kw needs genre Comedy/Romance/Drama, kw-gated genre Comedy/Drama/Romance, 1980-1999 |
| 11 | `11` | RETRO TOONS | `#2DC7B0` | Movies | 5 | incl Animation, kw +7, kw needs genre Animation/Family/Adventure, …-1999, rated G/PG/TV-Y/TV-Y7/TV-G/TV-PG/unrated |
| 12 | `12` | ACTION ADVENTURE | `#E74C3C` | Movies | 3 | incl Action/Adventure, no Thriller/Crime/War/Horror/Animation, 1980-1999 |
| 13 | `13` | LAST ACTION HEROES | `#B7410E` | Movies | 5 | incl Action/Thriller, no Family/Kids/Children/Animation/Animated/Fantasy/Comedy, kw +13, kw needs genre Action/Thriller, 1980-2002, ≥ 85 min |
| 14 | `14` | BUDDIES | `#F39C12` | Movies | 5 | incl Action/Comedy, no Animation/Animated/Horror/Kids/Children/Family/Romance, kw +10, kw needs genre Action/Comedy, 1980-2004 |
| 15 | **`215`** ⚠︎ | CARTOON NETWORK | `#00BFFF` | Episodes | 5 | networks Cartoon Network, title allowlist (39) |
| 16 | **`225`** ⚠︎ | DVD SHELF | `#C0392B` | Movies | 5 | 2000-2009 |
| 17 | **`226`** ⚠︎ | MILLENNIAL COMEDY | `#E67E22` | Movies | 3 | incl Comedy, no Animation/Animated, kw excl (3), 2000-2009 |
| 18 | **`227`** ⚠︎ | MILLENNIAL SITCOMS | `#F1C40F` | Episodes | 10 | incl Comedy, no Anime/Animation, 2000-2009 |

### SCREAM · CH 19–132

_Horror, all year's worth, front and centre every October_

| CH | `id` | Name | Color | Type | Min items | Rules |
|---|---|---|---|---|---|---|
| 19 | **`228`** ⚠︎ | NOSTALGEX HORROR | `#8E44AD` | Movies | 3 | incl Horror, no Family/Children/Kids/Animation/Animated, 1975-1999 |
| 77 | **`141`** ⚠︎ | FRIGHT NIGHT | `#8B0000` | Any | 5 | incl Horror |
| 131 | `131` | SCREAM KIDS | `#FF8C00` | Movies | 3 | no Horror, title allowlist (37), editorial always-in (43), rated G/PG/TV-Y/TV-Y7/TV-G/TV-PG |
| 132 | `132` | SCREAM ADULTS | `#8B0000` | Movies | 3 | incl Horror/Thriller, no Family/Children/Kids/Animation/Animated, title allowlist (53), title blocklist (11), rated R/NC-17/PG-13/TV-MA |

### KIDZ ZONE · CH 20–35

_Disney, Nickelodeon, Pixar, and more_

| CH | `id` | Name | Color | Type | Min items | Rules |
|---|---|---|---|---|---|---|
| 20 | `20` | FAMILY HOUR | `#00C4FF` | Movies | 10 | needs ALL Family, rated G/PG/PG-13/unrated |
| 21 | `21` | DIZ FLICKS | `#7B2FBE` | Movies | 3 | studios Disney/Walt Disney/Walt Disney Pictures +1 more, rated G/PG/PG-13/TV-Y/TV-Y7/TV-G/TV-PG/TV-14/unrated |
| 22 | `22` | DIZNEY TOONS | `#9C27B0` | Movies | 3 | needs ALL Animation, studios Disney/Walt Disney/Walt Disney Pictures +1 more, rated G/PG/PG-13/TV-Y/TV-Y7/TV-G/TV-PG/unrated |
| 23 | `23` | DIZ JUNIOR | `#7B68EE` | Episodes | 3 | studios Disney Junior/Disney Television Animation/Ludo Studio +3 more, title allowlist (19), 2010-…, rated TV-Y/TV-Y7/TV-G/G/unrated |
| 24 | `24` | DIZ TV | `#AB47BC` | Episodes | 3 | studios Disney/Disney Channel/Disney Television Animation +2 more, networks Disney Channel/Disney XD/Disney+, rated TV-Y/TV-Y7/TV-G/TV-PG/TV-14/G/PG/unrated |
| 25 | `25` | ANIMATION | `#FF5722` | Movies | 5 | incl Animation, prodCo DreamWorks Animation/Sony Pictures Animation/Warner Bros. Animation +9 more, rated G/PG/PG-13/TV-G/TV-PG/unrated |
| 26 | `26` | SLIME TV | `#FF6600` | Episodes | 3 | studios Nickelodeon/Nickelodeon Animation Studio/Nickelodeon Productions +4 more, rated TV-Y/TV-Y7/TV-G/TV-PG/TV-14/G/PG/unrated |
| 27 | `27` | PIXAR MOVIES | `#00B894` | Movies | 3 | studios Pixar/Pixar Animation Studios, prodCo Pixar Animation Studios/Pixar, rated G/PG/PG-13/TV-Y/TV-Y7/TV-G/TV-PG/unrated |
| 28 | `28` | MINION HQ | `#FDCB6E` | Movies | 3 | studios Illumination/Illumination Entertainment, prodCo Illumination Entertainment/Illumination |
| 29 | `29` | TWEEN TV | `#FF69B4` | Episodes | 5 | no Animation/Anime/Cartoon, studios Disney Channel/Nickelodeon/Nickelodeon Productions +7 more, title allowlist (26), 1989-…, rated TV-G/TV-PG/TV-Y7/unrated |
| 30 | `30` | TEEN DRAMA | `#E74C8B` | Episodes | 5 | incl Drama/Romance/Comedy, no Animation/Anime, kw +7, kw excl (8), 2000-…, rated TV-14/TV-PG |
| 31 | **`33`** ⚠︎ | FAMILY TV | `#FF7043` | Episodes | 10 | incl Family/Comedy/Drama, no Kids/Children/Cartoon, 2000-…, rated TV-G/TV-PG/TV-14/unrated |
| 32 | **`34`** ⚠︎ | NETFLIX KIDS | `#E50914` | Any | 3 | incl Family/Kids/Children/Comedy/Adventure, no Horror/Thriller, studios Netflix/Netflix Animation/Netflix Family, title allowlist (28), rated TV-Y/TV-Y7/TV-G/G/PG/TV-PG/unrated |
| 33 | **`216`** ⚠︎ | MILLENNIUM CARTOONS | `#1ABC9C` | Episodes | 5 | incl Animation/Kids/Children/Cartoon/Animated, 2000-2029, rated TV-Y/TV-Y7/TV-G/G/TV-PG/unrated |
| 34 | **`218`** ⚠︎ | DREAMWORKS | `#2ECC71` | Any | 5 | studios DreamWorks Animation/Pacific Data Images, rated G/PG/PG-13/TV-Y/TV-Y7/TV-G/TV-PG/unrated |
| 35 | **`220`** ⚠︎ | TOON TOWN | `#FF9F1C` | Movies | 5 | kw +1, rated G/PG/PG-13/unrated |

### PRIME TIME · CH 40–84

_Everyday favorites and feel-good viewing_

| CH | `id` | Name | Color | Type | Min items | Rules |
|---|---|---|---|---|---|---|
| 40 | **`50`** ⚠︎ | SITCOMS | `#9B59B6` | Episodes | 10 | incl Comedy, no Animation/Anime/Kids/Children/Family, kw +7 |
| 41 | **`51`** ⚠︎ | FLICKS | `#FF6600` | Movies | 10 | no Horror/Kids/Children/Family |
| 42 | **`52`** ⚠︎ | ROM COMS | `#FF85A1` | Movies | 50 | needs ALL Romance + Comedy, no Horror/Thriller/Action/Animation/Family |
| 43 | **`53`** ⚠︎ | FEEL GOOD TV | `#7ED957` | Episodes | 5 | title allowlist (51) |
| 44 | **`54`** ⚠︎ | REALITY TV | `#FF4500` | Episodes | 5 | incl Reality/Reality-TV/Docuseries, no Game Show/Game-Show/Competition |
| 45 | **`56`** ⚠︎ | DOCS | `#2E86C1` | Any | 5 | incl Documentary, no Sport, kw +7, kw needs genre Documentary |
| 46 | **`57`** ⚠︎ | LOL | `#F1C40F` | Movies | 5 | incl Comedy, no Horror/War/History/Documentary, kw excl (3), Plex rating ≥ 7 |
| 47 | **`59`** ⚠︎ | MAN CAVE | `#4A6741` | Episodes | 3 | incl Crime/Action, no Family/Children/Kids, title allowlist (8) |
| 48 | **`66`** ⚠︎ | BLOCKBUSTER | `#F39C12` | Movies | 5 | incl Action/Adventure/Science Fiction, Plex rating ≥ 6 |
| 49 | **`62`** ⚠︎ | FRESH | `#00E5FF` | Movies | 3 | released ≤ 6 mo ago, ≥ 60 min |
| 50 | **`200`** ⚠︎ | DRAMA TV | `#5A3E8A` | Episodes | 10 | incl Drama, no Animation/Comedy/Documentary/Horror/Reality/Kids/Children/Family, kw +5, kw needs genre Drama |
| 51 | **`210`** ⚠︎ | RECORD STORE | `#FF6B35` | Movies | 3 | incl Music, kw excl (4) |
| 53 | **`223`** ⚠︎ | PREMIERES | `#F72585` | Any | 1 | incl Action/Adventure/Animation/Anime/Biography/Cartoon +23 more, added ≤ 14 d ago |
| 83 | **`224`** ⚠︎ | HISTORY & BIO | `#A0522D` | Movies | 5 | incl History/Biography, no Documentary/Docuseries/Animation/Animated |
| 84 | **`222`** ⚠︎ | R RATED COMEDY | `#E84393` | Movies | 5 | incl Comedy, no Animation/Family/Children/Kids, title blocklist (6), 1995-2029, rated R |

### MARQUEE · CH 59–69

_Premium channels_

| CH | `id` | Name | Color | Type | Min items | Rules |
|---|---|---|---|---|---|---|
| 59 | **`217`** ⚠︎ | SKETCH COMEDY | `#5DADE2` | Episodes | 3 | incl Comedy/Talk Show/News, title allowlist (24) |
| 60 | `60` | ANIME | `#FF3D6E` | Any | 3 | **TMDB manifest only**, incl Animation, editorial always-in (138), kw +7, kw needs genre Animation/Action & Adventure/Sci-Fi & Fantasy |
| 61 | `61` | MUSICALS | `#C2185B` | Movies | 3 | incl Music/Musical, kw +5, kw needs genre Music/Comedy/Romance, kw-gated genre Music |
| 62 | **`55`** ⚠︎ | GAME SHOWS | `#FFB300` | Episodes | 3 | incl Game Show/Game-Show/Competition, title allowlist (30) |
| 63 | `63` | ADULT CARTOONS | `#8E44AD` | Episodes | 3 | incl Animation/Animated/Cartoon, title allowlist (21) |
| 64 | `64` | DATE NIGHT | `#E74C8B` | Movies | 3 | needs ALL Romance, no Horror/Animation/Family/Children/Kids, kw +7, kw excl (2) |
| 65 | **`58`** ⚠︎ | STAND-UP | `#F5B041` | Any | 3 | **TMDB manifest only**, incl Comedy/Documentary, kw +2, kw needs genre Comedy |
| 66 | **`201`** ⚠︎ | BIOPICS | `#C9A84C` | Movies | 5 | kw +6 |
| 67 | `67` | ALL TIME GREATS | `#FFD700` | Movies | 5 | Plex rating ≥ 8.2, ≥ 60 min |
| 68 | `68` | CERTIFIED GOLD | `#F56040` | Movies | 3 | Plex rating ≥ 8, ≥ 60 min |
| 69 | `69` | OSCAR WINNERS | `#FFD700` | Movies | 3 | title allowlist (44) |

### ADVENTURELAND · CH 70–79

_Epic quests, disasters, and adrenaline_

| CH | `id` | Name | Color | Type | Min items | Rules |
|---|---|---|---|---|---|---|
| 70 | `70` | EPIC ADVENTURES | `#D4A017` | Movies | 3 | incl Adventure/Fantasy, no Animation/Animated/Family/Children/Kids, ≥ 110 min |
| 71 | `71` | DISASTER MOVIES | `#E67E22` | Movies | 3 | no Animation/Animated/Family/Fantasy/Romance, title allowlist (23), title blocklist (8) |
| 72 | `72` | RUSH | `#E74C3C` | Movies | 5 | incl Action/Thriller, no Family/Kids/Children/Animation/Animated/Fantasy, kw +10, 2000-…, Plex rating ≥ 5.5, ≥ 80 min |
| 73 | `73` | SCI-FI | `#16A0C8` | Movies | 5 | incl Science Fiction/Horror, needs ALL Science Fiction, no Animation/Family/Kids, kw +8, kw needs genre Science Fiction |
| 74 | `74` | FANTASY | `#8E44AD` | Movies | 5 | incl Fantasy/Adventure, no Animation/Horror/Science Fiction, kw +7, kw needs genre Fantasy/Adventure |
| 75 | `75` | WESTERNS | `#B9770E` | Any | 3 | incl Western, kw +7, kw needs genre Western |
| 76 | `76` | FRONT LINE | `#5D6D7E` | Any | 3 | incl War/War & Politics, no Documentary/Docuseries/Animation/Animated, kw +16, kw needs genre War/War & Politics/History/Biography |
| 77 | **`141`** ⚠︎ | FRIGHT NIGHT | `#8B0000` | Any | 5 | incl Horror |
| 78 | **`65`** ⚠︎ | SUPERHERO MOVIES | `#E74C3C` | Movies | 3 | title allowlist (31), title blocklist (5) |
| 79 | **`219`** ⚠︎ | SPY GAMES | `#34495E` | Movies | 5 | kw +8, kw needs genre Action/Thriller/Adventure/Comedy |

### OVERTIME · CH 80–82

_Movies, shows, and docs_

| CH | `id` | Name | Color | Type | Min items | Rules |
|---|---|---|---|---|---|---|
| 80 | `80` | LOCKERROOM | `#1DB954` | Movies | 3 | incl Sport/Sports/Sports Film |
| 81 | `81` | OVERTIME TV | `#2ECC71` | Episodes | 3 | incl Sport/Sports, title allowlist (1) |
| 82 | `82` | SPORTS DOCS | `#27AE60` | Any | 3 | incl Documentary, needs ALL Sport |

### CASE FILES · CH 85–89

_True crime, thrillers & mystery_

| CH | `id` | Name | Color | Type | Min items | Rules |
|---|---|---|---|---|---|---|
| 85 | **`40`** ⚠︎ | TRUE CRIME | `#7B241C` | Any | 1 | incl Documentary/Docuseries, needs ALL Documentary, kw +17, kw-gated genre Documentary/Docuseries |
| 86 | **`41`** ⚠︎ | CRIME FLICKS | `#A93226` | Movies | 5 | incl Crime, no Documentary, kw +7, kw needs genre Crime |
| 87 | **`42`** ⚠︎ | THRILLERS | `#5B2C6F` | Movies | 5 | incl Thriller, no Horror/Documentary, kw +7, kw needs genre Thriller/Crime |
| 88 | **`43`** ⚠︎ | MYSTERY | `#1A5276` | Movies | 3 | incl Mystery, no Horror/Documentary, kw +6, kw needs genre Mystery/Crime/Thriller |
| 89 | **`44`** ⚠︎ | CRIME TV | `#784212` | Episodes | 3 | incl Crime, no Documentary/Animation, kw +6, kw needs genre Crime |

### DECADES · CH 90–96

_Movies and shows sorted by decade_

| CH | `id` | Name | Color | Type | Min items | Rules |
|---|---|---|---|---|---|---|
| 90 | `90` | THE 60S | `#C0392B` | Any | 5 | 1960-1969, Plex rating ≥ 6 |
| 91 | `91` | THE 70S | `#D2691E` | Any | 5 | 1970-1979, Plex rating ≥ 6 |
| 92 | `92` | THE 80S | `#FF1493` | Any | 5 | 1980-1989, Plex rating ≥ 6 |
| 93 | `93` | THE 90S | `#00CED1` | Any | 5 | 1990-1999, Plex rating ≥ 6 |
| 94 | `94` | THE 00S | `#7B68EE` | Any | 5 | 2000-2009, Plex rating ≥ 6 |
| 95 | `95` | THE 10S | `#20B2AA` | Any | 5 | 2010-2019, Plex rating ≥ 6 |
| 96 | `96` | THE 20S | `#FF6347` | Any | 5 | 2020-2029, Plex rating ≥ 6 |

### FRANCHISES · CH 100–106

_Movie franchise marathons_

| CH | `id` | Name | Color | Type | Min items | Rules |
|---|---|---|---|---|---|---|
| 100 | `100` | STAR WARS | `#FFE81F` | Movies | 3 | title allowlist (1) |
| 101 | `101` | MARVEL | `#E74C3C` | Movies | 3 | studios Marvel Studios |
| 102 | `102` | HARRY POTTER | `#7B68EE` | Movies | 3 | title allowlist (2) |
| 103 | `103` | JURASSIC PARK | `#2ECC71` | Any | 3 | title allowlist (4) |
| 104 | `104` | LORD OF THE RINGS | `#D4A017` | Movies | 3 | title allowlist (2) |
| 105 | `105` | MISSION IMPOSSIBLE | `#C0392B` | Movies | 3 | title allowlist (2) |
| 106 | `106` | JASON BOURNE | `#566573` | Movies | 3 | title allowlist (1) |

### NETWORKS · CH 119–129

_Channels by streaming service and studio_

| CH | `id` | Name | Color | Type | Min items | Rules |
|---|---|---|---|---|---|---|
| 119 | **`221`** ⚠︎ | MIRAMAX | `#C0392B` | Movies | 3 | studios Miramax/Miramax Films/Dimension Films, prodCo Miramax/Dimension Films |
| 120 | `120` | HBO | `#8B5CF6` | Any | 5 | studios HBO/HBO Films/HBO Max, networks HBO/Max/HBO Max, title allowlist (52) |
| 121 | `121` | APPLE TV+ | `#5AC8FA` | Any | 3 | studios Apple TV+/Apple/Apple Studios, networks Apple TV+, title allowlist (80) |
| 122 | `122` | NETFLIX | `#E50914` | Any | 3 | studios Netflix/Netflix Animation/Netflix Studios +2 more, networks Netflix, title allowlist (40), editorial always-in (4) |
| 123 | `123` | PARAMOUNT+ | `#0064FF` | Any | 3 | studios Paramount+/Paramount Television/Paramount Television Studios +3 more, networks Paramount+/Paramount Network/Showtime +4 more, title allowlist (22) |
| 124 | `124` | AMAZON | `#00A8E1` | Any | 3 | studios Amazon/Amazon Studios/Amazon MGM Studios +3 more, networks Amazon Prime Video/Prime Video/Amazon, title allowlist (30) |
| 125 | `125` | HULU | `#1CE783` | Any | 3 | studios Hulu/Hulu Originals/Onyx Collective +2 more, networks Hulu, title allowlist (28) |
| 126 | `126` | SONY | `#374151` | Movies | 3 | studios Sony/Sony Pictures/Sony Pictures Television +3 more, prodCo Columbia Pictures/Sony Pictures/TriStar Pictures +2 more |
| 127 | `127` | WARNER BROS | `#B8860B` | Movies | 3 | studios Warner Bros./Warner Bros. Pictures/Warner Bros. Television +3 more, prodCo Warner Bros. Pictures/New Line Cinema/Castle Rock Entertainment +2 more |
| 128 | `128` | UNIVERSAL | `#00A651` | Movies | 3 | studios Universal/Universal Pictures/Universal Television +3 more, prodCo Universal Pictures/DreamWorks Pictures/DreamWorks Animation +2 more |
| 129 | `129` | 20TH CENTURY | `#C8A951` | Movies | 3 | studios 20th Century Fox/20th Century Studios/20th Television +5 more, prodCo 20th Century Fox/20th Century Studios/Searchlight Pictures +2 more |

### TIS THE SEASON · CH 130

_Christmas and holiday channels_

| CH | `id` | Name | Color | Type | Min items | Rules |
|---|---|---|---|---|---|---|
| 130 | `130` | HOLIDAZE | `#C41E3A` | Movies | 3 | incl Holiday/Christmas, title allowlist (19), editorial always-in (96), Plex rating ≥ 5 |

### ARTHOUSE · CH 140–143

_Criterion, foreign films, midnight movies, and cult classics_

| CH | `id` | Name | Color | Type | Min items | Rules |
|---|---|---|---|---|---|---|
| 140 | **`211`** ⚠︎ | CRITERION | `#F5E6C8` | Movies | 3 | **TMDB manifest only** |
| 141 | **`212`** ⚠︎ | FOREIGN FILMS | `#2C3E50` | Movies | 3 | kw +10, **IMDb ≥ 6.5**, **IMDb votes ≥ 5,000** |
| 142 | **`213`** ⚠︎ | MIDNIGHT | `#1A0A2E` | Movies | 3 | kw +9 |
| 143 | **`214`** ⚠︎ | CULT CLASSICS | `#6C1C8A` | Movies | 3 | kw +5, **IMDb votes ≥ 30,000** |

### HIGH ROTATION · CH 150–164

_Music videos by genre_

| CH | `id` | Name | Color | Type | Min items | Rules |
|---|---|---|---|---|---|---|
| 150 | `150` | HIGH ROTATION | `#FF2DB4` | Any | 3 | source: music videos |
| 151 | `151` | POP | `#FF2DB4` | Any | 3 | source: music videos, incl Pop |
| 152 | `152` | ROCK'N | `#FF2DB4` | Any | 3 | source: music videos, incl Rock/Hard Rock/Classic Rock |
| 153 | `153` | COUNTRY SWAGGER | `#FF2DB4` | Any | 3 | source: music videos, incl Country/Country Rock |
| 154 | `154` | BALLIN | `#FF2DB4` | Any | 3 | source: music videos, incl Hip-Hop/Hip Hop |
| 155 | `155` | RAP GODS | `#FF2DB4` | Any | 3 | source: music videos, incl Rap |
| 156 | `156` | ALT ROCK | `#FF2DB4` | Any | 3 | source: music videos, incl Alternative/Indie Rock/Alternative Rock |
| 157 | `157` | SLOW JAMS | `#FF2DB4` | Any | 3 | source: music videos, incl R&B/Soul/Acoustic |
| 159 | `159` | Y2K | `#FF2DB4` | Any | 3 | source: music videos, 2000-2019 |
| 160 | `160` | CURRENT SPIN | `#FF2DB4` | Any | 3 | source: music videos, 2020-2100 |
| 161 | `161` | DANCE FLOOR | `#FF2DB4` | Any | 3 | source: music videos, incl Electronic/Dance/House/Techno/EDM/Trance |
| 162 | `162` | CALIENTE | `#FF2DB4` | Any | 3 | source: music videos, incl Latin/Reggaeton |
| 163 | `163` | HEADBANGERS | `#FF2DB4` | Any | 3 | source: music videos, incl Metal |
| 164 | `164` | GET DOWN | `#FF2DB4` | Any | 3 | source: music videos, incl Funk/Disco |

---

## `id` ≠ `number`

42 channels whose manifest/exclusivity key (`id`) is not their on-screen number. Marked ⚠︎ in the tables above.

| `id` | Airs as | Name |
|---|---|---|
| `215` | CH15 | CARTOON NETWORK |
| `225` | CH16 | DVD SHELF |
| `226` | CH17 | MILLENNIAL COMEDY |
| `227` | CH18 | MILLENNIAL SITCOMS |
| `228` | CH19 | NOSTALGEX HORROR |
| `33` | CH31 | FAMILY TV |
| `34` | CH32 | NETFLIX KIDS |
| `216` | CH33 | MILLENNIUM CARTOONS |
| `218` | CH34 | DREAMWORKS |
| `220` | CH35 | TOON TOWN |
| `50` | CH40 | SITCOMS |
| `51` | CH41 | FLICKS |
| `52` | CH42 | ROM COMS |
| `53` | CH43 | FEEL GOOD TV |
| `54` | CH44 | REALITY TV |
| `56` | CH45 | DOCS |
| `57` | CH46 | LOL |
| `59` | CH47 | MAN CAVE |
| `66` | CH48 | BLOCKBUSTER |
| `62` | CH49 | FRESH |
| `200` | CH50 | DRAMA TV |
| `210` | CH51 | RECORD STORE |
| `223` | CH53 | PREMIERES |
| `217` | CH59 | SKETCH COMEDY |
| `55` | CH62 | GAME SHOWS |
| `58` | CH65 | STAND-UP |
| `201` | CH66 | BIOPICS |
| `141` | CH77 | FRIGHT NIGHT |
| `65` | CH78 | SUPERHERO MOVIES |
| `219` | CH79 | SPY GAMES |
| `224` | CH83 | HISTORY & BIO |
| `222` | CH84 | R RATED COMEDY |
| `40` | CH85 | TRUE CRIME |
| `41` | CH86 | CRIME FLICKS |
| `42` | CH87 | THRILLERS |
| `43` | CH88 | MYSTERY |
| `44` | CH89 | CRIME TV |
| `221` | CH119 | MIRAMAX |
| `211` | CH140 | CRITERION |
| `212` | CH141 | FOREIGN FILMS |
| `213` | CH142 | MIDNIGHT |
| `214` | CH143 | CULT CLASSICS |

---

_Generated from `channels.json` v29 by `scripts/render-channels-doc.mjs`. Do not edit by hand._
