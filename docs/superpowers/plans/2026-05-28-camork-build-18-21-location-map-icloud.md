# Camork Build 18-21 Plan: Location, Map, Calendar, iCloud

- **Date:** 2026-05-28
- **Branch:** `rebuild/v2`
- **Current shipped test build:** `1.0.0 (17)` on TestFlight internal testing
- **Status:** finalized planning baseline before Build 18 implementation
- **Inputs:** user real-device feedback, Build 17 handoff notes, Claude Code read-only critique controlled from Terminal, Codex final judgment

## Decision

The direction is correct: Camork needs location, map retrieval, date filtering, and iCloud continuity to become useful beyond a polished local camera.

The sequencing needs one correction: do not jump from visual polish into CloudKit without a migration safety net and a feedback gate. Build 18 must add a local export safety path and clearer local-only copy before CloudKit exists.

No external SSO should be introduced. Future sync should use the device iCloud account through CloudKit private database.

## Final Sequence

### Build 18 — Full-Bleed, Location-First, Export Safety

Goal: improve perceived quality, make location metadata real, and prevent misleading safety expectations before iCloud exists.

Scope:

- Push gallery/session chrome toward full-bleed behavior without regressing large title restoration.
- Request location only at moment of need: first capture that can use location, or first map/location feature entry.
- Capture should still succeed when location is denied, unavailable, slow, or inaccurate.
- Add reverse geocoding for `placeName` as best-effort:
  - capture-time attempt
  - no bulk geocoding
  - no hard dependency on network
  - safe retry/on-demand path later if needed
- Add `Export all` from Settings:
  - export original media files plus metadata manifest
  - write a zip/shareable package through the system share/files flow
  - make it explicit that this is the pre-iCloud backup path
- Add local-only disclosure copy until iCloud ships:
  - current records are stored on this iPhone
  - use export for backup before iCloud automatic storage is available

Acceptance:

- Fresh install does not request location at launch.
- First capture can request When In Use location with value-based copy.
- Permission denied path saves the photo/video with no geotag and no crash.
- Permission granted path stores latitude/longitude/accuracy and eventually `placeName` where available.
- Gallery/session/photo detail display no placeholder place name when reverse geocoding is unavailable.
- Export creates a restorable package containing media and metadata.
- Real-device smoke covers permission grant, denial, Settings revocation, airplane mode, and capture after revocation.

Non-goals:

- Map tab/view.
- Calendar UI.
- CloudKit.
- Search.

### Gate — Build 18 Release Decision

After Build 18 real-device verification, decide whether to:

- ship App Store `1.0` / external TestFlight with local-only/export disclosure, or
- continue internal-only until Build 19.

Do not market device migration, restore, multi-device, or "safe forever" claims before CloudKit asset sync exists.

### Build 19 — Map and Calendar

Goal: make field records findable by place and time.

Scope:

- Add a map view using session-level pins from `Session.firstLocation`.
- Pin tap opens the session detail.
- Add shared date filtering used by gallery and map:
  - today
  - this week
  - this month
  - custom calendar range
  - all
- Keep filters explicit and visible so users understand why a session is hidden.

Acceptance:

- Sessions with `firstLocation` appear on map.
- Sessions without location remain accessible from gallery and are clearly excluded from map results.
- Date filtering handles local calendar boundaries correctly.
- Gallery count and map pin count match the active filter.
- Real-device smoke covers several sessions at different locations and dates.

Non-goals:

- Photo-level pins.
- Text search.
- CloudKit.

### Build 20 — CloudKit Metadata Sync Foundation

Goal: prove sync architecture internally before any user-facing iCloud promise.

Scope:

- Create ADR before implementation:
  - CloudKit custom zone strategy
  - CKRecord schema for sessions/photos/trash state
  - conflict policy
  - account-state behavior
  - migration and rollback
  - privacy disclosure impact
- Implement metadata-only sync behind an internal/dev flag.
- All remote change application must flow through `MediaStorage`; do not introduce a second writer to GRDB.
- Add idempotent upsert/apply APIs for remote records.

