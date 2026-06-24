# Open-Source Release Checklist

Use this checklist before creating the public GitHub repository.

## Must Pass

- `flutter analyze`
- `flutter test --coverage`
- `scripts/make_windows_build_kit.sh`
- Local path scan:

```bash
rg -n '/Users/[A-Za-z0-9._-]+|C:\\Users\\[A-Za-z0-9._-]+' \
  . -g '!build/**' -g '!dist/**' -g '!.dart_tool/**' \
  -g '!macos/Flutter/ephemeral/**' -g '!macos/Pods/**'
```

## Do Not Publish

- Any extra `packager/templates/*.zip` except the intentionally bundled football template:
  `packager/templates/BFA3A0F4596C4C57A6BCDC1EB3348932.zip`
- Generated `.cwtheme` packages
- Generated OTA zips
- `package-report.json` or `*-report.json`
- Local app-library data
- Generated design exploration images in `design-mockups/`
- `.dart_tool/`, `build/`, `dist/`, `coverage/`, `macos/Pods/`, and other generated caches
- Screenshots or logs containing real local paths

## License And Brand Checks

- Confirm the project license is still intended to be MIT.
- Confirm bundled `astcenc` binaries can be redistributed under Apache 2.0.
- Confirm every image, icon, mask, or brand-like visual asset has redistribution rights.
- Keep `DISCLAIMER.md` visible in the repository because this is an unofficial compatibility tool.

## GitHub Setup

1. Create an empty GitHub repository.
2. Initialize the local repository from this project directory.
3. Add files normally so `.gitignore` excludes generated resources.
4. Review the staged file list before the first commit.
5. Push to GitHub only after confirming no extra template zip or local path is staged.

Suggested commands:

```bash
git init
git branch -M main
git add .
git status --short
git commit -m "chore: prepare open source release"
git remote add origin git@github.com:<owner>/<repo>.git
git push -u origin main
```

Do not run the final `git push` until the repository owner, visibility, and staged file list have been confirmed.
