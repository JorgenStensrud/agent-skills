#!/usr/bin/env bash
# Kjører garmin.py med garminconnect hentet av uvx, så ingenting må installeres
# globalt. Første kjøring laster ned pakken; etterpå ligger den i uv sin cache.
#
# Exit: 2 ikke innlogget, 3 feil input, 4 mangler kjøretid, 5 Garmin avviste
set -euo pipefail
her="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v uvx >/dev/null 2>&1; then
  echo "garmin: uvx mangler. Installer uv: https://docs.astral.sh/uv/" >&2
  exit 4
fi

# --with garminconnect gir biblioteket; skriptet kjøres med systemets python via uv.
exec uvx --quiet --from garminconnect --with garminconnect python "$her/garmin.py" "$@"
