# HERMES_DEV_NOTES — Camork (카모크)

## Project
- 이름: Camork (카모크)
- 회사 PC 경로: `~/Desktop/Personal/camork`
- 개인 Mac 권장 경로: `~/Projects/camork-ios`
- 앱 유형: iOS 카메라 앱
- 기술스택: Swift, SwiftUI, XcodeGen (project.yml 기반)

## How to run locally
- 사전 요구: Xcode 16+, XcodeGen 설치 (`brew install xcodegen`)
- 프로젝트 생성: `xcodegen generate`
- `Camork.xcodeproj` 열고 Run
- Bundle ID: `com.camork.app`
- iOS Deployment Target: 17.0

## Environment Variables
- 현재 별도 .env, API 키 파일 없음
- 카메라/마이크 권한 plist 키만 사용 (`Info.plist`)

## 주요 폴더
- `Camork/` — 앱 소스
  - `Camera/` — 카메라 캡처 로직
  - `Components/`, `Views/` — SwiftUI
  - `Features/`, `Models/`, `Services/`, `Utilities/`
  - `Camork.entitlements`, `Info.plist`
- `Camork.xcodeproj` — XcodeGen 산출물 (project.yml로 재생성 가능)
- `agent-office/` — 별도 Node.js 도구 (이 폴더의 `node_modules` 제외 필요)
- `build/` — 빌드 산출물 (제외)

## Git 상태 (회사 PC 시점)
- git 미초기화
- 이관 시 `git init` 후 `jedelpark/camork-ios`로 신규 push

## 필수 .gitignore 항목
```
# Xcode
*.xcuserdata/
*.xcworkspace/xcuserdata/
DerivedData/
build/
*.pbxuser

# XcodeGen artifact (선택 - 재생성 가능)
# Camork.xcodeproj/

# Node (agent-office)
agent-office/node_modules/
agent-office/build/

# OMC/Claude state
.omc/
.claude/
.sisyphus/
.team-os/

# macOS
.DS_Store
```

## Notes for Hermes
- XcodeGen 기반이라 `project.yml`이 진실의 원천 — `.xcodeproj`는 재생성 가능
- `agent-office/` 폴더 용도 확인 필요 (별도 도구일 가능성)
- 첫 빌드 전 `xcodegen generate` 한 번 실행
