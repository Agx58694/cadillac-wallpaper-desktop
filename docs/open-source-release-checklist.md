# Open-source release checklist

Use this for the existing `Agx58694/cadillac-wallpaper-desktop` repository. Review the exact staged files before pushing source and review exact binaries before attaching them to a GitHub Release.

## Source checks

- Run `flutter analyze` and `flutter test`.
- Run `PYTHONPATH=packager python3 -m unittest discover -s packager/tests -p 'test_*.py'`.
- Run a complete native static day/night package build, inspect the final nine-file OTA ZIP and report, and test offline import with the existing installer importer.
- Build the macOS app locally where possible. In the release workflow, verify the Flutter executable, Python/Pillow runtime for **both** architectures, launcher, and `astcenc`; test both runtime slices on their native runners.
- Build Windows x64 on a Windows runner or host. Verify the Flutter executable, standalone packager CLI, `astcenc.exe`, and bundled template in the archive.
- Scan source text for local user paths. Review `git diff --cached --name-status` and `git diff --cached --check` before commit/push.

## Never stage in Git

- Any extra `packager/templates/*.zip` beyond the intentionally bundled football template.
- Generated OTA ZIP or `.cwtheme` packages, package reports, theme-library data, local work folders, image explorations, logs, caches, or build/dist output.
- Downloaded QNX, OEM APKs or firmware, user screenshots, vehicle data, credentials, or absolute user paths.
- The Android installer APK. If authorized for distribution, attach the reviewed APK to a GitHub Release **as an asset**, not to the source commit.

Use explicit `git add` paths for the source, tests, public documentation, and workflow changes. The ignore rules are a safeguard; they do not replace staged-file review.

## License and release identity

- Keep `LICENSE` and `DISCLAIMER.md` visible.
- Review distribution rights for the existing bundled football template, images, masks, icons, and `astcenc` binaries. Both desktop release packages must contain the copied Python, Pillow, and PyInstaller license texts and runtime notice under `packager_runtime/third_party_licenses*`.
- Do not bundle Winter-Star, Alps, downloaded OEM material, or user artwork.
- The existing `desktop-release.yml` uses `workflow_dispatch` and uploads **Actions artifacts**. It does not create a GitHub Release.
- Do not overwrite remote history or change repository ownership/visibility. Verify the remote main commit before pushing; then verify the pushed commit and CI run.

## Android installer attachment

The current compatible candidate is `wallpaper-studio-0.2.1-test.apk` from the separate `cadillac-wallpaper-studio-android` project. It is `com.cadillac.wallpaperstudio` version 0.2.1/code 3, debug-signed, and contains the built-in “雨夜球场 V12” sample. Source project is not a Git repository, so its build report, SHA-256, signature verification, and APK metadata are the provenance records. Publish the test/vehicle-validation boundary in release notes. The old `com.cadillac.themeinstaller` 1.0.1 app has a fixed football target and is not compatible with generated independent identities.
