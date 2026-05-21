# Release Candidate Build 11 Report

- **Date:** 2026-05-21
- **Branch:** `rebuild/v2`
- **Release candidate:** `1.0.0 (11)`
- **Build commit:** `a58e7c6` (`Reserve build 11 as the release candidate`)
- **Purpose:** close feature development and provide the build for final TestFlight smoke testing, screenshot capture, and App Store submission preparation.

## Scope

Build 11 exists because build 10 had already been uploaded before the final Gallery chrome polish landed.

Included since build 10:

- `66df104` — Gallery tab B + content gradient polish.
- `a58e7c6` — build number bump from `10` to `11`.

No new product feature work should be added after this point unless it fixes a release blocker.

## Build And Upload Evidence

- Archive:
  `/Users/jedel/Projects/camork-ios/build/Camork-1.0.0-11-20260521-134204.xcarchive`
- Export/upload path:
  `/Users/jedel/Projects/camork-ios/build/Camork-1.0.0-11-upload-20260521-134257`
- Upload result:
  `Uploaded Camork`
- Export result:
  `** EXPORT SUCCEEDED **`

## Verification

- `xcodegen generate`
- `plutil -lint Camork/Info.plist`
- `jq empty Camork/Resources/Localizable.xcstrings`
- `xcodebuild -scheme Camork -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:CamorkTests CODE_SIGNING_ALLOWED=NO test`
  - Result: `** TEST SUCCEEDED **`
  - Test count: 188 tests / 24 suites
- `xcodebuild archive -scheme Camork -destination 'generic/platform=iOS'`
  - Result: `** ARCHIVE SUCCEEDED **`
- `xcodebuild -exportArchive`
  - Result: `Uploaded Camork` / `** EXPORT SUCCEEDED **`

## App Store Connect Status

Observed in App Store Connect after upload:

- Build upload table: `1.0.0 (11)` status `완료`
- Created: May 21, 2026 1:44 PM
- iOS build table: build `11` status `제출 준비 완료`
- Group: `Internal Testers`
- Internal tester registration: confirmed by user

## Known Non-Blocking Warnings

Archive emitted Swift concurrency warnings in `AppLockController.swift` around actor-isolated state access in an initializer. This is non-blocking under the current Swift 5.9 mode, but it should be cleared before a Swift 6 strict-concurrency migration.

Do not block the 1.0 App Store release on this unless the project changes Swift language mode.

## Release Candidate Policy

From this report forward:

- Feature work is frozen.
- Allowed changes:
  - App Review blocking bug fixes.
  - Crash fixes.
  - Incorrect permission/privacy text fixes.
  - Screenshot-blocking visual defects.
  - App Store metadata/review-note updates.
- Disallowed changes:
  - New features.
  - Large UI redesigns.
  - Storage migrations unrelated to a blocker.
  - Swift 6 migration.
  - iCloud/sync/search/analytics.

## Human Handoff

User-owned next actions:

- Install build 11 from TestFlight on a real device.
- Capture App Store screenshots from build 11.
- Prepare graphics for App Store screenshots.
- Final smoke test on the same build that will be submitted.

Agent-owned next actions, when requested:

- Prepare App Store metadata and review notes.
- Verify privacy answers against actual app behavior.
- Select build 11 for the App Store version after screenshots/metadata are ready.
- Submit for review only after user explicitly approves the final App Store submission.