Acceptance:

- Metadata round-trips between local rows and CKRecord representations.
- Conflict resolver is deterministic.
- Soft delete/trash state syncs without prematurely purging remote assets.
- Same-iCloud two-device internal test shows metadata propagation.
- No user-facing sync UI yet.

Non-goals:

- Original media CKAsset upload/download.
- Restore UX.
- Public iCloud marketing.

### Build 21 — CKAsset, Restore, User Sync UI

Goal: make iCloud continuity real and user-understandable.

Scope:

- Add Settings row/toggle for iCloud automatic storage.
- First enable requires explicit explanation:
  - what is uploaded: metadata, notes, original media
  - where: the user's iCloud private database
  - who can access it: not shared with other Camork users
  - how to disable it
- Upload original media as CKAsset.
- Restore metadata first, then lazy-download original media on demand.
- Show sync status, last sync, pending/error states, and manual sync trigger.

Acceptance:

- New iPhone with same iCloud account restores sessions and media.
- Existing installs default to sync off until the user explicitly enables it.
- New installs may recommend sync, but still require consent before upload.
- iCloud unavailable states degrade to local-only without data loss.
- App Store privacy answers are updated before release.

Non-goals:

- External login/SSO.
- Multi-user sharing.
- Custom end-to-end encryption beyond CloudKit private database behavior.

### Build 22 — Search and Organization

Search, sort, and batch organization should follow map/calendar/iCloud foundations unless user feedback indicates a stronger immediate need.

## Architecture Risks

- `capturedAt` / `createdAt` are stored as Unix seconds. Calendar filtering must be tested against local day boundaries, especially KST midnight.
- Location columns already exist on both `Session` and `Photo`; map pins can start from `Session.firstLocation` without schema change.
- `placeName` is currently not populated. Reverse geocoding must be explicitly implemented and rate-limited.
- `Session.firstLocation` can become stale if the first photo is later deleted or trashed. Treat this as an intentional v1 tradeoff unless user testing proves it confusing.
- CloudKit remote changes require idempotent upsert APIs; plain insert will fail on repeated pulls.
- Keep thumbnails local/regenerated. Do not sync thumbnails as CKAsset unless performance data requires it.

## Privacy And Review Rules

- Use When In Use location only. Do not add background location.
- Do not request location at first launch.
- Permission copy must describe concrete user value: tagging capture sites and finding sites later on a map.
- If location is denied, capture must remain fully usable.
- CloudKit upload must not be a surprise background upload. First enable requires explicit consent.
- Before shipping CloudKit media sync, update App Store privacy answers for linked user content, location, and app functionality usage.
- Keep ATT/IDFA out of scope.

## iCloud Account-State Behavior

- iCloud available and sync on: sync metadata/media, show last sync and pending state.
- iCloud available and sync off: local-only, offer Settings enablement.
- iCloud signed out: pause sync, keep local data, offer system settings deep link.
- iCloud storage full: pause uploads and surface a recoverable warning.
- iCloud account changed: stop sync and require explicit user acknowledgement before using the new account's private zone.
- MDM/parental restriction: disable sync quietly with a non-blaming unavailable state.

## Cutline Before CloudKit

Safe to ship before CloudKit:

- Full-bleed UI.
- Local location metadata and reverse geocoding.
- Map and calendar over local data.
- Export-all package.

Do not claim before CloudKit asset sync:

- automatic backup
- restore after phone replacement
- multi-device continuity
- records are "safe" beyond the current device/export path

## Apple Login / External Account Requirements

Tell the user before these steps:

- **Build 20:** Apple Developer access is required to create/verify the iCloud capability and CloudKit container for `com.camork.app`.
- **Build 21:** App Store Connect access is required to update privacy answers before shipping iCloud sync.
- **Any TestFlight/App Store upload:** Xcode/App Store Connect account authentication or API key is required. Do not submit for App Review without explicit user confirmation.

No external SSO is required for product functionality.
