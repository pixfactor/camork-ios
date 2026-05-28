# Build 19 Follow-up

Date: 2026-05-28
Branch: `rebuild/v2`

## Requested Fixes

- iCloud alert must not expose raw `CKError` diagnostics.
- Gallery list should visually flow under the top header and bottom tab chrome more like map mode.
- Custom date filter should open a calendar, and days with recorded photos should show a small identity dot.

## Claude Critique Artifact

- `.omx/artifacts/claude-you-are-reviewing-camork-ios-swiftui-code-before-a-near-rele-2026-05-28T11-47-57-222Z.md`

## iCloud Finding

Real-device TestFlight error:

```text
CKError unknownItem: Did not find record type: CamorkSession
```

This is a Production CloudKit schema issue. Apple documents that CloudKit has separate Development and Production environments; Development can create missing record types from saved records, but Production cannot. TestFlight/App Store builds use Production, so `CamorkSession` and `CamorkPhoto` must exist in the Production schema before iCloud backup can work.

Admin checklist:

- Open CloudKit Database / Dashboard for `iCloud.com.camork.app`.
- Confirm record types exist in Development: `CamorkSession`, `CamorkPhoto`.
- Deploy schema changes to Production.
- Confirm Production has query support for full-record fetch/restore paths before relying on restore.
- Re-test TestFlight iCloud sync and restore on a clean device.

References:

- Apple iCloud Design Guide, Development vs Production environments: https://developer.apple.com/library/archive/documentation/General/Conceptual/iCloudDesignGuide/DesigningforCloudKit/DesigningforCloudKit.html
- Apple CloudKit schema management page: https://developer.apple.com/documentation/cloudkit/inspecting-and-editing-an-icloud-container-s-schema

## Code Changes

- Added `CloudSyncErrorPresentation` so Settings shows localized user-facing messages instead of raw CloudKit errors.
- Switched single-record CloudKit saves to `CKModifyRecordsOperation(savePolicy: .allKeys)` to avoid repeated sync failures from missing `recordChangeTag` on locally remapped records.
- Reworked Gallery list mode so the header is an overlay and cards scroll underneath it; removed the artificial bottom clear spacer from the list path.
- Added `GalleryCalendarFilterSheet` with a 42-cell month grid, range selection, and accent dots for days that have photo-backed sessions.
- Added tests for iCloud error classification and calendar month/day normalization.

## Remaining Manual Verification

- iCloud cannot be fully verified until the Production schema is deployed in Apple CloudKit tools.
- Visual edge behavior still needs real-device confirmation because iOS 26 scroll/tab chrome rendering differs from Simulator and Xcode canvas.
