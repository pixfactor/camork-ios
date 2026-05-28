# Camork (카모크) — 앱 가이드

> 이 파일은 부모 `/Users/jedel/Projects/CLAUDE.md` 와 `.claude/references/apple-hig.md`를 상속한다. 공통 규칙은 거기, 이 앱 고유 사항만 여기.

## 정체성

**업무용 카메라 앱**. 일반 사진/영상과 격리된 잠긴 로컬 앨범에 업무 자료를 촬영·보관한다.

- **타겟**: 개인용이 아닌 **모든 산업의 업무 시나리오** — 특정 직군에 한정하지 않는 범용 B2B/B2P 카메라.
- **차별 가치**:
  1. 일반 사진첩과 **분리** (실수로 SNS 공유 / 가족 사진과 섞임 방지)
  2. **Face ID 잠금** (민감 업무 사진 보호)
  3. **위치·시간 메타데이터** (현장 검증/리포트 작성에 활용)
  4. **사운드 포함 동영상** (현장 기록)
- **시장**: 글로벌 출시. 1차 언어 한국어, 영어 번역 동봉.

## 디바이스 & 타겟

- **iPhone 전용**. iPad 지원하지 않음 — `project.yml` `TARGETED_DEVICE_FAMILY: "1"` 그대로 유지.
- `Info.plist`의 `UISupportedInterfaceOrientations~ipad` 는 **잔재이므로 제거 대상** (재구축 시 같이 정리).
- 세로 모드 고정 (카메라 UX는 세로 기준 설계).

## 기술 스택 (공통 가이드 + α)

- 언어/UI: Swift 5.9, SwiftUI (공통 가이드 따름)
- **카메라**: AVFoundation (`AVCaptureSession`, `AVCapturePhotoOutput`, `AVCaptureMovieFileOutput`)
- **저장**: 로컬 (앱 샌드박스 내 분리 앨범). PhotoKit 사용하지 않음 — 시스템 사진첩과 격리가 핵심.
- **보안**: LocalAuthentication (Face ID / Touch ID / 패스코드)
- **메타데이터**: CoreLocation, EXIF (촬영 시 위치·시간·디바이스 정보 임베드)
- **iOS Deployment Target**: 17.0
- Bundle ID: `com.camork.app`, Scheme: `Camork`

## 빌드 / 실행

```bash
# project.yml 수정 시 반드시
xcodegen generate

# 시뮬레이터 빌드
xcodebuild -scheme Camork \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
  build
```

- **XcodeGen 기반** — `project.yml`이 진실의 원천. `.xcodeproj`를 직접 수정하지 말 것 (재생성 시 사라짐).
- `xcodegen` 미설치 시: `brew install xcodegen`

## 디렉토리 구조 (`Camork/`)

```
Camera/        — 카메라 캡처 로직 (AVFoundation)
Views/         — SwiftUI 화면
Components/    — 재사용 UI 컴포넌트
Features/      — 기능 단위 모듈
Models/        — 데이터 모델
Services/      — 인증, 위치, 저장 등 비즈니스 서비스
Utilities/     — 유틸리티
CamorkApp.swift — App entry point
ContentView.swift
Info.plist
Camork.entitlements
```

> 위 구조는 **현 상태**의 기록일 뿐. 전면 재구축 진행 중이므로 이 섹션은 재구축 종료 시점에 다시 정렬한다.

## 권한 (Info.plist에 정의됨)

- `NSCameraUsageDescription` — 업무 사진/영상 촬영
- `NSMicrophoneUsageDescription` — 동영상 사운드
- `NSLocationWhenInUseUsageDescription` — 메타데이터
- `NSFaceIDUsageDescription` — 앱 잠금

권한 문구는 **모두 한국어 1차**. 글로벌 출시 시 InfoPlist.strings 로컬라이즈 추가.

위치 권한은 첫 실행에서 요청하지 않는다. 첫 촬영 또는 지도/위치 기반 기능 진입처럼 사용자가 위치 기록의 가치를 이해할 수 있는 시점에만 `When In Use` 권한을 요청한다. 거부되거나 사용할 수 없어도 촬영/저장은 계속 성공해야 하며, 해당 기록만 위치 메타데이터 없이 저장한다.

## 별도 영역 — `agent-office/`

루트의 `agent-office/`는 Node.js 도구로 **앱 본체와 분리**. iOS 작업 시 무시. 빌드/배포 파이프라인에 포함하지 말 것.

## 현재 상태 / 작업 모드

🚧 **전면 재구축 진행 중** (2026-05 ~). 기존 코드는 참고용일 뿐 보존 가치 낮음. 재구축 결정은 `.claude/plans/` 또는 별도 설계 문서에 누적.
