# Oneul 프로젝트 규칙

## 디자인 — 저작권·상표 유의 (필수)
- **다른 앱(애플 캘린더·메모, 배민, 네이버 등)의 아이콘·일러스트·고유 그래픽을 복제하지 않는다.**
- 아이콘은 **SF Symbols만** 사용(Apple 라이선스상 앱 내 UI 사용 허용). 단 **SF Symbol을 앱 아이콘(AppIcon)으로 쓰는 것은 금지**(Apple 규정) — 앱 아이콘은 자체 제작.
- 시스템 컴포넌트(리퀴드 글래스, 표준 컨트롤)와 일반적 UI 관례(주간 그리드, 타임라인 바 등)는 기능적 표현이라 사용 가능. 특정 앱의 **고유한 시각 정체성(트레이드 드레스)을 통째로 모방하는 수준**은 피한다.
- 서드파티 이미지·폰트·사운드를 넣을 땐 라이선스 확인 후 출처를 주석으로 남긴다.

## 비밀 관리
- `NEIS.swift`, `ElectiveSetupView.swift`, `PushConfig.swift`는 `skip-worktree` — 비공개 URL·키 포함, **절대 커밋 금지**.
- 새 비밀은 Cloudflare `wrangler secret` 또는 skip-worktree 로컬 파일로만.

## 빌드
- `project.yml`이 원본 — 타깃/파일 추가는 xcodegen(`xcodegen generate`)으로. Xcode에서 직접 타깃 추가 금지(재생성 시 소실).
- 커밋 전 iOS(`Oneul`)·macOS(`OneulMac`) 두 스킴 빌드 통과 확인.
