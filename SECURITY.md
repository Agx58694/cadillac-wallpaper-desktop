# Security Policy

## Supported Versions

Security fixes target the current `main` branch unless a maintainer explicitly marks a release branch as supported.

## Reporting a Vulnerability

After this project is hosted on GitHub, report vulnerabilities through GitHub Security Advisories when available. If advisories are not enabled yet, contact the maintainer privately instead of opening a public issue with exploit details.

Do not include private OTA templates, generated packages, real local paths, personal files, credentials, or vehicle-identifying information in reports.

## Security Boundaries

- Treat all image files, OTA zips, `.cwtheme` files, and reports as untrusted input.
- Do not execute files from user-supplied packages.
- Keep path redaction enabled in logs and UI output.
- Do not commit private templates, generated package outputs, local app-library data, or machine-specific build caches.
- Validate output reports before using generated OTA packages.
