# Third-Party Notices

This project uses third-party software and packages. Keep this file updated when adding bundled binaries or runtime dependencies.

## Flutter and Dart Packages

Flutter, Dart, and the packages listed in `pubspec.yaml` and `pubspec.lock` are licensed by their respective authors. Generated app bundles include Flutter's aggregated `NOTICES` file.

## Arm ASTC Encoder

Bundled files:

- `packager/tools/macos/astcenc`
- `packager/tools/windows/astcenc.exe`

Project: [ARM-software/astc-encoder](https://github.com/arm-software/astc-encoder)

License: Apache License 2.0.

The upstream project states that the Arm ASTC Encoder is licensed under Apache 2.0. Keep the upstream license text available when redistributing release packages.

## Python Runtime Dependencies

The Python packager requires Pillow. Pillow is not vendored in this repository; install it in the Python runtime used by `CADILLAC_PYTHON`.

## User-Supplied OTA Templates

OTA template zips are user-supplied private inputs. They are not covered by this repository's MIT license and should not be published unless you have explicit redistribution rights.
