#!/usr/bin/env bash
# Write Godot editor_settings with Android SDK and JDK paths for CI export.
# Keystore env vars must already be set on GITHUB_ENV when this runs.
set -euo pipefail

GODOT_VERSION="${GODOT_VERSION:-4.7.2}"
major="${GODOT_VERSION%.*}"

mkdir -p "$HOME/.config/godot"
cat > "$HOME/.config/godot/editor_settings-${major}.tres" <<TRES
[gd_resource type="EditorSettings" format=3]

[resource]
export/android/android_sdk_path = "$ANDROID_HOME"
export/android/java_sdk_path = "$JAVA_HOME"
TRES
