# Contributing

## Development Setup

Install Flutter with desktop support and a Python 3 runtime that can import Pillow.

```bash
flutter pub get
flutter analyze
flutter test --coverage
```

For real package generation, provide a compatible local OTA template:

```bash
export CADILLAC_INPUT_ZIP=/path/to/your/template.zip
```

## Pull Request Checklist

- Keep changes scoped to the requested feature or fix.
- Add or update tests for behavior changes.
- Run `flutter analyze` and `flutter test --coverage`.
- Do not commit private OTA templates, generated packages, reports, local absolute paths, or build outputs.
- Update README, notices, or release docs when behavior, dependencies, or packaging changes.

## Coding Notes

- The Flutter UI must use the shared Python packager flow; do not duplicate KZB or ASTC patching rules in Dart.
- The UI should render report data instead of replacing validation with a generic success message.
- Logs and persisted library records must redact local user paths.
