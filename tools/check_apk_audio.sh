#!/usr/bin/env bash
# Check that an exported APK contains every sound the game uses.
#
# Wired sounds are the res:// .wav/.ogg/.mp3 paths referenced by game
# scripts, scenes and resources (tools/ and tests/ excluded). For each one
# the APK must hold the import remap (assets/<path>.import) and a non-empty
# imported stream (assets/.godot/imported/<file>-<hash>.sample,
# .oggvorbisstr or .mp3str). Without them the build plays nothing.
#
# Usage: ./tools/check_apk_audio.sh path/to/game.apk
set -euo pipefail

apk="${1:?usage: $0 path/to/game.apk}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

listing="$(mktemp)"
trap 'rm -f "$listing"' EXIT
unzip -l "$apk" | awk 'NR > 3 && $1 ~ /^[0-9]+$/ { size = $1; $1 = $2 = $3 = ""; sub(/^ +/, ""); print size "\t" $0 }' > "$listing"

mapfile -t sounds < <(
  git ls-files '*.gd' '*.tscn' '*.tres' | grep -vE '^(tools|tests)/' \
    | xargs grep -ohE 'res://[^"]+\.(wav|ogg|mp3)' | sort -u
)
if [[ "${#sounds[@]}" -eq 0 ]]; then
  echo "error: no wired sounds found in the project" >&2
  exit 1
fi

missing=0
for res in "${sounds[@]}"; do
  path="${res#res://}"
  file="$(basename "$path")"
  if ! grep -qF $'\t'"assets/${path}.import" "$listing"; then
    echo "MISSING ${path}.import" >&2
    missing=1
  fi
  if ! awk -F'\t' -v f="$file" '
      index($2, "assets/.godot/imported/" f "-") == 1 && $2 ~ /\.(sample|oggvorbisstr|mp3str)$/ && $1 > 0 { ok = 1 }
      END { exit ok ? 0 : 1 }' "$listing"; then
    echo "MISSING imported stream for ${path}" >&2
    missing=1
  fi
done

if [[ "${missing}" -ne 0 ]]; then
  echo "error: APK is missing audio for wired sounds" >&2
  exit 1
fi
echo "APK audio: ok (${#sounds[@]} wired sounds present in $(basename "$apk"))"
