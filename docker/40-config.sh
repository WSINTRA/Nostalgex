#!/bin/sh
# Writes the tuner's runtime config from the environment. nginx serves it at
# /config.json (see docker/nginx.conf). Runs from the nginx image's entrypoint,
# as the unprivileged nginx user, before nginx starts.
#
#   NOSTALGEX_ENRICHMENT=on   (default) TMDB/OMDb metadata from the shared cache and
#                             the nostalgex.app relay. Only TMDB and IMDb ids are sent.
#   NOSTALGEX_ENRICHMENT=off  no Supabase or relay requests at all.
#
# tunerVersion is what Settings shows as WEB TUNER 1.0.3 · DOCKER. It comes from
# NOSTALGEX_TUNER_VERSION, which the image sets from its build arg (the release tag's
# version), else from the config.json the build wrote next to the pages (package.json
# "tunerVersion"). Neither: an empty string, and Settings shows no version line.
set -eu

raw="${NOSTALGEX_ENRICHMENT:-on}"
case "$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')" in
  on|true|1|yes) enrichment=true ;;
  off|false|0|no) enrichment=false ;;
  *)
    # A typo should not quietly send requests someone tried to turn off.
    echo "$0: NOSTALGEX_ENRICHMENT must be on or off, got '$raw'. Treating it as off." >&2
    enrichment=false
    ;;
esac

safe_version() {
  case "$1" in
    ''|*[!A-Za-z0-9._-]*) return 1 ;;
  esac
}

version="${NOSTALGEX_TUNER_VERSION:-}"
if ! safe_version "$version"; then
  version="$(sed -n 's/.*"tunerVersion"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    /usr/share/nginx/html/config.json 2>/dev/null | head -n 1)"
  safe_version "$version" || version=
fi

mkdir -p /tmp/nostalgex
printf '{"tunerVersion":"%s","musicLookups":false,"enrichment":%s}\n' "$version" "$enrichment" \
  > /tmp/nostalgex/config.json

label="${version:-(no version)}"
if [ "$enrichment" = true ]; then
  echo "$0: Nostalgex tuner $label, metadata enrichment on (NOSTALGEX_ENRICHMENT=off turns it off)"
else
  echo "$0: Nostalgex tuner $label, metadata enrichment off"
fi
