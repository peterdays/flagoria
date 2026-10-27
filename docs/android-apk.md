# Android test builds

A manual run of the `android-apk` workflow on `main` exports a debug-signed Android APK and publishes it as a GitHub pre-release tagged and named `v<next-minor>-test.<N>`, for example `v1.4.0-test.3`. `<next-minor>` is the highest `vX.Y.Z` release tag with the minor bumped (`v1.3.1` gives `v1.4.0`); `<N>` is one more than the highest existing test number for that version, starting at 1. `tools/next_test_tag.sh` computes the tag (`git tag -l | ./tools/next_test_tag.sh`). The release notes link the commit and, when there is one, the pull request it came from. Pushes to `main` do not publish a release.

These are test builds, debug-exported and signed with the project's stable test key. The key is stored as the `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD` and `ANDROID_KEY_ALIAS` repository secrets; a manual run fails if any of them is missing. Each build gets a higher Android version code (the workflow run number plus one), so a newer build installs over an older one. The workflow logs the APK's signing certificate SHA-256 and fails if it does not match the configured key.

Builds use the Godot 4.7.2 prebuilt Android template (target SDK 36, Android 16) and run on Android 7.0 (API 24) and newer.

## Install on a phone

1. On the phone, open the repository's **Releases** page and pick the newest pre-release.
2. Under **Assets**, tap `flagoria-<tag>-<sha>.apk` (for example `flagoria-v1.4.0-test.3-f3ea9bd.apk`; the short SHA also appears in the release notes) to download it.
3. Open the downloaded file. Android asks to allow installs from this source (the browser or file manager): enable **Install unknown apps** for it in the prompt or under *Settings > Apps > Special app access > Install unknown apps*.
4. Confirm the install and launch Flagoria.

Builds published before the stable key was introduced were each signed with a different throwaway key. If one of those is installed, uninstall it once before installing a stable-key build. After that, newer builds install in place and keep the app's data.

## Run a build manually

Open **Actions > android-apk > Run workflow** on `main`. Pull requests that touch the workflow or `export_presets.cfg` run the export only and attach the APK as a workflow artifact, without publishing a release. Pull request runs that cannot read the secrets (for example from forks) sign with a throwaway key and log a warning; that APK cannot update an installed build.
