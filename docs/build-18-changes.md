# Build 18 Changes

Date: 2026-05-28

## Scope

- Location-first capture behavior without blocking camera usage.
- Reverse-geocoded place names for location-backed sessions.
- Full-bleed gallery foundation with list/map switching and date filtering.
- Manual export-all safety net.
- CloudKit private database sync foundation for metadata and original photo assets.
- Settings UI for iCloud backup, manual sync, and restore.

## User-Visible Changes

- Camera opens when camera permission is granted even if location is not decided or denied.
- The first shutter press requests location permission when needed.
- If location is unavailable, capture still succeeds and the app shows a short notice.
- Gallery can switch between list and map views.
- Gallery can filter by all, today, this week, this month, or a custom date range.
- Settings includes a local full export archive.
- Settings includes iCloud backup controls:
  - off by default
  - hidden/shown through `CAMORKCloudSyncFeatureVisible`
  - account status check
  - manual sync now
  - manual restore from iCloud

## CloudKit Design Notes

- No external SSO was added.
- Sync uses the user's device iCloud account through CloudKit private database.
- Records:
  - `CamorkSession`
  - `CamorkPhoto`
- Original media uses `CKAsset` on the photo record.
- Local restore is idempotent:
  - sessions and photo metadata upsert by UUID
  - existing local original files are not overwritten
  - missing originals are restored through the canonical `<photo UUID>.heic` path
- `CKContainer` is created lazily so simulator unit tests without CloudKit entitlements do not crash during app bootstrap.
- The app target entitlements include `iCloud.com.camork.app` and CloudKit service. Real operation still depends on the Apple Developer App ID and provisioning profile matching those entitlements.

## Apple Developer / App Store Connect Remaining Work

- Verify or create CloudKit container `iCloud.com.camork.app`.
- Ensure the App ID for `com.camork.app` has iCloud + CloudKit capability enabled.
- Confirm provisioning profiles include:
  - `com.apple.developer.icloud-services = CloudKit`
  - `com.apple.developer.icloud-container-identifiers = iCloud.com.camork.app`
- In CloudKit Dashboard, create/deploy schema for:
  - `CamorkSession`
  - `CamorkPhoto`
- Update App Store Connect privacy answers for:
  - user content/photos
  - location
  - app functionality / iCloud sync
- Do not submit App Review until real-device iCloud sync/restore is verified.

## Verification

- `python3 -m json.tool Camork/Resources/Localizable.xcstrings`
- `xcodegen generate`
- Targeted tests:
  - `CloudRecordMapperTests`
  - `MediaStorageCloudRestoreTests`
  - `SessionDateFilterTests`
  - `ZipArchiveWriterTests`
- Full suite:
  - `xcodebuild test -project Camork.xcodeproj -scheme Camork -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO`
  - Result: 199 tests / 28 suites passed.

## Known Gaps

- Real CloudKit upload/restore is not verified until the Apple Developer container and signed TestFlight build are available.
- Conflict resolution is currently last-writer style through full-record save/upsert. A future sync engine should add per-field conflict policy and change tokens.
- Background push-driven sync is not implemented yet; current UI exposes manual sync/restore.
