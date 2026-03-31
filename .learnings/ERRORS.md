# Errors Log

Errors encountered during development. See `/self-improvement` for format.

## 2026-03-31 — Xcode exportArchive "Copy failed" due to MacPorts rsync

- **Category:** knowledge_gap
- **What happened:** `xcodebuild -exportArchive` failed with "Copy failed" error. Root cause: MacPorts rsync 3.4.1 at `/opt/local/bin/rsync` doesn't support Apple's `-E` (extended attributes) flag. Xcode picks up the MacPorts version from PATH.
- **Rule:** When running `xcodebuild -exportArchive`, ensure Apple's `/usr/bin/rsync` is used, not MacPorts'. Fix: prepend `/usr/bin` to PATH: `PATH="/usr/bin:$PATH" xcodebuild -exportArchive ...`

## 2026-03-31 — Fastlane "invalid curve name" with App Store Connect API key

- **Category:** knowledge_gap
- **What happened:** `fastlane beta` failed with `OpenSSL::PKey::PKeyError: invalid curve name`. Known issue with Fastlane 2.232.2 + Ruby 4.0 + OpenSSL 3.x.
- **Rule:** Use `xcodebuild` CLI directly for archive + export + upload instead of Fastlane until fixed upstream.

## 2026-03-31 — GitHub push rejected for workflow files without `workflow` scope

- **Category:** knowledge_gap
- **What happened:** `git push` rejected when pushing `.github/workflows/ci.yml` — OAuth token lacked the `workflow` scope.
- **Rule:** To push GitHub Actions workflow files, the git credential must have the `workflow` scope. Either update the token or add workflow files via GitHub's web UI.
