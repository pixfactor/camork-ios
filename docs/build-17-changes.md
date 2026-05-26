# Camork 수정 내역 — Build 17 (rebuild/v2)

> 2026-05-27 실기기 피드백 대응 및 App Store Connect 업로드 준비

## 핵심 수정

- 갤러리 상하단 fade를 컨텐츠 alpha mask 방식에서 scroll edge/material overlay 방식으로 전환.
- 갤러리 상단 large title이 스크롤 복귀 후 사라지는 문제를 피하도록 시스템 scroll edge와 직접 충돌하던 fade 처리를 제거.
- 사진 상세 화면의 pager를 화면 전체 고정 영역으로 만들고, 상단/하단 chrome은 overlay로 분리해 사진별 메모 높이가 좌우 스와이프 프레임을 흔들지 않게 조정.
- 사진 메모 편집 UI를 세션 메모와 같은 `Form` + `Section` 패턴으로 통일.
- 세션 상세 메모는 기본 8행까지만 노출하고, 긴 메모는 "더보기" 시트에서 전체 내용을 확인하도록 변경.
- 사진 상세 메모는 기본 2행 노출을 유지하되, 메모 영역 탭으로 전체 내용을 읽고 별도 편집 액션으로 수정하게 분리.
- 사진 상세 시트 표시 상태를 단일 enum 기반 sheet route로 정리해 읽기 시트와 편집 시트가 동시에 경합하지 않게 보강.

## 검증

- `xcodebuild test -project Camork.xcodeproj -scheme Camork -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO`
  - 결과: `** TEST SUCCEEDED **`
  - 188 tests / 24 suites 통과.
- `xcodebuild archive -project Camork.xcodeproj -scheme Camork -configuration Release -destination 'generic/platform=iOS'`
  - 결과: `** ARCHIVE SUCCEEDED **`
  - Archive: `/Users/jedel/Projects/camork-ios/build/Camork-1.0.0-17-20260527-004327.xcarchive`
- Archive metadata 확인:
  - `CFBundleShortVersionString`: `1.0.0`
  - `CFBundleVersion`: `17`
  - Bundle ID: `com.camork.app`

## 업로드 상태

- App Store Connect upload/export는 실행했지만 로컬 Xcode 계정 인증에서 차단됨.
- 실패 로그:
  - `error: exportArchive Failed to Use Accounts`
  - `Failed to find an account with App Store Connect access for team ... teamID='RCNZ7N94S3'`
  - `App Store Connect access for "RCNZ7N94S3" is required. Ensure that your Apple Account usernames and passwords are correct in Accounts settings.`
- 제한 검색 범위에서 App Store Connect API key (`AuthKey_*.p8`)는 발견되지 않음.

## 이어서 할 일

- Xcode > Settings > Accounts에서 `RCNZ7N94S3` 팀의 App Store Connect 권한 계정 재인증 후 기존 archive 재업로드.
- 또는 App Store Connect API key (`AuthKey_*.p8`, Key ID, Issuer ID)를 사용해 `xcodebuild -exportArchive`를 재실행.
- 코드 재빌드 없이 위 archive에서 업로드만 재시도 가능.

## 빌드 번호

- `CURRENT_PROJECT_VERSION: 16` → `17`
