# Android test builds

A manual run of the `android-apk` workflow on `main` exports a debug-signed Android APK and publishes it as a GitHub pre-release named after the commit's short SHA. The release notes link the commit and, when there is one, the pull request it came from. Pushes to `main` do not publish a release.

These are test builds. They are signed with a throwaway debug key generated inside the CI job, so they are not suitable for distribution through a store.

## Install on a phone

1. On the phone, open the repository's **Releases** page and pick the newest pre-release.
2. Under **Assets**, tap `flagoria-<sha>-debug.apk` to download it.
3. Open the downloaded file. Android asks to allow installs from this source (the browser or file manager): enable **Install unknown apps** for it in the prompt or under *Settings > Apps > Special app access > Install unknown apps*.
4. Confirm the install and launch Flagoria.

Each build uses a new debug key, so installing a newer build over an older one fails with a signature conflict. Uninstall the previous version first.

## Run a build manually

Open **Actions > android-apk > Run workflow** on `main`. Pull requests that touch the workflow or `export_presets.cfg` run the export only and attach the APK as a workflow artifact, without publishing a release.
