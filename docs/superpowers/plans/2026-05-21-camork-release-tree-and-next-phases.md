# Camork Release Tree And Next Phases

- **Date:** 2026-05-21
- **Branch:** `rebuild/v2`
- **Release candidate:** `1.0.0 (11)`
- **Status:** feature freeze
- **Related report:** `docs/superpowers/reports/2026-05-21-release-candidate-build-11.md`

## Phase R0 — Release Candidate Freeze

Status: complete.

Exit evidence:

- `a58e7c6` pushed to `origin/rebuild/v2`.
- Build `1.0.0 (11)` archived and uploaded.
- App Store Connect shows build 11 as processed / ready for submission.
- Build 11 is assigned to internal testing.
- Unit/regression suite passes: 188 tests / 24 suites.

Rules while frozen:

- Do not add features.
- Keep new code changes tiny, local, and directly tied to an App Review, crash, data-loss, or screenshot-blocking issue.
- If a blocker requires code, bump to build 12 in a dedicated commit before archive/upload.

## Phase R1 — Screenshot And Metadata

Owner: user for screenshots; agent assists with text, review notes, and validation.

Checklist:

- Capture App Store screenshots from build 11 on real device.
- Prepare final screenshot artwork.
- Confirm app name, subtitle, promotional text, description, keywords, support URL, marketing URL if used.
- Confirm privacy policy URL is reachable.
- Confirm App Store privacy answers match actual behavior:
  - Camera: used for capture, not uploaded by the app.
  - Microphone: used for video sound, not uploaded by the app.
  - Location: stored locally as metadata when permission is granted.
  - Photos: PhotoKit not used for storage; Camork uses app sandbox storage.
  - No third-party analytics or tracking in the current app.
- Draft review notes:
  - Explain camera/location/microphone purpose.
  - Explain local-only locked album behavior.
  - Mention TestFlight/internal tester path if useful.

Exit criteria:

- Screenshots uploaded.
- Metadata complete.
- Privacy answers complete.
- Build 11 selected for version `1.0.0`.

## Phase R2 — Final Device Smoke Test

Run on the exact TestFlight build intended for review: `1.0.0 (11)`.

Must-pass flows:

- Fresh install launch.
- Camera permission prompt.
- Location permission prompt.
- Microphone permission prompt if video path is exercised.
- Photo capture.
- Flash off / auto / on on real hardware.
- Video capture with sound.
- Gallery list rendering:
  - dynamic grid for 1/2/3/4+ photos.
  - Gallery bottom chrome fade in dark mode.
  - Gallery bottom chrome fade in light mode.
- Session detail:
  - edit session name/note.
  - edit photo memo.
  - share one photo.
  - share multiple photos.
- App lock:
  - lock policy.
  - Face ID unlock.
  - background/foreground lock behavior.
- Trash:
  - photo delete / restore / purge.
  - session delete / restore / purge.
- App restart:
  - captured media persists.
  - thumbnails reload without duplicated images.

Exit criteria:

- No crash.
- No data loss.
- No blocking visual defects in App Store screenshot paths.
- No permission-copy mismatch.

## Phase R3 — App Review Submission

Submission should be a deliberate final action, not an automatic continuation.

Before submission:

- Confirm screenshots are final.
- Confirm build selected: `1.0.0 (11)` unless a blocker forced build 12.
- Confirm privacy answers.
- Confirm review notes.
- Confirm support/privacy URLs.
- Confirm age rating/export compliance/encryption answers.

Submit only after explicit user approval.

## Phase 1.0.1 — First Patch Lane

Use only after App Review feedback or first public/internal release feedback.

Candidate scope:

- App Review requested fixes.
- Crash fixes.
- Permission wording or metadata corrections.
- Screenshot mismatch fixes.
- Small UX polish that does not alter storage or capture behavior.

Avoid:

- iCloud/sync.
- Search.
- Large navigation redesign.
- Swift 6 migration.

## Phase 1.1 — Search And Organization

Candidate scope:

- Session search by name, note, date, and place.
- Better filters for deleted/active sessions.
- Optional sorting controls.
- Batch select in Gallery/Trash.

Prerequisite:

- No pending App Review blocker.
- Current storage indexes reviewed before adding query-heavy UI.

## Phase 1.2 — Cloud/Synchronization Exploration

Candidate scope:

- iCloud Drive or CloudKit evaluation.
- Encrypted export/import.
- Multi-device story.

Rules:

- Start with an ADR.
- Do not mix with release patch work.
- Re-check privacy nutrition labels before shipping.

## Phase S — Swift 6 Concurrency Cleanup

Candidate scope:

- Resolve current `AppLockController` actor initializer warnings.
- Enable stricter concurrency checking incrementally.
- Add Sendable annotations only where ownership is clear.

Rules:

- Separate from release submission.
- Keep behavior unchanged.
- Add regression tests before refactoring lock-state behavior.
