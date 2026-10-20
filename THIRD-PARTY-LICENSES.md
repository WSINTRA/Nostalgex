# Third-party licenses

Nostalgex itself is MIT (see `LICENSE`). It ships with the following third-party work.

## Fonts (bundled in the tvOS app)

| Font | Copyright | License |
|---|---|---|
| VT323 | 2011, The VT323 Project Authors (peter.hull@oikoi.com) | SIL Open Font License 1.1, `Nostalgex/Nostalgex/OFL-VT323.txt` |
| DM Mono | 2020, The DM Mono Project Authors (github.com/googlefonts/dm-mono) | SIL Open Font License 1.1, `Nostalgex/Nostalgex/OFL-DMMono.txt` |

The web tuner and site load their fonts from Google Fonts at runtime and do not redistribute them.

## Self-hosted web tuner (Docker image)

The image (`npm run build:selfhost`) bundles these from npm instead of loading them from a CDN. Each license ships in the image under `vendor/licenses/`.

| Package | License |
|---|---|
| hls.js 1.5.17 | Apache License 2.0 |
| qrcodejs 1.0.0 | MIT |
| VT323, Press Start 2P, Silkscreen, Space Mono, Bricolage Grotesque (via @fontsource) | SIL Open Font License 1.1 |
| nginx (base image `nginxinc/nginx-unprivileged`) | 2-clause BSD |

## Swift packages

| Package | License |
|---|---|
| TelemetryDeck SwiftSDK (github.com/TelemetryDeck/SwiftSDK) | MIT |
