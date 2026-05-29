# Build 21 Release Readiness

Date: 2026-05-29
Branch: `rebuild/v2`

## CloudKit Production Schema

Production deployment was completed in CloudKit Database for container `iCloud.com.camork.app`.

Verified in the CloudKit Production environment:

- `CamorkPhoto` exists with 18 fields.
- `CamorkSession` exists with 15 fields.
- `Users` exists with 7 fields.

The deployed app schema matches `CloudRecordMapper`:

- `CamorkSession`: `name`, `note`, `createdAt`, `endedAt`, `firstLat`, `firstLon`, `firstHorizontalAccuracy`, `firstPlaceName`, `deletedAt`.
- `CamorkPhoto`: `sessionId`, `fileName`, `kind`, `capturedAt`, `lat`, `lon`, `horizontalAccuracy`, `placeName`, `exifJson`, `note`, `deletedAt`, `originalAsset`.

Important constraint: after Production deployment, CloudKit record types and fields are effectively append-only for this release line. Do not rename, remove, or change the type of deployed fields; add new optional fields instead.

## iCloud Real-Device Verification

Required manual test after the next TestFlight build:

1. Install the TestFlight build on a device signed in to iCloud.
2. Open Camork > Settings > iCloud backup.
3. Turn iCloud backup on.
4. Create a new field session with at least one photo, note, and location.
5. Tap manual sync and confirm the Settings status reports success.
6. Delete and reinstall the app, or install on another device signed in to the same iCloud account.
7. Enable iCloud backup if needed, then run restore.
8. Confirm sessions, photos, notes, timestamps, and map locations restore.
9. Confirm the app remains usable when iCloud is off or unavailable.

Do not claim device-migration reliability publicly until this full restore path passes on real hardware.

## App Review Notes

Use this note in App Review:

```text
Camork does not require an app account or third-party login.

The app can be used fully with local on-device storage. Camera access is used to capture field records. Location access is optional and is used only to tag capture locations and display field records on the map.

Optional iCloud backup uses the user's signed-in iCloud account and the app's private CloudKit database. The user must turn it on manually in Settings; Camork does not use an external server, advertising SDK, analytics SDK, or tracking.

To test iCloud backup: sign in to iCloud on the device, open Camork > Settings > iCloud backup, enable it, create/capture a field record, tap Sync now, reinstall or use another signed-in device, then tap Restore from iCloud.
```

## App Store Connect Draft State

The Korean promotional text, description, and App Review notes have been rewritten in the App Store Connect draft to describe "local by default, optional iCloud backup" instead of "device-only/no external sync".

Saving the draft is currently blocked by required App Review contact fields:

- First name
- Last name
- Phone number
- Email

Confirmed values available from the project/support pages:

- Name: `JOONGI PARK`
- Email: `parkphoto39@gmail.com`

Do not invent the phone number. Enter the real review contact phone number, then save before navigating away from the version page.

## App Privacy Answers

The App Store Connect privacy answers should match the current implementation:

- No app account is required.
- No third-party login or SSO is used.
- No advertising SDK, analytics SDK, tracking SDK, or tracking domain is used.
- Camera/photo data is user-generated content used for app functionality and optional iCloud backup.
- Location is optional and used for capture tagging, map display, and optional iCloud backup.
- Notes are user-generated content used for field records and optional iCloud backup.
- iCloud backup uses the user's signed-in iCloud account and private CloudKit database.
- The app remains usable without iCloud.

If App Store Connect asks whether collected data is linked to the user, treat CloudKit-backed user content, notes, and location as linked to the user's iCloud account for app functionality. Do not mark tracking.

## Privacy Manifest

`Camork/PrivacyInfo.xcprivacy` declares:

- `NSPrivacyAccessedAPICategoryFileTimestamp` with reason `C617.1`.
- `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1`.
- `NSPrivacyTracking` as `false`.
- No tracking domains.

This aligns with local media metadata/file operations and local settings state without claiming tracking.

## References

- Apple CloudKit schema workflow: https://developer.apple.com/documentation/cloudkit/integrating_a_text-based_schema_into_your_workflow/
- Apple CloudKit Development and Production environment behavior: https://developer.apple.com/library/archive/documentation/General/Conceptual/iCloudDesignGuide/DesigningforCloudKit/DesigningforCloudKit.html
- Apple App Privacy details: https://developer.apple.com/app-store/app-privacy-details/
- Apple App Store Connect app privacy reference: https://developer.apple.com/help/app-store-connect/reference/app-privacy/
- Apple required-reason API manifest keys: https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons
