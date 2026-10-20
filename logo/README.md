# Nostalgex brand

The brand is the one on [nostalgex.app](https://www.nostalgex.app): the NOSTALGEX wordmark with a TV for the O. Use it for anything new, on any platform.

## Logos

| File | Use |
|---|---|
| `nostalgex-white.svg` | Wordmark on dark backgrounds (cream letters) |
| `nostalgex-black.svg` | Wordmark on light backgrounds |
| `icon-white.svg`, `icon-black.svg` | The TV on its own, for small spaces and app icons |
| `png/` | The same at fixed sizes with transparent backgrounds, for platforms that can't draw SVG (Roku, for one). The `1600w` files are the masters; scale down from those. |

`old-nostalgex.svg`, `old-logo@4x-8.png` and `old-favicon.png` are the previous lightning-bolt logo. Don't use them for new work.

## Colours

From the site's `styles.css`.

| Name | Hex | Notes |
|---|---|---|
| Pink | `#F838AC` | |
| Cyan | `#2BC7F5` | |
| Yellow | `#FFD91C` | |
| Orange | `#FF8A3D` | |
| Paper | `#FAF4E8` | Cream. Light backgrounds, and the wordmark's letters on dark |
| Ink | `#141414` | Text on light |
| Navy | `#11142B` | Matches the app's UI background |
| Sunset | Pink to orange to yellow | `linear-gradient(100deg, #F838AC 5%, #FF8A3D 48%, #FFD91C 95%)` |

The TV in the wordmark has its own gradient: `#E7588A`, `#ED683C`, `#F3903F`, `#FDC70C`.

The site's dark theme swaps Paper to `#0E1018`, Ink to `#F7F1E3` and Navy to `#1B2044`.

## Fonts

- **Bricolage Grotesque** for headings, **Space Mono** for labels and buttons. Both are on Google Fonts.
- Inside the TV guide, the Apple TV app uses DM Mono (bundled in `Nostalgex/Nostalgex/`). Keep the guide matching the Apple TV app; the fonts above are for branding around it.
