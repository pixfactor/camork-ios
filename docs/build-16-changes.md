# Camork 수정 내역 — Build 16 (rebuild/v2)

> 2026-05-21 실기기 피드백 대응

## 핵심 수정

- 갤러리/세션 상세 하단 fade를 색 overlay가 아닌 alpha mask 기반으로 변경해 탭 캡슐 위 카드 경계를 부드럽게 처리.
- 상단 fade는 NavigationBar large-title 전환을 건드리지 않도록 overlay 기반으로 분리.
- 갤러리 루트의 큰 제목은 시스템 large title 의존을 제거하고 화면 내부 header로 고정해 스크롤 복귀 시 사라지는 문제 차단.
- 사진 상세의 `UIScrollView` pan은 zoom 상태에서만 켜지게 해, zoom 1.0 상태의 좌우 페이지 스와이프가 자연스럽게 TabView로 전달되도록 조정.
- DEBUG preview stub에 실제 샘플 JPEG 바이트를 심어 시뮬레이터에서 카드 fade와 사진 pager를 더 현실적으로 검증 가능하게 개선.

## 검증

- `xcodebuild test` equivalent via XcodeBuildMCP: 188 passed, 0 failed.
- iPhone 17 Pro simulator DEBUG stub:
  - 갤러리 상단 복귀 시 큰 `현장` header 유지 확인.
  - 하단 탭 캡슐 뒤 카드 fade 확인.
  - 사진 상세 좌우 스와이프 전환 확인.

## 빌드 번호

- `CURRENT_PROJECT_VERSION: 15` → `16`
