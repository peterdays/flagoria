#!/usr/bin/env bash
# Single CI path to install Godot 4.7.2 (and optional export templates).
# Called from .github/actions/install-godot after actions/cache restore.
# Do not duplicate curl/unzip Godot installs in workflow YAML.
set -euo pipefail

GODOT_VERSION="${GODOT_VERSION:-4.7.2}"
INSTALL_TEMPLATES="${FLAGORIA_CI_GODOT_TEMPLATES:-0}"
VERIFY_SHA512="${FLAGORIA_CI_GODOT_VERIFY_SHA512:-0}"
CACHE_ROOT="${FLAGORIA_GODOT_CACHE_DIR:-${HOME}/.cache/flagoria-godot/${GODOT_VERSION}}"
WORKSPACE="${GITHUB_WORKSPACE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

bin_name="Godot_v${GODOT_VERSION}-stable_linux.x86_64"
zip_name="${bin_name}.zip"
base_url="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable"

mkdir -p "${CACHE_ROOT}"

if [[ ! -x "${CACHE_ROOT}/${bin_name}" ]]; then
  zip_path="${CACHE_ROOT}/${zip_name}"
  if [[ ! -f "${zip_path}" ]]; then
    echo "ci_install_godot: downloading ${zip_name}"
    curl -fsSL -o "${zip_path}" "${base_url}/${zip_name}"
  else
    echo "ci_install_godot: using cached zip ${zip_path}"
  fi
  if [[ "${VERIFY_SHA512}" == "1" ]]; then
    sha_file="${WORKSPACE}/docker/godot-${GODOT_VERSION}-linux.sha512"
    if [[ ! -f "${sha_file}" ]]; then
      echo "ci_install_godot: missing ${sha_file}" >&2
      exit 1
    fi
    (cd "${CACHE_ROOT}" && sha512sum -c "${sha_file}")
  fi
  extract="${CACHE_ROOT}/.extract"
  rm -rf "${extract}"
  mkdir -p "${extract}"
  unzip -q -o "${zip_path}" -d "${extract}"
  install -m 755 "${extract}/${bin_name}" "${CACHE_ROOT}/${bin_name}"
  rm -rf "${extract}"
else
  echo "ci_install_godot: using cached binary ${CACHE_ROOT}/${bin_name}"
fi

if command -v sudo >/dev/null 2>&1 && [[ ! -w /usr/local/bin ]]; then
  sudo install -m 755 "${CACHE_ROOT}/${bin_name}" /usr/local/bin/godot
else
  install -m 755 "${CACHE_ROOT}/${bin_name}" /usr/local/bin/godot
fi
godot --version

if [[ "${INSTALL_TEMPLATES}" == "1" ]]; then
  tpl_cache="${CACHE_ROOT}/export_templates"
  dest="${HOME}/.local/share/godot/export_templates/${GODOT_VERSION}.stable"
  if [[ ! -f "${tpl_cache}/version.txt" ]]; then
    tpz="${CACHE_ROOT}/export_templates.tpz"
    if [[ ! -f "${tpz}" ]]; then
      echo "ci_install_godot: downloading export templates ${GODOT_VERSION}"
      curl -fsSL -o "${tpz}" "${base_url}/Godot_v${GODOT_VERSION}-stable_export_templates.tpz"
    fi
    mkdir -p "${tpl_cache}"
    unzip -q -j "${tpz}" 'templates/android_*' 'templates/version.txt' -d "${tpl_cache}"
  else
    echo "ci_install_godot: using cached export templates"
  fi
  mkdir -p "${dest}"
  cp -a "${tpl_cache}/." "${dest}/"
  ls "${dest}"
fi
