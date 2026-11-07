#!/usr/bin/env bash
# Idempotent Godot install for local and cloud agent environments.
# Pins the same stable binary CI uses. Agents must run this once when doctor
# reports Godot missing, never via ad-hoc find/curl loops mid-task.
#
# Usage:
#   ./tools/ensure_godot.sh
#   GODOT_VERSION=4.7.2 ./tools/ensure_godot.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

GODOT_VERSION="${GODOT_VERSION:-4.7.2}"
want_major_minor="${GODOT_VERSION%.*}"
if [[ -f project.godot ]]; then
  project_mm="$(sed -n 's/^config\/features=PackedStringArray(\(.*\))$/\1/p' project.godot \
    | tr ',' '\n' | tr -d ' "' | grep -E '^[0-9]+\.[0-9]+$' | head -n 1 || true)"
  if [[ -n "${project_mm}" && "${project_mm}" != "${want_major_minor}" ]]; then
    echo "ensure_godot: project.godot wants ${project_mm}.x but GODOT_VERSION=${GODOT_VERSION}" >&2
    exit 2
  fi
fi

bin_name="Godot_v${GODOT_VERSION}-stable_linux.x86_64"
url="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/${bin_name}.zip"

have_matching() {
  local candidate="$1" ver
  [[ -n "${candidate}" ]] || return 1
  command -v "${candidate}" >/dev/null 2>&1 || [[ -x "${candidate}" ]] || return 1
  ver="$("${candidate}" --version 2>/dev/null || true)"
  [[ "${ver}" == "${want_major_minor}".* ]]
}

if [[ -n "${GODOT:-}" ]] && have_matching "${GODOT}"; then
  echo "ensure_godot: already ok GODOT=${GODOT} ($("${GODOT}" --version))"
  exit 0
fi
if have_matching godot; then
  echo "ensure_godot: already ok PATH godot ($(godot --version))"
  exit 0
fi

dest_dir="${FLAGORIA_GODOT_PREFIX:-/usr/local/bin}"
dest="${dest_dir}/godot"
tmpdir="$(mktemp -d)"
cleanup() { rm -rf "${tmpdir}"; }
trap cleanup EXIT

echo "ensure_godot: installing Godot ${GODOT_VERSION} to ${dest}"
curl -fsSL -o "${tmpdir}/godot.zip" "${url}"
unzip -q -o "${tmpdir}/godot.zip" -d "${tmpdir}/out"
src="${tmpdir}/out/${bin_name}"
if [[ ! -f "${src}" ]]; then
  echo "ensure_godot: zip missing ${bin_name}" >&2
  ls -la "${tmpdir}/out" >&2 || true
  exit 1
fi

if [[ -w "${dest_dir}" ]]; then
  install -m 755 "${src}" "${dest}"
elif command -v sudo >/dev/null 2>&1; then
  sudo install -m 755 "${src}" "${dest}"
else
  dest_dir="${HOME}/.local/bin"
  dest="${dest_dir}/godot"
  mkdir -p "${dest_dir}"
  install -m 755 "${src}" "${dest}"
  echo "ensure_godot: installed to ${dest} (add ${dest_dir} to PATH)"
fi

if ! have_matching "${dest}"; then
  echo "ensure_godot: installed binary failed version check" >&2
  "${dest}" --version >&2 || true
  exit 1
fi

echo "ensure_godot: ok ${dest} ($("${dest}" --version))"
